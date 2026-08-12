import Foundation
import GRDB
import Testing
import TokenDeskCore
@testable import TokenDeskData

@Test
func providerAccountsRoundTripAcrossManagerRecreationWithoutPersistingSecrets() async throws {
    let database = try DatabaseQueue(configuration: TokenDeskDatabase.configuration)
    try TokenDeskDatabaseMigrator.migrate(database)
    let credentials = MemoryCredentialStore()
    let manager = GRDBProviderAccountManager(writer: database, credentialStore: credentials)

    let first = try await manager.save(
        ProviderAccountDraft(
            providerType: "openai",
            providerDisplayName: "OpenAI",
            accountDisplayName: "个人账户",
            scope: .personal,
            refreshIntervalMinutes: 15
        ),
        replacingCredential: Credential(utf8Value: "secret-never-in-sqlite")
    )
    _ = try await manager.save(
        ProviderAccountDraft(
            providerType: "openai",
            providerDisplayName: "OpenAI",
            accountDisplayName: "组织账户",
            scope: .organization,
            organizationReference: "org-private",
            projectReference: "project-private",
            refreshIntervalMinutes: 30
        ),
        replacingCredential: Credential(utf8Value: "second-secret")
    )

    let restored = try await GRDBProviderAccountManager(
        writer: database,
        credentialStore: credentials
    ).configurations()
    #expect(restored.count == 2)
    #expect(Set(restored.map(\.scope)) == [.personal, .organization])
    #expect(restored.allSatisfy { $0.credentialStatus == .configured })
    #expect(
        restored.first { $0.scope == .organization }?.hierarchy.projectReference
            == "project-private")
    #expect(first.credentialReference?.rawValue == first.accountID.rawValue)

    let storedText = try await database.read { database in
        try String.fetchAll(
            database,
            sql: """
                SELECT id || type || display_name FROM providers
                UNION ALL
                SELECT id || provider_id || display_name || COALESCE(credential_reference, '')
                FROM accounts
                """
        ).joined()
    }
    #expect(!storedText.contains("secret-never-in-sqlite"))
    #expect(!storedText.contains("second-secret"))
}

@Test
func providerDeletionCanRetainOrRemoveHistoryAndAlwaysDeletesCredential() async throws {
    let database = try DatabaseQueue(configuration: TokenDeskDatabase.configuration)
    try TokenDeskDatabaseMigrator.migrate(database)
    let credentials = MemoryCredentialStore()
    let manager = GRDBProviderAccountManager(writer: database, credentialStore: credentials)
    let retained = try await manager.save(
        ProviderAccountDraft(accountDisplayName: "保留历史"),
        replacingCredential: Credential(utf8Value: "retained-secret")
    )
    let removed = try await manager.save(
        ProviderAccountDraft(accountDisplayName: "删除历史"),
        replacingCredential: Credential(utf8Value: "removed-secret")
    )
    try insertPlanSnapshot(for: retained, in: database)
    try insertPlanSnapshot(for: removed, in: database)

    try await manager.delete(accountID: retained.accountID, history: .retain)
    try await manager.delete(accountID: removed.accountID, history: .delete)

    let configurations = try await manager.configurations()
    let archived = try #require(configurations.first { $0.accountID == retained.accountID })
    #expect(!archived.isEnabled)
    #expect(archived.credentialStatus == .notConfigured)
    #expect(configurations.allSatisfy { $0.accountID != removed.accountID })
    #expect(credentials.deletedReferences.contains(retained.accountID.rawValue))
    #expect(credentials.deletedReferences.contains(removed.accountID.rawValue))

    let counts = try await database.read { database in
        (
            try Int.fetchOne(
                database,
                sql: "SELECT COUNT(*) FROM plan_snapshots WHERE account_id = ?",
                arguments: [retained.accountID.rawValue]
            ) ?? 0,
            try Int.fetchOne(
                database,
                sql: "SELECT COUNT(*) FROM plan_snapshots WHERE account_id = ?",
                arguments: [removed.accountID.rawValue]
            ) ?? 0
        )
    }
    #expect(counts.0 == 1)
    #expect(counts.1 == 0)
}

private func insertPlanSnapshot(
    for configuration: ProviderAccountConfiguration,
    in writer: any DatabaseWriter
) throws {
    try writer.write { database in
        try database.execute(
            sql: """
                INSERT INTO plan_snapshots (
                    provider_id, account_id, plan_name, limit_identifier,
                    used_percent_decimal, window_duration_minutes, resets_at,
                    time_zone_identifier, source, source_kind, updated_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
            arguments: [
                configuration.providerID.rawValue,
                configuration.accountID.rawValue,
                "Plan",
                "window",
                "20",
                300,
                "2026-08-13T00:00:00Z",
                "UTC",
                "fixture",
                "demonstration",
                "2026-08-12T00:00:00Z",
            ]
        )
    }
}

private final class MemoryCredentialStore: CredentialStore, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Credential] = [:]
    private(set) var deletedReferences: Set<String> = []

    func save(_ credential: Credential, for accountID: AccountID) throws -> CredentialReference {
        let reference = try CredentialReference(rawValue: accountID.rawValue)
        lock.withLock { values[reference.rawValue] = credential }
        return reference
    }

    func credential(for reference: CredentialReference) throws -> Credential {
        try lock.withLock {
            guard let credential = values[reference.rawValue] else {
                throw CredentialStoreError.notFound
            }
            return credential
        }
    }

    func replace(_ credential: Credential, for reference: CredentialReference) throws {
        try lock.withLock {
            guard values[reference.rawValue] != nil else { throw CredentialStoreError.notFound }
            values[reference.rawValue] = credential
        }
    }

    func delete(for reference: CredentialReference) throws {
        lock.withLock {
            values[reference.rawValue] = nil
            deletedReferences.insert(reference.rawValue)
        }
    }

    func configurationStatus(for reference: CredentialReference) throws
        -> CredentialConfigurationStatus
    {
        lock.withLock { values[reference.rawValue] == nil ? .notConfigured : .configured }
    }
}
