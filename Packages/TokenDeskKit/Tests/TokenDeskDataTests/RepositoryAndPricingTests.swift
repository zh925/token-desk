import Foundation
import GRDB
import Testing
import TokenDeskCore
import TokenDeskData

@Test
func repositoryReturnsCachedUsageAndCostsWithoutPrecisionLoss() throws {
    let fixture = try RepositoryFixture()
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    let usage = try fixture.usage(
        start: start,
        granularity: .minute,
        input: 123,
        output: 456,
        cachedInput: 789,
        cacheWrite: 12,
        workspaceReference: "workspace"
    )
    let cost = CostSnapshot(
        providerID: fixture.providerID,
        accountID: fixture.account.id,
        projectReference: "project",
        workspaceReference: "workspace",
        period: usage.period,
        money: Money(
            amount: Decimal(string: "0.123456789012345678")!,
            currency: try CurrencyCode(rawValue: "USD")
        ),
        metadata: usage.metadata
    )

    try fixture.repository.saveUsage([usage])
    try fixture.repository.saveCosts([cost])

    let interval = DateInterval(start: start, duration: 120)
    let cachedUsage = try fixture.repository.cachedUsage(
        for: fixture.account,
        in: interval,
        granularity: .minute
    )
    let cachedCosts = try fixture.repository.cachedCosts(for: fixture.account, in: interval)

    #expect(cachedUsage == [usage])
    #expect(cachedCosts == [cost])
}

@Test
func repositoryBatchWriteRollsBackWhenAnyBucketIsInvalid() throws {
    let fixture = try RepositoryFixture()
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    let valid = try fixture.usage(start: start, granularity: .minute, input: 1)
    let invalid = try fixture.usage(start: start, granularity: .week, input: 2)

    #expect(throws: UsageRepositoryError.self) {
        try fixture.repository.saveUsage([valid, invalid])
    }

    let cached = try fixture.repository.cachedUsage(
        for: fixture.account,
        in: DateInterval(start: start, duration: 120),
        granularity: .minute
    )
    #expect(cached.isEmpty)
}

@Test
func responseUsageAddsConcurrentCallsIntoOneLocalMinuteBucket() async throws {
    let fixture = try RepositoryFixture()
    let start = Date(timeIntervalSince1970: 1_800_000_030)
    let usage = try fixture.usage(
        start: start,
        granularity: .minute,
        input: 10,
        output: 2,
        cachedInput: 3,
        sourceKind: .locallyAggregated
    )

    try await withThrowingTaskGroup(of: Void.self) { group in
        for _ in 0..<20 {
            group.addTask {
                try fixture.repository.addLocallyAggregatedUsage([usage])
            }
        }
        try await group.waitForAll()
    }

    let cached = try fixture.repository.cachedUsage(
        for: fixture.account,
        in: DateInterval(start: start.addingTimeInterval(-30), duration: 120),
        granularity: .minute
    )
    let bucket = try #require(cached.first)
    #expect(cached.count == 1)
    #expect(bucket.tokens.input.rawValue == 200)
    #expect(bucket.tokens.output.rawValue == 40)
    #expect(bucket.tokens.cachedInput.rawValue == 60)
    #expect(bucket.metadata.source.kind == .locallyAggregated)
}

@Test
func repositoryPersistsOptionalCumulativeCreditDetailsSeparatelyFromAvailableBalance() throws {
    let fixture = try RepositoryFixture()
    let currency = try CurrencyCode(rawValue: "USD")
    let observedAt = Date(timeIntervalSince1970: 1_800_000_000)
    let balance = BalanceSnapshot(
        providerID: fixture.providerID,
        accountID: fixture.account.id,
        available: Money(amount: Decimal(string: "21.25")!, currency: currency),
        creditDetails: try CreditBalanceDetails(
            totalCredited: Money(amount: Decimal(string: "25.50")!, currency: currency),
            totalConsumed: Money(amount: Decimal(string: "4.25")!, currency: currency),
            balanceCurrency: currency
        ),
        metadata: ObservationMetadata(
            source: try DataSource(kind: .official, identifier: "credits_api"),
            updatedAt: observedAt,
            isStale: false
        )
    )

    try fixture.repository.saveBalances([balance])

    let values = try fixture.database.read { database in
        try Row.fetchOne(database, sql: "SELECT * FROM balances")
    }
    #expect(values?["available_amount_decimal"] as String? == "21.25")
    #expect(values?["total_credited_amount_decimal"] as String? == "25.5")
    #expect(values?["total_consumed_amount_decimal"] as String? == "4.25")
    #expect(try fixture.repository.cachedBalances(for: fixture.account) == [balance])
}

@Test
func repositoryReturnsOnlyCurrentPlanWindowsForDashboardCache() throws {
    let fixture = try RepositoryFixture()
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let metadata = ObservationMetadata(
        source: try DataSource(kind: .estimated, identifier: "local_plan_estimate"),
        updatedAt: now,
        isStale: false
    )
    let current = try PlanWindow(
        providerID: fixture.providerID,
        accountID: fixture.account.id,
        planName: "Current",
        limitIdentifier: "primary",
        usedPercent: UsagePercent(rawValue: 42),
        windowDurationMinutes: 300,
        resetsAt: now.addingTimeInterval(3_600),
        timeZoneIdentifier: "UTC",
        confidence: SourceConfidence(rawValue: Decimal(string: "0.8")!),
        metadata: metadata
    )
    let expired = try PlanWindow(
        providerID: fixture.providerID,
        accountID: fixture.account.id,
        planName: "Expired",
        limitIdentifier: "old",
        usedPercent: UsagePercent(rawValue: 100),
        windowDurationMinutes: 300,
        resetsAt: now.addingTimeInterval(-1),
        timeZoneIdentifier: "UTC",
        metadata: metadata
    )
    try fixture.repository.savePlans([current, expired])

    #expect(try fixture.repository.cachedPlans(for: fixture.account, now: now) == [current])
}

@Test
func retentionAggregatesBeforeDeletingAcrossSevenNinetyAndSevenHundredThirtyDays() throws {
    let fixture = try RepositoryFixture()
    let now = Date(timeIntervalSince1970: 2_000_000_000)
    let oldMinuteHour = now.addingTimeInterval(-8 * 86_400)
    let firstMinute = try fixture.usage(
        start: oldMinuteHour,
        granularity: .minute,
        input: 10,
        output: 1
    )
    let secondMinute = try fixture.usage(
        start: oldMinuteHour.addingTimeInterval(60),
        granularity: .minute,
        input: 20,
        output: 2
    )
    let recentMinute = try fixture.usage(
        start: now.addingTimeInterval(-86_400),
        granularity: .minute,
        input: 30
    )
    let oldHour = try fixture.usage(
        start: now.addingTimeInterval(-100 * 86_400),
        granularity: .hour,
        input: 40
    )
    let expiredDay = try fixture.usage(
        start: now.addingTimeInterval(-800 * 86_400),
        granularity: .day,
        input: 50
    )
    try fixture.repository.saveUsage([
        firstMinute, secondMinute, recentMinute, oldHour, expiredDay,
    ])

    let report = try fixture.repository.performRetention(now: now)

    #expect(report.minuteRowsAggregated == 2)
    #expect(report.hourRowsAggregated == 1)
    #expect(report.dayRowsDeleted == 1)

    let allTime = DateInterval(start: now.addingTimeInterval(-900 * 86_400), end: now)
    let minutes = try fixture.repository.cachedUsage(
        for: fixture.account,
        in: allTime,
        granularity: .minute
    )
    let hours = try fixture.repository.cachedUsage(
        for: fixture.account,
        in: allTime,
        granularity: .hour
    )
    let days = try fixture.repository.cachedUsage(
        for: fixture.account,
        in: allTime,
        granularity: .day
    )

    #expect(minutes.map(\.tokens.input.rawValue) == [30])
    #expect(hours.count == 1)
    #expect(hours[0].tokens.input.rawValue == 30)
    #expect(hours[0].tokens.output.rawValue == 3)
    #expect(hours[0].metadata.source.kind == .locallyAggregated)
    #expect(days.count == 1)
    #expect(days[0].tokens.input.rawValue == 40)
}

@Test
func pricingCatalogSelectsEffectiveExactVersionAndCalculatorMetersEveryCategory() throws {
    let fixture = try RepositoryFixture()
    let catalog = GRDBPricingCatalog(writer: fixture.database)
    let providerType = try ProviderType(rawValue: "example")
    let currency = try CurrencyCode(rawValue: "USD")
    let source = try DataSource(kind: .official, identifier: "provider_pricing_page")
    let epoch = Date(timeIntervalSince1970: 0)
    let boundary = Date(timeIntervalSince1970: 1_200)
    let v1 = try PricingRule(
        id: "example-v1",
        providerType: providerType,
        modelMatch: "model-a",
        currency: currency,
        region: "global",
        version: 1,
        effectiveFrom: epoch,
        effectiveTo: boundary,
        rates: TokenRates(input: 1, output: 2, cacheRead: 0.25, cacheWrite: 0.5),
        source: source,
        updatedAt: epoch
    )
    let v2 = try PricingRule(
        id: "example-v2",
        providerType: providerType,
        modelMatch: "model-a",
        currency: currency,
        region: "global",
        version: 2,
        effectiveFrom: boundary,
        rates: TokenRates(input: 2, output: 8, cacheRead: 0.5, cacheWrite: 1),
        source: source,
        updatedAt: boundary
    )
    try catalog.upsert([v1, v2])

    #expect(
        try catalog.rule(
            providerType: providerType,
            model: "model-a",
            currency: currency,
            region: "CN",
            effectiveAt: boundary.addingTimeInterval(-1)
        )?.id == "example-v1"
    )
    let selectedRule = try catalog.rule(
        providerType: providerType,
        model: "model-a",
        currency: currency,
        region: "CN",
        effectiveAt: boundary
    )
    let selected = try #require(selectedRule)
    #expect(selected == v2)

    let usage = try fixture.usage(
        start: boundary,
        granularity: .minute,
        input: 500_000,
        output: 250_000,
        cachedInput: 1_000_000,
        cacheWrite: 2_000_000
    )
    let estimate = try CostCalculator().estimate(
        usage: usage,
        providerType: providerType,
        rule: selected,
        at: boundary
    )

    #expect(estimate.money.amount == Decimal(string: "5.5")!)
    #expect(estimate.money.currency == currency)
    #expect(estimate.isEstimated)
    #expect(estimate.metadata.source.identifier == "pricing_catalog:example-v2:v2")

    let official = CostSnapshot(
        providerID: fixture.providerID,
        accountID: fixture.account.id,
        period: usage.period,
        money: Money(amount: 99, currency: currency),
        metadata: ObservationMetadata(
            source: try DataSource(kind: .official, identifier: "official_cost_api"),
            updatedAt: boundary,
            isStale: false
        )
    )
    let resolved = try CostCalculator().resolve(
        officialCosts: [official],
        usage: usage,
        providerType: providerType,
        currency: currency,
        region: "CN",
        catalog: catalog,
        calculatedAt: boundary
    )
    #expect(resolved == [official])
}

private struct RepositoryFixture {
    let database: DatabaseQueue
    let repository: GRDBUsageRepository
    let providerID: ProviderID
    let account: AccountReference

    init() throws {
        database = try DatabaseQueue(configuration: TokenDeskDatabase.configuration)
        try TokenDeskDatabaseMigrator.migrate(database)
        providerID = try ProviderID(rawValue: "provider")
        account = try AccountReference(
            id: AccountID(rawValue: "account"),
            providerID: providerID,
            displayName: "Fixture Account",
            scope: .personal
        )
        repository = GRDBUsageRepository(writer: database)
        let timestamp = "2026-08-12T00:00:00Z"
        try database.write { database in
            try database.execute(
                sql: """
                    INSERT INTO providers (
                        id, type, display_name, refresh_interval_seconds, created_at, updated_at
                    ) VALUES (?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    providerID.rawValue, "example", "Fixture Provider", 60, timestamp, timestamp,
                ]
            )
            try database.execute(
                sql: """
                    INSERT INTO accounts (
                        id, provider_id, display_name, scope, deduplication_key,
                        created_at, updated_at
                    ) VALUES (?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    account.id.rawValue,
                    providerID.rawValue,
                    account.displayName,
                    account.scope.rawValue,
                    "fixture-account",
                    timestamp,
                    timestamp,
                ]
            )
        }
    }

    func usage(
        start: Date,
        granularity: UsageGranularity,
        input: Int64,
        output: Int64 = 0,
        cachedInput: Int64 = 0,
        cacheWrite: Int64 = 0,
        sourceKind: DataSourceKind = .official,
        workspaceReference: String? = nil
    ) throws -> TokenUsageBucket {
        let timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let period = try UsagePeriod.containing(
            start,
            granularity: granularity,
            calendar: Calendar(identifier: .gregorian),
            timeZone: timeZone
        )
        return try TokenUsageBucket(
            providerID: providerID,
            accountID: account.id,
            projectReference: "project",
            workspaceReference: workspaceReference,
            model: "model-a",
            granularity: granularity,
            period: period,
            tokens: TokenBreakdown(
                input: TokenCount(rawValue: input),
                output: TokenCount(rawValue: output),
                cachedInput: TokenCount(rawValue: cachedInput),
                cacheWrite: TokenCount(rawValue: cacheWrite)
            ),
            metadata: ObservationMetadata(
                source: DataSource(kind: sourceKind, identifier: "fixture_usage"),
                updatedAt: start,
                isStale: false
            )
        )
    }
}
