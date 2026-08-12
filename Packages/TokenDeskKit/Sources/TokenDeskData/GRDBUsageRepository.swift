import Foundation
import GRDB
import TokenDeskCore

/// Stable mapping and policy failures raised by the GRDB repository boundary.
public enum UsageRepositoryError: Error, Equatable, Sendable {
    case unsupportedStoredGranularity(UsageGranularity)
    case invalidStoredValue(field: String)
}

/// A cache-first GRDB implementation with transactional upserts and retention aggregation.
public final class GRDBUsageRepository: UsageRepository, LocallyAggregatedUsageRepository,
    @unchecked Sendable
{
    private let writer: any DatabaseWriter

    /// Creates a repository over a GRDB writer configured by ``TokenDeskDatabase``.
    public init(writer: any DatabaseWriter) {
        self.writer = writer
    }

    /// Atomically upserts plan snapshots without mixing them with usage or cost values.
    public func savePlans(_ plans: [PlanWindow]) throws {
        try writer.write { database in
            for plan in plans {
                try database.execute(
                    sql: """
                        INSERT INTO plan_snapshots (
                            provider_id, account_id, plan_name, limit_identifier,
                            used_percent_decimal, window_duration_minutes, resets_at,
                            time_zone_identifier, confidence_decimal, source, source_kind,
                            updated_at, is_stale
                        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                        ON CONFLICT(provider_id, account_id, limit_identifier, resets_at, source)
                        DO UPDATE SET
                            plan_name = excluded.plan_name,
                            used_percent_decimal = excluded.used_percent_decimal,
                            window_duration_minutes = excluded.window_duration_minutes,
                            time_zone_identifier = excluded.time_zone_identifier,
                            confidence_decimal = excluded.confidence_decimal,
                            source_kind = excluded.source_kind,
                            updated_at = excluded.updated_at,
                            is_stale = excluded.is_stale
                        """,
                    arguments: [
                        plan.providerID.rawValue,
                        plan.accountID.rawValue,
                        plan.planName,
                        plan.limitIdentifier,
                        PersistenceCodec.decimal(plan.usedPercent.rawValue),
                        plan.windowDurationMinutes,
                        PersistenceCodec.date(plan.resetsAt),
                        plan.timeZoneIdentifier,
                        plan.confidence.map { PersistenceCodec.decimal($0.rawValue) },
                        plan.metadata.source.identifier,
                        plan.metadata.source.kind.rawValue,
                        PersistenceCodec.date(plan.metadata.updatedAt),
                        plan.metadata.isStale,
                    ]
                )
            }
        }
    }

    /// Atomically upserts minute, hour, or day usage buckets.
    public func saveUsage(_ usage: [TokenUsageBucket]) throws {
        try writer.write { database in
            for bucket in usage {
                try Self.upsertUsage(bucket, mergeAggregatedValues: false, in: database)
            }
        }
    }

    /// Atomically adds response-level usage without replacing other responses in the same minute.
    public func addLocallyAggregatedUsage(_ usage: [TokenUsageBucket]) throws {
        try writer.write { database in
            for bucket in usage {
                guard bucket.metadata.source.kind == .locallyAggregated else {
                    throw UsageRepositoryError.invalidStoredValue(field: "sourceKind")
                }
                try Self.upsertUsage(bucket, mergeAggregatedValues: true, in: database)
            }
        }
    }

    /// Atomically upserts official or estimated monetary snapshots.
    public func saveCosts(_ costs: [CostSnapshot]) throws {
        try writer.write { database in
            for cost in costs {
                try database.execute(
                    sql: """
                        INSERT INTO cost_buckets (
                            provider_id, account_id, project_reference, workspace_reference,
                            bucket_start_at, bucket_end_at, time_zone_identifier, amount_decimal,
                            currency, is_estimated, source, source_kind, updated_at, is_stale
                        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                        ON CONFLICT(
                            provider_id, account_id, project_reference, workspace_reference,
                            bucket_start_at, bucket_end_at, currency, source
                        ) DO UPDATE SET
                            time_zone_identifier = excluded.time_zone_identifier,
                            amount_decimal = excluded.amount_decimal,
                            is_estimated = excluded.is_estimated,
                            source_kind = excluded.source_kind,
                            updated_at = excluded.updated_at,
                            is_stale = excluded.is_stale
                        """,
                    arguments: [
                        cost.providerID.rawValue,
                        cost.accountID.rawValue,
                        cost.projectReference ?? "",
                        cost.workspaceReference ?? "",
                        PersistenceCodec.date(cost.period.interval.start),
                        PersistenceCodec.date(cost.period.interval.end),
                        cost.period.timeZoneIdentifier,
                        PersistenceCodec.decimal(cost.money.amount),
                        cost.money.currency.rawValue,
                        cost.isEstimated,
                        cost.metadata.source.identifier,
                        cost.metadata.source.kind.rawValue,
                        PersistenceCodec.date(cost.metadata.updatedAt),
                        cost.metadata.isStale,
                    ]
                )
            }
        }
    }

    /// Atomically upserts independently observed balances.
    public func saveBalances(_ balances: [BalanceSnapshot]) throws {
        try writer.write { database in
            for balance in balances {
                try database.execute(
                    sql: """
                        INSERT INTO balances (
                            provider_id, account_id, available_amount_decimal, currency,
                            total_credited_amount_decimal, total_consumed_amount_decimal,
                            observed_at, source, source_kind, updated_at, is_stale
                        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                        ON CONFLICT(provider_id, account_id, currency, observed_at, source)
                        DO UPDATE SET
                            available_amount_decimal = excluded.available_amount_decimal,
                            total_credited_amount_decimal = excluded.total_credited_amount_decimal,
                            total_consumed_amount_decimal = excluded.total_consumed_amount_decimal,
                            source_kind = excluded.source_kind,
                            updated_at = excluded.updated_at,
                            is_stale = excluded.is_stale
                        """,
                    arguments: [
                        balance.providerID.rawValue,
                        balance.accountID.rawValue,
                        PersistenceCodec.decimal(balance.available.amount),
                        balance.available.currency.rawValue,
                        balance.creditDetails.map {
                            PersistenceCodec.decimal($0.totalCredited.amount)
                        },
                        balance.creditDetails.map {
                            PersistenceCodec.decimal($0.totalConsumed.amount)
                        },
                        PersistenceCodec.date(balance.metadata.updatedAt),
                        balance.metadata.source.identifier,
                        balance.metadata.source.kind.rawValue,
                        PersistenceCodec.date(balance.metadata.updatedAt),
                        balance.metadata.isStale,
                    ]
                )
            }
        }
    }

    /// Reads overlapping cached usage in stable chronological order.
    public func cachedUsage(
        for account: AccountReference,
        in interval: DateInterval,
        granularity: UsageGranularity
    ) throws -> [TokenUsageBucket] {
        try Self.validateStored(granularity)
        return try writer.read { database in
            let rows = try Row.fetchAll(
                database,
                sql: """
                    SELECT * FROM usage_buckets
                    WHERE provider_id = ? AND account_id = ? AND granularity = ?
                        AND bucket_start_at < ? AND bucket_end_at > ?
                    ORDER BY bucket_start_at, model, project_reference, workspace_reference
                    """,
                arguments: [
                    account.providerID.rawValue,
                    account.id.rawValue,
                    granularity.rawValue,
                    PersistenceCodec.date(interval.end),
                    PersistenceCodec.date(interval.start),
                ]
            )
            return try rows.map(Self.usage(from:))
        }
    }

    /// Reads overlapping cached cost snapshots in stable chronological order.
    public func cachedCosts(
        for account: AccountReference,
        in interval: DateInterval
    ) throws -> [CostSnapshot] {
        try writer.read { database in
            let rows = try Row.fetchAll(
                database,
                sql: """
                    SELECT * FROM cost_buckets
                    WHERE provider_id = ? AND account_id = ?
                        AND bucket_start_at < ? AND bucket_end_at > ?
                    ORDER BY bucket_start_at, currency, source
                    """,
                arguments: [
                    account.providerID.rawValue,
                    account.id.rawValue,
                    PersistenceCodec.date(interval.end),
                    PersistenceCodec.date(interval.start),
                ]
            )
            return try rows.map(Self.cost(from:))
        }
    }

    /// Reads current cached plan windows for one account without inventing expired values.
    public func cachedPlans(for account: AccountReference, now: Date) throws -> [PlanWindow] {
        try writer.read { database in
            let rows = try Row.fetchAll(
                database,
                sql: """
                    SELECT * FROM plan_snapshots
                    WHERE provider_id = ? AND account_id = ? AND resets_at > ?
                    ORDER BY resets_at, limit_identifier, source
                    """,
                arguments: [
                    account.providerID.rawValue,
                    account.id.rawValue,
                    PersistenceCodec.date(now),
                ]
            )
            return try rows.map(Self.plan(from:))
        }
    }

    /// Reads retained balance observations for one account; aggregation selects the latest value.
    public func cachedBalances(for account: AccountReference) throws -> [BalanceSnapshot] {
        try writer.read { database in
            let rows = try Row.fetchAll(
                database,
                sql: """
                    SELECT * FROM balances
                    WHERE provider_id = ? AND account_id = ?
                    ORDER BY observed_at, currency, source
                    """,
                arguments: [account.providerID.rawValue, account.id.rawValue]
            )
            return try rows.map(Self.balance(from:))
        }
    }

    /// Applies 7/90/730-day aggregation and deletion in one database transaction.
    public func performRetention(now: Date) throws -> RetentionReport {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? calendar.timeZone
        guard
            let minuteCutoff = calendar.date(byAdding: .day, value: -7, to: now),
            let hourCutoff = calendar.date(byAdding: .day, value: -90, to: now),
            let dayCutoff = calendar.date(byAdding: .day, value: -730, to: now)
        else {
            throw UsageRepositoryError.invalidStoredValue(field: "retentionCutoff")
        }

        return try writer.write { database in
            let minuteRows = try Self.expiredUsage(
                granularity: .minute,
                endingOnOrBefore: minuteCutoff,
                in: database
            )
            let hourly = try Self.aggregate(minuteRows, to: .hour, updatedAt: now)
            for bucket in hourly {
                try Self.upsertUsage(bucket, mergeAggregatedValues: true, in: database)
            }
            try Self.deleteExpired(
                granularity: .minute,
                endingOnOrBefore: minuteCutoff,
                in: database
            )

            let hourRows = try Self.expiredUsage(
                granularity: .hour,
                endingOnOrBefore: hourCutoff,
                in: database
            )
            let daily = try Self.aggregate(hourRows, to: .day, updatedAt: now)
            for bucket in daily {
                try Self.upsertUsage(bucket, mergeAggregatedValues: true, in: database)
            }
            try Self.deleteExpired(
                granularity: .hour,
                endingOnOrBefore: hourCutoff,
                in: database
            )

            try Self.deleteExpired(
                granularity: .day,
                endingOnOrBefore: dayCutoff,
                in: database
            )
            let deletedDays = database.changesCount
            return RetentionReport(
                minuteRowsAggregated: minuteRows.count,
                hourRowsAggregated: hourRows.count,
                dayRowsDeleted: deletedDays
            )
        }
    }

    private static func validateStored(_ granularity: UsageGranularity) throws {
        guard [.minute, .hour, .day].contains(granularity) else {
            throw UsageRepositoryError.unsupportedStoredGranularity(granularity)
        }
    }

    private static func upsertUsage(
        _ bucket: TokenUsageBucket,
        mergeAggregatedValues: Bool,
        in database: Database
    ) throws {
        try validateStored(bucket.granularity)
        let updateTokens: String
        if mergeAggregatedValues {
            updateTokens = """
                    input_tokens = CASE WHEN usage_buckets.source_kind = 'official'
                        THEN usage_buckets.input_tokens
                        ELSE usage_buckets.input_tokens + excluded.input_tokens END,
                    output_tokens = CASE WHEN usage_buckets.source_kind = 'official'
                        THEN usage_buckets.output_tokens
                        ELSE usage_buckets.output_tokens + excluded.output_tokens END,
                    cached_input_tokens = CASE WHEN usage_buckets.source_kind = 'official'
                        THEN usage_buckets.cached_input_tokens
                        ELSE usage_buckets.cached_input_tokens + excluded.cached_input_tokens END,
                    cache_write_tokens = CASE WHEN usage_buckets.source_kind = 'official'
                        THEN usage_buckets.cache_write_tokens
                        ELSE usage_buckets.cache_write_tokens + excluded.cache_write_tokens END,
                """
        } else {
            updateTokens = """
                    input_tokens = excluded.input_tokens,
                    output_tokens = excluded.output_tokens,
                    cached_input_tokens = excluded.cached_input_tokens,
                    cache_write_tokens = excluded.cache_write_tokens,
                """
        }
        try database.execute(
            sql: """
                INSERT INTO usage_buckets (
                    provider_id, account_id, project_reference, workspace_reference, model,
                    granularity, bucket_start_at, bucket_end_at, time_zone_identifier,
                    input_tokens, output_tokens, cached_input_tokens, cache_write_tokens,
                    source, source_kind, updated_at, is_stale
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(
                    provider_id, account_id, project_reference, workspace_reference,
                    model, granularity, bucket_start_at
                ) DO UPDATE SET
                    bucket_end_at = excluded.bucket_end_at,
                    time_zone_identifier = excluded.time_zone_identifier,
                    \(updateTokens)
                    source = CASE WHEN usage_buckets.source_kind = 'official'
                        THEN usage_buckets.source ELSE excluded.source END,
                    source_kind = CASE WHEN usage_buckets.source_kind = 'official'
                        THEN usage_buckets.source_kind ELSE excluded.source_kind END,
                    updated_at = excluded.updated_at,
                    is_stale = excluded.is_stale
                """,
            arguments: [
                bucket.providerID.rawValue,
                bucket.accountID.rawValue,
                bucket.projectReference ?? "",
                bucket.workspaceReference ?? "",
                bucket.model,
                bucket.granularity.rawValue,
                PersistenceCodec.date(bucket.period.interval.start),
                PersistenceCodec.date(bucket.period.interval.end),
                bucket.period.timeZoneIdentifier,
                bucket.tokens.input.rawValue,
                bucket.tokens.output.rawValue,
                bucket.tokens.cachedInput.rawValue,
                bucket.tokens.cacheWrite.rawValue,
                bucket.metadata.source.identifier,
                bucket.metadata.source.kind.rawValue,
                PersistenceCodec.date(bucket.metadata.updatedAt),
                bucket.metadata.isStale,
            ]
        )
    }

    private static func expiredUsage(
        granularity: UsageGranularity,
        endingOnOrBefore cutoff: Date,
        in database: Database
    ) throws -> [TokenUsageBucket] {
        let rows = try Row.fetchAll(
            database,
            sql: """
                SELECT * FROM usage_buckets
                WHERE granularity = ? AND bucket_end_at <= ?
                ORDER BY bucket_start_at
                """,
            arguments: [granularity.rawValue, PersistenceCodec.date(cutoff)]
        )
        return try rows.map(usage(from:))
    }

    private static func deleteExpired(
        granularity: UsageGranularity,
        endingOnOrBefore cutoff: Date,
        in database: Database
    ) throws {
        try database.execute(
            sql: "DELETE FROM usage_buckets WHERE granularity = ? AND bucket_end_at <= ?",
            arguments: [granularity.rawValue, PersistenceCodec.date(cutoff)]
        )
    }

    private struct AggregateKey: Hashable {
        let providerID: ProviderID
        let accountID: AccountID
        let projectReference: String?
        let workspaceReference: String?
        let model: String
        let period: UsagePeriod
    }

    private static func aggregate(
        _ buckets: [TokenUsageBucket],
        to granularity: UsageGranularity,
        updatedAt: Date
    ) throws -> [TokenUsageBucket] {
        var totals: [AggregateKey: TokenBreakdown] = [:]
        for bucket in buckets {
            guard let timeZone = TimeZone(identifier: bucket.period.timeZoneIdentifier) else {
                throw UsageRepositoryError.invalidStoredValue(field: "timeZoneIdentifier")
            }
            let period = try UsagePeriod.containing(
                bucket.period.interval.start,
                granularity: granularity,
                calendar: Calendar(identifier: .gregorian),
                timeZone: timeZone
            )
            let key = AggregateKey(
                providerID: bucket.providerID,
                accountID: bucket.accountID,
                projectReference: bucket.projectReference,
                workspaceReference: bucket.workspaceReference,
                model: bucket.model,
                period: period
            )
            if let current = totals[key] {
                totals[key] = TokenBreakdown(
                    input: try current.input.adding(bucket.tokens.input),
                    output: try current.output.adding(bucket.tokens.output),
                    cachedInput: try current.cachedInput.adding(bucket.tokens.cachedInput),
                    cacheWrite: try current.cacheWrite.adding(bucket.tokens.cacheWrite)
                )
            } else {
                totals[key] = bucket.tokens
            }
        }
        let source = try DataSource(kind: .locallyAggregated, identifier: "retention_v1")
        return try totals.map { key, tokens in
            try TokenUsageBucket(
                providerID: key.providerID,
                accountID: key.accountID,
                projectReference: key.projectReference,
                workspaceReference: key.workspaceReference,
                model: key.model,
                granularity: granularity,
                period: key.period,
                tokens: tokens,
                metadata: ObservationMetadata(source: source, updatedAt: updatedAt, isStale: false)
            )
        }
    }

    private static func usage(from row: Row) throws -> TokenUsageBucket {
        let granularityRaw: String = row["granularity"]
        guard let granularity = UsageGranularity(rawValue: granularityRaw) else {
            throw UsageRepositoryError.invalidStoredValue(field: "granularity")
        }
        let sourceKindRaw: String = row["source_kind"]
        guard let sourceKind = DataSourceKind(rawValue: sourceKindRaw) else {
            throw UsageRepositoryError.invalidStoredValue(field: "sourceKind")
        }
        let projectReference: String = row["project_reference"]
        let workspaceReference: String = row["workspace_reference"]
        return try TokenUsageBucket(
            providerID: ProviderID(rawValue: row["provider_id"]),
            accountID: AccountID(rawValue: row["account_id"]),
            projectReference: projectReference.isEmpty ? nil : projectReference,
            workspaceReference: workspaceReference.isEmpty ? nil : workspaceReference,
            model: row["model"],
            granularity: granularity,
            period: UsagePeriod(
                interval: DateInterval(
                    start: try PersistenceCodec.date(row["bucket_start_at"]),
                    end: try PersistenceCodec.date(row["bucket_end_at"])
                ),
                timeZoneIdentifier: row["time_zone_identifier"]
            ),
            tokens: TokenBreakdown(
                input: try TokenCount(rawValue: row["input_tokens"]),
                output: try TokenCount(rawValue: row["output_tokens"]),
                cachedInput: try TokenCount(rawValue: row["cached_input_tokens"]),
                cacheWrite: try TokenCount(rawValue: row["cache_write_tokens"])
            ),
            metadata: ObservationMetadata(
                source: try DataSource(kind: sourceKind, identifier: row["source"]),
                updatedAt: try PersistenceCodec.date(row["updated_at"]),
                isStale: row["is_stale"]
            )
        )
    }

    private static func cost(from row: Row) throws -> CostSnapshot {
        let sourceKindRaw: String = row["source_kind"]
        guard let sourceKind = DataSourceKind(rawValue: sourceKindRaw) else {
            throw UsageRepositoryError.invalidStoredValue(field: "sourceKind")
        }
        let projectReference: String = row["project_reference"]
        let workspaceReference: String = row["workspace_reference"]
        guard let amount = PersistenceCodec.decimal(row["amount_decimal"] as String) else {
            throw UsageRepositoryError.invalidStoredValue(field: "amountDecimal")
        }
        return try CostSnapshot(
            providerID: ProviderID(rawValue: row["provider_id"]),
            accountID: AccountID(rawValue: row["account_id"]),
            projectReference: projectReference.isEmpty ? nil : projectReference,
            workspaceReference: workspaceReference.isEmpty ? nil : workspaceReference,
            period: UsagePeriod(
                interval: DateInterval(
                    start: try PersistenceCodec.date(row["bucket_start_at"]),
                    end: try PersistenceCodec.date(row["bucket_end_at"])
                ),
                timeZoneIdentifier: row["time_zone_identifier"]
            ),
            money: Money(
                amount: amount,
                currency: CurrencyCode(rawValue: row["currency"])
            ),
            metadata: ObservationMetadata(
                source: try DataSource(kind: sourceKind, identifier: row["source"]),
                updatedAt: try PersistenceCodec.date(row["updated_at"]),
                isStale: row["is_stale"]
            )
        )
    }

    private static func plan(from row: Row) throws -> PlanWindow {
        let sourceKindRaw: String = row["source_kind"]
        guard let sourceKind = DataSourceKind(rawValue: sourceKindRaw) else {
            throw UsageRepositoryError.invalidStoredValue(field: "sourceKind")
        }
        guard
            let usedPercent = PersistenceCodec.decimal(row["used_percent_decimal"] as String)
        else {
            throw UsageRepositoryError.invalidStoredValue(field: "usedPercentDecimal")
        }
        let confidenceValue = (row["confidence_decimal"] as String?).flatMap {
            PersistenceCodec.decimal($0)
        }
        return try PlanWindow(
            providerID: ProviderID(rawValue: row["provider_id"]),
            accountID: AccountID(rawValue: row["account_id"]),
            planName: row["plan_name"],
            limitIdentifier: row["limit_identifier"],
            usedPercent: UsagePercent(rawValue: usedPercent),
            windowDurationMinutes: row["window_duration_minutes"],
            resetsAt: try PersistenceCodec.date(row["resets_at"]),
            timeZoneIdentifier: row["time_zone_identifier"],
            confidence: try confidenceValue.map(SourceConfidence.init(rawValue:)),
            metadata: ObservationMetadata(
                source: try DataSource(kind: sourceKind, identifier: row["source"]),
                updatedAt: try PersistenceCodec.date(row["updated_at"]),
                isStale: row["is_stale"]
            )
        )
    }

    private static func balance(from row: Row) throws -> BalanceSnapshot {
        let sourceKindRaw: String = row["source_kind"]
        guard let sourceKind = DataSourceKind(rawValue: sourceKindRaw) else {
            throw UsageRepositoryError.invalidStoredValue(field: "sourceKind")
        }
        guard
            let amount = PersistenceCodec.decimal(row["available_amount_decimal"] as String)
        else {
            throw UsageRepositoryError.invalidStoredValue(field: "availableAmountDecimal")
        }
        let currency = try CurrencyCode(rawValue: row["currency"])
        let credited = (row["total_credited_amount_decimal"] as String?).flatMap {
            PersistenceCodec.decimal($0)
        }
        let consumed = (row["total_consumed_amount_decimal"] as String?).flatMap {
            PersistenceCodec.decimal($0)
        }
        let details: CreditBalanceDetails?
        if let credited, let consumed {
            details = try CreditBalanceDetails(
                totalCredited: Money(amount: credited, currency: currency),
                totalConsumed: Money(amount: consumed, currency: currency),
                balanceCurrency: currency
            )
        } else {
            details = nil
        }
        return BalanceSnapshot(
            providerID: try ProviderID(rawValue: row["provider_id"]),
            accountID: try AccountID(rawValue: row["account_id"]),
            available: Money(amount: amount, currency: currency),
            creditDetails: details,
            metadata: ObservationMetadata(
                source: try DataSource(kind: sourceKind, identifier: row["source"]),
                updatedAt: try PersistenceCodec.date(row["updated_at"]),
                isStale: row["is_stale"]
            )
        )
    }
}

enum PersistenceCodec {
    private static let locale = Locale(identifier: "en_US_POSIX")

    static func date(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = .gmt
        return formatter.string(from: date)
    }

    static func date(_ value: String) throws -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        guard let date = formatter.date(from: value) else {
            throw UsageRepositoryError.invalidStoredValue(field: "date")
        }
        return date
    }

    static func decimal(_ value: Decimal) -> String {
        NSDecimalNumber(decimal: value).stringValue
    }

    static func decimal(_ value: String) -> Decimal? {
        Decimal(string: value, locale: locale)
    }
}
