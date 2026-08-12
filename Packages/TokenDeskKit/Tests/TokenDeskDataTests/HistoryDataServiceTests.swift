import Foundation
import GRDB
import Testing
import TokenDeskCore
import TokenDeskData

@Test
func historyExportFiltersRowsUsesWhitelistAndPreservesExactValues() async throws {
    let fixture = try HistoryFixture()
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    try fixture.seedObservations(start: start)
    let request = HistoryExportRequest(
        interval: DateInterval(start: start, duration: 3_600),
        providerID: fixture.providerID,
        accountID: fixture.accountID,
        projectReference: "project-sensitive",
        granularities: [.minute]
    )

    let csv = try await fixture.service.makeExport(format: .csv, request: request)
    #expect(csv.recordCount == 2)
    #expect(Array(csv.data.prefix(3)) == [0xEF, 0xBB, 0xBF])
    let csvText = try #require(String(data: csv.data, encoding: .utf8))
    #expect(csvText.contains("团队,中文"))
    #expect(csvText.contains("0.123456789012345678"))
    #expect(csvText.contains("1234567890123"))
    #expect(!csvText.contains("project-sensitive"))
    #expect(!csvText.contains("remote-account-sensitive"))
    #expect(!csvText.contains("keychain-sensitive"))
    #expect(!csvText.contains("source-sensitive"))
    #expect(!csvText.localizedCaseInsensitiveContains("prompt"))

    let json = try await fixture.service.makeExport(format: .json, request: request)
    let object = try #require(
        JSONSerialization.jsonObject(with: json.data) as? [[String: Any]]
    )
    #expect(object.count == 2)
    let keys = Set(object.flatMap(\.keys))
    #expect(
        keys.isSubset(of: [
            "time", "dataType", "provider", "accountAlias", "model", "granularity",
            "inputTokens", "outputTokens", "cachedInputTokens", "cacheWriteTokens", "cost",
            "currency", "dataSource", "isEstimated",
        ])
    )
    #expect(object.contains { $0["dataType"] as? String == "usage" })
    #expect(object.contains { $0["dataType"] as? String == "cost" })
}

@Test
func historyExportGranularityAndAccountFiltersExcludeOtherRows() async throws {
    let fixture = try HistoryFixture()
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    try fixture.seedObservations(start: start)
    let hour = try fixture.usage(start: start, granularity: .hour, input: 99)
    try fixture.repository.saveUsage([hour])
    _ = try fixture.addOtherProvider(start: start)

    let minute = try await fixture.service.makeExport(
        format: .json,
        request: HistoryExportRequest(
            interval: DateInterval(start: start, duration: 7_200),
            providerID: fixture.providerID,
            accountID: fixture.accountID,
            granularities: [.minute]
        )
    )
    let records = try #require(
        JSONSerialization.jsonObject(with: minute.data) as? [[String: Any]]
    )
    #expect(!records.contains { $0["granularity"] as? String == "hour" })
    #expect(records.contains { $0["granularity"] as? String == "minute" })
    #expect(!records.contains { $0["model"] as? String == "other-model" })
}

@Test
func historyExportHandlesThousandsOfRowsWithoutChangingTokenValues() async throws {
    let fixture = try HistoryFixture()
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    let rows = try (0..<2_500).map { offset in
        try fixture.usage(
            start: start.addingTimeInterval(Double(offset) * 60),
            granularity: .minute,
            input: Int64(offset)
        )
    }
    try fixture.repository.saveUsage(rows)

    let export = try await fixture.service.makeExport(
        format: .csv,
        request: HistoryExportRequest(
            interval: DateInterval(start: start, duration: 2_500 * 60),
            accountID: fixture.accountID,
            granularities: [.minute]
        )
    )

    #expect(export.recordCount == 2_500)
    let text = try #require(String(data: export.data, encoding: .utf8))
    #expect(text.contains("\"2499\""))
}

@Test
func storageAndHistoryClearAreScopedTransactionalAndCancellationAware() async throws {
    let fixture = try HistoryFixture()
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    try fixture.seedObservations(start: start)
    let other = try fixture.addOtherProvider(start: start)

    let before = try await fixture.service.storageSnapshot()
    #expect(before.databaseBytes > 0)
    #expect(before.usageRows == 2)
    #expect(before.costRows == 2)
    #expect(before.retentionPolicy == .productDefault)

    let scoped = try await fixture.service.clearHistory(scope: .provider(fixture.providerID))
    #expect(scoped.deletedUsageRows == 1)
    #expect(scoped.deletedCostRows == 1)
    let afterScoped = try await fixture.service.storageSnapshot()
    #expect(afterScoped.usageRows == 1)
    #expect(afterScoped.costRows == 1)

    let all = try await fixture.service.clearHistory(scope: .all)
    #expect(all.deletedUsageRows == 1)
    #expect(all.deletedCostRows == 1)
    let settingsRemain = try await fixture.database.read { database in
        try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM accounts") ?? 0
    }
    #expect(settingsRemain == 2)
    _ = other

    let cancelled = Task {
        try await fixture.service.makeExport(
            format: .json,
            request: HistoryExportRequest(
                interval: DateInterval(start: start, duration: 60),
                granularities: [.minute]
            )
        )
    }
    cancelled.cancel()
    do {
        _ = try await cancelled.value
        Issue.record("A cancelled export must throw CancellationError")
    } catch is CancellationError {
        // Expected: cancellation is never converted into a generic export failure.
    }
}

private struct HistoryFixture {
    let database: DatabaseQueue
    let repository: GRDBUsageRepository
    let service: GRDBHistoryDataService
    let providerID: ProviderID
    let accountID: AccountID

    init() throws {
        database = try DatabaseQueue(configuration: TokenDeskDatabase.configuration)
        try TokenDeskDatabaseMigrator.migrate(database)
        repository = GRDBUsageRepository(writer: database)
        service = GRDBHistoryDataService(writer: database)
        providerID = try ProviderID(rawValue: "provider-local")
        accountID = try AccountID(rawValue: "account-local")
        try insertAccount(
            providerID: providerID,
            accountID: accountID,
            providerName: "示例 Provider",
            accountName: "团队,中文"
        )
    }

    func seedObservations(start: Date) throws {
        let usage = try usage(start: start, granularity: .minute, input: 1_234_567_890_123)
        let cost = CostSnapshot(
            providerID: providerID,
            accountID: accountID,
            projectReference: "project-sensitive",
            period: usage.period,
            money: Money(
                amount: try #require(Decimal(string: "0.123456789012345678")),
                currency: try CurrencyCode(rawValue: "USD")
            ),
            metadata: usage.metadata
        )
        try repository.saveUsage([usage])
        try repository.saveCosts([cost])
    }

    func addOtherProvider(start: Date) throws -> ProviderID {
        let providerID = try ProviderID(rawValue: "other-provider")
        let accountID = try AccountID(rawValue: "other-account")
        try insertAccount(
            providerID: providerID,
            accountID: accountID,
            providerName: "Other",
            accountName: "Other Alias"
        )
        let period = try period(start: start, granularity: .minute)
        let metadata = ObservationMetadata(
            source: try DataSource(kind: .official, identifier: "other-source"),
            updatedAt: start,
            isStale: false
        )
        try repository.saveUsage([
            try TokenUsageBucket(
                providerID: providerID,
                accountID: accountID,
                model: "other-model",
                granularity: .minute,
                period: period,
                tokens: TokenBreakdown(input: try TokenCount(rawValue: 1), output: .zero),
                metadata: metadata
            )
        ])
        try repository.saveCosts([
            CostSnapshot(
                providerID: providerID,
                accountID: accountID,
                period: period,
                money: Money(amount: 1, currency: try CurrencyCode(rawValue: "CNY")),
                metadata: metadata
            )
        ])
        return providerID
    }

    func usage(
        start: Date,
        granularity: UsageGranularity,
        input: Int64
    ) throws -> TokenUsageBucket {
        try TokenUsageBucket(
            providerID: providerID,
            accountID: accountID,
            projectReference: "project-sensitive",
            workspaceReference: "workspace-sensitive",
            model: "model-safe",
            granularity: granularity,
            period: period(start: start, granularity: granularity),
            tokens: TokenBreakdown(
                input: try TokenCount(rawValue: input),
                output: try TokenCount(rawValue: 2),
                cachedInput: try TokenCount(rawValue: 3),
                cacheWrite: try TokenCount(rawValue: 4)
            ),
            metadata: ObservationMetadata(
                source: try DataSource(kind: .official, identifier: "source-sensitive"),
                updatedAt: start,
                isStale: false
            )
        )
    }

    private func period(start: Date, granularity: UsageGranularity) throws -> UsagePeriod {
        try UsagePeriod.containing(
            start,
            granularity: granularity,
            calendar: Calendar(identifier: .gregorian),
            timeZone: try #require(TimeZone(secondsFromGMT: 0))
        )
    }

    private func insertAccount(
        providerID: ProviderID,
        accountID: AccountID,
        providerName: String,
        accountName: String
    ) throws {
        try database.write { database in
            let timestamp = "2026-08-12T00:00:00Z"
            try database.execute(
                sql: """
                    INSERT INTO providers (
                        id, type, display_name, refresh_interval_seconds, created_at, updated_at
                    ) VALUES (?, 'example', ?, 60, ?, ?)
                    """,
                arguments: [providerID.rawValue, providerName, timestamp, timestamp]
            )
            try database.execute(
                sql: """
                    INSERT INTO accounts (
                        id, provider_id, display_name, scope, deduplication_key,
                        remote_account_reference, project_reference, credential_reference,
                        created_at, updated_at
                    ) VALUES (?, ?, ?, 'organization', ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    accountID.rawValue, providerID.rawValue, accountName, accountID.rawValue,
                    "remote-account-sensitive", "project-sensitive", "keychain-sensitive",
                    timestamp, timestamp,
                ]
            )
        }
    }
}
