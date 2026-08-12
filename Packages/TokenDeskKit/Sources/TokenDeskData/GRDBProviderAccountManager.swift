import Foundation
import GRDB
import TokenDeskCore

/// Stable validation and recovery failures surfaced by Provider settings.
public enum ProviderAccountManagerError: LocalizedError, Equatable, Sendable {
    case emptyField(String)
    case invalidRefreshInterval
    case configurationNotFound
    case credentialCleanupRequired

    /// Localized recovery guidance without credential or remote response data.
    public var errorDescription: String? {
        switch self {
        case .emptyField(let field): "请填写\(field)。"
        case .invalidRefreshInterval: "刷新频率必须大于 0 分钟。"
        case .configurationNotFound: "账户配置已变化，请刷新后重试。"
        case .credentialCleanupRequired: "历史已按选择处理，但 Keychain 凭据删除失败；可重试删除。"
        }
    }
}

/// Persists queryable account settings in SQLite and credential material in Keychain.
public final class GRDBProviderAccountManager: ProviderAccountManaging, @unchecked Sendable {
    private let writer: any DatabaseWriter
    private let credentialStore: any CredentialStore

    /// Creates a manager over migrated SQLite and device-local Keychain boundaries.
    public init(writer: any DatabaseWriter, credentialStore: any CredentialStore) {
        self.writer = writer
        self.credentialStore = credentialStore
    }

    /// Loads non-secret configurations and resolves presence-only credential states.
    public func configurations() async throws -> [ProviderAccountConfiguration] {
        let records = try await writer.read { database in
            try ProviderAccountRecord.fetchAll(
                database,
                sql: """
                    SELECT
                        providers.id AS provider_id,
                        accounts.id AS account_id,
                        providers.type AS provider_type,
                        providers.display_name AS provider_display_name,
                        accounts.display_name AS account_display_name,
                        accounts.scope,
                        accounts.organization_reference,
                        accounts.project_reference,
                        accounts.workspace_reference,
                        accounts.credential_reference,
                        (providers.is_enabled AND accounts.is_enabled) AS is_enabled,
                        providers.refresh_interval_seconds
                    FROM accounts
                    JOIN providers ON providers.id = accounts.provider_id
                    ORDER BY providers.display_name, accounts.display_name, accounts.id
                    """
            )
        }
        return try records.map(configuration(from:))
    }

    /// Atomically upserts non-secret rows and safely replaces optional Keychain material.
    public func save(
        _ draft: ProviderAccountDraft,
        replacingCredential credential: Credential?
    ) async throws -> ProviderAccountConfiguration {
        let normalized = try NormalizedProviderAccountDraft(draft)
        let providerID = try draft.providerID ?? ProviderID(rawValue: UUID().uuidString)
        let accountID = try draft.accountID ?? AccountID(rawValue: UUID().uuidString)
        let existingReference = try await writer.read { database in
            try String.fetchOne(
                database,
                sql: "SELECT credential_reference FROM accounts WHERE id = ?",
                arguments: [accountID.rawValue]
            )
        }.flatMap { try? CredentialReference(rawValue: $0) }

        var previousCredential: Credential?
        var savedReference = existingReference
        if let credential {
            if let existingReference {
                previousCredential = try credentialStore.credential(for: existingReference)
                try credentialStore.replace(credential, for: existingReference)
                savedReference = existingReference
            } else {
                savedReference = try credentialStore.save(credential, for: accountID)
            }
        }

        let referenceForStorage = savedReference
        do {
            try await writer.write { database in
                let now = Date().ISO8601Format()
                try database.execute(
                    sql: """
                        INSERT INTO providers (
                            id, type, display_name, is_enabled, refresh_interval_seconds,
                            created_at, updated_at
                        ) VALUES (?, ?, ?, ?, ?, ?, ?)
                        ON CONFLICT(id) DO UPDATE SET
                            type = excluded.type,
                            display_name = excluded.display_name,
                            is_enabled = excluded.is_enabled,
                            refresh_interval_seconds = excluded.refresh_interval_seconds,
                            updated_at = excluded.updated_at
                        """,
                    arguments: [
                        providerID.rawValue,
                        normalized.providerType.rawValue,
                        normalized.providerDisplayName,
                        draft.isEnabled,
                        normalized.refreshIntervalMinutes * 60,
                        now,
                        now,
                    ]
                )
                let deduplicationKey = [
                    draft.scope.rawValue,
                    normalized.organizationReference ?? "",
                    normalized.projectReference ?? "",
                    normalized.workspaceReference ?? "",
                    accountID.rawValue,
                ].joined(separator: "|")
                try database.execute(
                    sql: """
                        INSERT INTO accounts (
                            id, provider_id, display_name, scope, deduplication_key,
                            organization_reference, project_reference, workspace_reference,
                            credential_reference, is_enabled, created_at, updated_at
                        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                        ON CONFLICT(id) DO UPDATE SET
                            provider_id = excluded.provider_id,
                            display_name = excluded.display_name,
                            scope = excluded.scope,
                            deduplication_key = excluded.deduplication_key,
                            organization_reference = excluded.organization_reference,
                            project_reference = excluded.project_reference,
                            workspace_reference = excluded.workspace_reference,
                            credential_reference = excluded.credential_reference,
                            is_enabled = excluded.is_enabled,
                            updated_at = excluded.updated_at
                        """,
                    arguments: [
                        accountID.rawValue,
                        providerID.rawValue,
                        normalized.accountDisplayName,
                        draft.scope.rawValue,
                        deduplicationKey,
                        normalized.organizationReference,
                        normalized.projectReference,
                        normalized.workspaceReference,
                        referenceForStorage?.rawValue,
                        draft.isEnabled,
                        now,
                        now,
                    ]
                )
            }
        } catch {
            if let existingReference, let previousCredential {
                try? credentialStore.replace(previousCredential, for: existingReference)
            } else if existingReference == nil, let savedReference {
                try? credentialStore.delete(for: savedReference)
            }
            throw error
        }

        guard
            let configuration = try await configurations().first(where: {
                $0.accountID == accountID
            })
        else {
            throw ProviderAccountManagerError.configurationNotFound
        }
        return configuration
    }

    /// Enables or disables one configured account without deleting its history.
    public func setEnabled(_ isEnabled: Bool, accountID: AccountID) async throws {
        let changed = try await writer.write { database in
            try database.execute(
                sql: "UPDATE accounts SET is_enabled = ?, updated_at = ? WHERE id = ?",
                arguments: [isEnabled, Date().ISO8601Format(), accountID.rawValue]
            )
            return database.changesCount
        }
        guard changed == 1 else { throw ProviderAccountManagerError.configurationNotFound }
    }

    /// Deletes credentials and either archives or removes account history with retryable ordering.
    public func delete(
        accountID: AccountID,
        history: ProviderHistoryDisposition
    ) async throws {
        let record = try writer.read { database in
            try Row.fetchOne(
                database,
                sql: """
                    SELECT provider_id, credential_reference
                    FROM accounts WHERE id = ?
                    """,
                arguments: [accountID.rawValue]
            )
        }
        guard let record else { throw ProviderAccountManagerError.configurationNotFound }
        let providerID: String = record["provider_id"]
        let reference = (record["credential_reference"] as String?).flatMap {
            try? CredentialReference(rawValue: $0)
        }

        try await writer.write { database in
            try database.execute(
                sql: "UPDATE accounts SET is_enabled = 0, updated_at = ? WHERE id = ?",
                arguments: [Date().ISO8601Format(), accountID.rawValue]
            )
            guard history == .delete else { return }
            for table in ["plan_snapshots", "usage_buckets", "cost_buckets", "balances"] {
                try database.execute(
                    sql: "DELETE FROM \(table) WHERE provider_id = ? AND account_id = ?",
                    arguments: [providerID, accountID.rawValue]
                )
            }
            try database.execute(
                sql: "DELETE FROM alert_rules WHERE provider_id = ? AND account_id = ?",
                arguments: [providerID, accountID.rawValue]
            )
            try database.execute(
                sql: "UPDATE export_jobs SET account_id = NULL WHERE account_id = ?",
                arguments: [accountID.rawValue]
            )
        }

        if let reference {
            do {
                try credentialStore.delete(for: reference)
            } catch {
                throw ProviderAccountManagerError.credentialCleanupRequired
            }
        }

        try await writer.write { database in
            switch history {
            case .retain:
                try database.execute(
                    sql: """
                        UPDATE accounts
                        SET credential_reference = NULL, updated_at = ?
                        WHERE id = ?
                        """,
                    arguments: [Date().ISO8601Format(), accountID.rawValue]
                )
            case .delete:
                try database.execute(
                    sql: "DELETE FROM accounts WHERE id = ?",
                    arguments: [accountID.rawValue]
                )
                let accountCount =
                    try Int.fetchOne(
                        database,
                        sql: "SELECT COUNT(*) FROM accounts WHERE provider_id = ?",
                        arguments: [providerID]
                    ) ?? 0
                if accountCount == 0 {
                    try database.execute(
                        sql: "DELETE FROM providers WHERE id = ?",
                        arguments: [providerID]
                    )
                }
            }
        }
    }

    private func configuration(
        from record: ProviderAccountRecord
    ) throws -> ProviderAccountConfiguration {
        let reference = try record.credentialReference.map(CredentialReference.init(rawValue:))
        let status: CredentialConfigurationStatus
        if let reference {
            status = try credentialStore.configurationStatus(for: reference)
        } else {
            status = .notConfigured
        }
        return ProviderAccountConfiguration(
            providerID: try ProviderID(rawValue: record.providerID),
            accountID: try AccountID(rawValue: record.accountID),
            providerType: try ProviderType(rawValue: record.providerType),
            providerDisplayName: record.providerDisplayName,
            accountDisplayName: record.accountDisplayName,
            scope: AccountScope(rawValue: record.scope) ?? .personal,
            hierarchy: AccountHierarchy(
                organizationReference: record.organizationReference,
                projectReference: record.projectReference,
                workspaceReference: record.workspaceReference
            ),
            credentialReference: reference,
            credentialStatus: status,
            isEnabled: record.isEnabled,
            refreshIntervalMinutes: max(1, record.refreshIntervalSeconds / 60)
        )
    }
}

private struct ProviderAccountRecord: FetchableRecord {
    let providerID: String
    let accountID: String
    let providerType: String
    let providerDisplayName: String
    let accountDisplayName: String
    let scope: String
    let organizationReference: String?
    let projectReference: String?
    let workspaceReference: String?
    let credentialReference: String?
    let isEnabled: Bool
    let refreshIntervalSeconds: Int

    init(row: Row) {
        providerID = row["provider_id"]
        accountID = row["account_id"]
        providerType = row["provider_type"]
        providerDisplayName = row["provider_display_name"]
        accountDisplayName = row["account_display_name"]
        scope = row["scope"]
        organizationReference = row["organization_reference"]
        projectReference = row["project_reference"]
        workspaceReference = row["workspace_reference"]
        credentialReference = row["credential_reference"]
        isEnabled = row["is_enabled"]
        refreshIntervalSeconds = row["refresh_interval_seconds"]
    }
}

private struct NormalizedProviderAccountDraft {
    let providerType: ProviderType
    let providerDisplayName: String
    let accountDisplayName: String
    let organizationReference: String?
    let projectReference: String?
    let workspaceReference: String?
    let refreshIntervalMinutes: Int

    init(_ draft: ProviderAccountDraft) throws {
        providerType = try ProviderType(rawValue: draft.providerType)
        providerDisplayName = try Self.required(draft.providerDisplayName, field: "Provider 名称")
        accountDisplayName = try Self.required(draft.accountDisplayName, field: "账户别名")
        organizationReference = Self.optional(draft.organizationReference)
        projectReference = Self.optional(draft.projectReference)
        workspaceReference = Self.optional(draft.workspaceReference)
        guard draft.refreshIntervalMinutes > 0 else {
            throw ProviderAccountManagerError.invalidRefreshInterval
        }
        refreshIntervalMinutes = draft.refreshIntervalMinutes
    }

    private static func required(_ value: String, field: String) throws -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ProviderAccountManagerError.emptyField(field) }
        return trimmed
    }

    private static func optional(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
