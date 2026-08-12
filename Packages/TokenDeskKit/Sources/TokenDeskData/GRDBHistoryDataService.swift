import Foundation
import GRDB
import TokenDeskCore

/// Validated failures surfaced by history export and lifecycle operations.
enum HistoryDataServiceError: LocalizedError, Equatable, Sendable {
    case invalidDateRange
    case unsupportedGranularity

    var errorDescription: String? {
        switch self {
        case .invalidDateRange: "导出结束时间必须晚于开始时间。"
        case .unsupportedGranularity: "导出粒度必须是分钟、小时或每日。"
        }
    }
}

/// Generates privacy-minimized exports and clears history transactionally.
public final class GRDBHistoryDataService: HistoryDataServicing, @unchecked Sendable {
    private let writer: any DatabaseWriter

    /// Creates a lifecycle service over a migrated GRDB writer.
    public init(writer: any DatabaseWriter) {
        self.writer = writer
    }

    /// Returns SQLite allocation and history counts without exposing its path.
    public func storageSnapshot() async throws -> HistoryStorageSnapshot {
        try Task.checkCancellation()
        return try await writer.read { database in
            let pageCount = try Int64.fetchOne(database, sql: "PRAGMA page_count") ?? 0
            let pageSize = try Int64.fetchOne(database, sql: "PRAGMA page_size") ?? 0
            return HistoryStorageSnapshot(
                databaseBytes: pageCount * pageSize,
                usageRows: try Self.count("usage_buckets", in: database),
                costRows: try Self.count("cost_buckets", in: database),
                planRows: try Self.count("plan_snapshots", in: database),
                balanceRows: try Self.count("balances", in: database)
            )
        }
    }

    /// Reads filtered usage and cost records and serializes only approved fields.
    public func makeExport(
        format: HistoryExportFormat,
        request: HistoryExportRequest
    ) async throws -> HistoryExportPayload {
        guard request.interval.duration > 0 else {
            throw HistoryDataServiceError.invalidDateRange
        }
        let supported: Set<UsageGranularity> = [.minute, .hour, .day]
        guard request.granularities.isSubset(of: supported) else {
            throw HistoryDataServiceError.unsupportedGranularity
        }
        try Task.checkCancellation()
        let records = try await writer.read { database in
            var records = try Self.usageRecords(request: request, in: database)
            try Task.checkCancellation()
            records.append(contentsOf: try Self.costRecords(request: request, in: database))
            records.sort {
                ($0.time, $0.dataType, $0.provider, $0.accountAlias, $0.model ?? "")
                    < ($1.time, $1.dataType, $1.provider, $1.accountAlias, $1.model ?? "")
            }
            return records
        }
        try Task.checkCancellation()
        let data: Data
        switch format {
        case .csv:
            data = try Self.csv(records)
        case .json:
            data = try Self.json(records)
        }
        try Task.checkCancellation()
        return HistoryExportPayload(data: data, recordCount: records.count)
    }

    /// Deletes Provider-scoped or complete history in one transaction.
    public func clearHistory(scope: HistoryClearScope) async throws -> HistoryClearReport {
        try Task.checkCancellation()
        return try await writer.write { database in
            let providerID: String?
            switch scope {
            case .provider(let id): providerID = id.rawValue
            case .all: providerID = nil
            }

            let usage = try Self.delete(from: "usage_buckets", providerID: providerID, in: database)
            try Task.checkCancellation()
            let costs = try Self.delete(from: "cost_buckets", providerID: providerID, in: database)
            let plans = try Self.delete(
                from: "plan_snapshots", providerID: providerID, in: database)
            let balances = try Self.delete(from: "balances", providerID: providerID, in: database)
            let alerts: Int
            if let providerID {
                try database.execute(
                    sql: """
                        DELETE FROM alert_events
                        WHERE rule_id IN (SELECT id FROM alert_rules WHERE provider_id = ?)
                        """,
                    arguments: [providerID]
                )
                alerts = database.changesCount
            } else {
                try database.execute(sql: "DELETE FROM alert_events")
                alerts = database.changesCount
            }
            try Task.checkCancellation()
            return HistoryClearReport(
                deletedUsageRows: usage,
                deletedCostRows: costs,
                deletedPlanRows: plans,
                deletedBalanceRows: balances,
                deletedAlertEventRows: alerts
            )
        }
    }

    private static func usageRecords(
        request: HistoryExportRequest,
        in database: Database
    ) throws -> [ExportRecord] {
        let cursor = try Row.fetchCursor(
            database,
            sql: """
                SELECT
                    u.bucket_start_at, p.display_name AS provider_name,
                    a.display_name AS account_name, u.model, u.granularity,
                    u.input_tokens, u.output_tokens, u.cached_input_tokens,
                    u.cache_write_tokens, u.source_kind
                FROM usage_buckets u
                JOIN providers p ON p.id = u.provider_id
                JOIN accounts a ON a.id = u.account_id AND a.provider_id = u.provider_id
                WHERE u.bucket_start_at < ? AND u.bucket_end_at > ?
                    AND (? IS NULL OR u.provider_id = ?)
                    AND (? IS NULL OR u.account_id = ?)
                    AND (? IS NULL OR u.project_reference = ?)
                ORDER BY u.bucket_start_at, p.display_name, a.display_name, u.model
                """,
            arguments: [
                PersistenceCodec.date(request.interval.end),
                PersistenceCodec.date(request.interval.start),
                request.providerID?.rawValue,
                request.providerID?.rawValue,
                request.accountID?.rawValue,
                request.accountID?.rawValue,
                request.projectReference,
                request.projectReference,
            ]
        )
        var result: [ExportRecord] = []
        while let row = try cursor.next() {
            try Task.checkCancellation()
            guard
                let granularity = UsageGranularity(rawValue: row["granularity"]),
                request.granularities.contains(granularity)
            else { continue }
            let sourceKind: String = row["source_kind"]
            result.append(
                ExportRecord(
                    time: row["bucket_start_at"],
                    dataType: "usage",
                    provider: row["provider_name"],
                    accountAlias: row["account_name"],
                    model: row["model"],
                    granularity: granularity.rawValue,
                    inputTokens: row["input_tokens"],
                    outputTokens: row["output_tokens"],
                    cachedInputTokens: row["cached_input_tokens"],
                    cacheWriteTokens: row["cache_write_tokens"],
                    cost: nil,
                    currency: nil,
                    dataSource: sourceKind,
                    isEstimated: sourceKind == DataSourceKind.estimated.rawValue
                )
            )
        }
        return result
    }

    private static func costRecords(
        request: HistoryExportRequest,
        in database: Database
    ) throws -> [ExportRecord] {
        let cursor = try Row.fetchCursor(
            database,
            sql: """
                SELECT
                    c.bucket_start_at, p.display_name AS provider_name,
                    a.display_name AS account_name, c.amount_decimal, c.currency,
                    c.is_estimated, c.source_kind
                FROM cost_buckets c
                JOIN providers p ON p.id = c.provider_id
                JOIN accounts a ON a.id = c.account_id AND a.provider_id = c.provider_id
                WHERE c.bucket_start_at < ? AND c.bucket_end_at > ?
                    AND (? IS NULL OR c.provider_id = ?)
                    AND (? IS NULL OR c.account_id = ?)
                    AND (? IS NULL OR c.project_reference = ?)
                ORDER BY c.bucket_start_at, p.display_name, a.display_name, c.currency
                """,
            arguments: [
                PersistenceCodec.date(request.interval.end),
                PersistenceCodec.date(request.interval.start),
                request.providerID?.rawValue,
                request.providerID?.rawValue,
                request.accountID?.rawValue,
                request.accountID?.rawValue,
                request.projectReference,
                request.projectReference,
            ]
        )
        var result: [ExportRecord] = []
        while let row = try cursor.next() {
            try Task.checkCancellation()
            let sourceKind: String = row["source_kind"]
            result.append(
                ExportRecord(
                    time: row["bucket_start_at"],
                    dataType: "cost",
                    provider: row["provider_name"],
                    accountAlias: row["account_name"],
                    model: nil,
                    granularity: nil,
                    inputTokens: nil,
                    outputTokens: nil,
                    cachedInputTokens: nil,
                    cacheWriteTokens: nil,
                    cost: row["amount_decimal"],
                    currency: row["currency"],
                    dataSource: sourceKind,
                    isEstimated: row["is_estimated"]
                )
            )
        }
        return result
    }

    private static func csv(_ records: [ExportRecord]) throws -> Data {
        let columns = [
            "时间", "数据类型", "Provider", "账户别名", "模型", "粒度", "输入Token",
            "输出Token", "缓存读取Token", "缓存写入Token", "费用", "币种", "数据来源", "是否估算",
        ]
        var lines = [columns.joined(separator: ",")]
        lines.reserveCapacity(records.count + 1)
        for record in records {
            try Task.checkCancellation()
            lines.append(
                [
                    record.time, record.dataType, record.provider, record.accountAlias,
                    record.model, record.granularity, record.inputTokens.map(String.init),
                    record.outputTokens.map(String.init),
                    record.cachedInputTokens.map(String.init),
                    record.cacheWriteTokens.map(String.init), record.cost, record.currency,
                    record.dataSource, record.isEstimated ? "true" : "false",
                ].map(csvField).joined(separator: ",")
            )
        }
        return Data([0xEF, 0xBB, 0xBF]) + Data((lines.joined(separator: "\n") + "\n").utf8)
    }

    private static func json(_ records: [ExportRecord]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        var data = Data("[\n".utf8)
        for (index, record) in records.enumerated() {
            try Task.checkCancellation()
            data.append(Data("  ".utf8))
            data.append(try encoder.encode(record))
            if index < records.count - 1 {
                data.append(Data(",".utf8))
            }
            data.append(Data("\n".utf8))
        }
        data.append(Data("]\n".utf8))
        return data
    }

    private static func csvField(_ value: String?) -> String {
        guard let value else { return "" }
        return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    private static func count(_ table: String, in database: Database) throws -> Int {
        try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM \(table)") ?? 0
    }

    private static func delete(
        from table: String,
        providerID: String?,
        in database: Database
    ) throws -> Int {
        if let providerID {
            try database.execute(
                sql: "DELETE FROM \(table) WHERE provider_id = ?",
                arguments: [providerID]
            )
        } else {
            try database.execute(sql: "DELETE FROM \(table)")
        }
        return database.changesCount
    }
}

private struct ExportRecord: Codable, Sendable {
    let time: String
    let dataType: String
    let provider: String
    let accountAlias: String
    let model: String?
    let granularity: String?
    let inputTokens: Int64?
    let outputTokens: Int64?
    let cachedInputTokens: Int64?
    let cacheWriteTokens: Int64?
    let cost: String?
    let currency: String?
    let dataSource: String
    let isEstimated: Bool
}
