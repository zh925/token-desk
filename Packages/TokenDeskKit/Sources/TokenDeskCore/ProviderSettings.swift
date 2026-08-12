import Foundation

/// Non-secret Provider and account settings restored from SQLite.
public struct ProviderAccountConfiguration: Equatable, Sendable, Identifiable {
    /// Stable configured Provider instance identifier.
    public let providerID: ProviderID
    /// Stable local account identifier.
    public let accountID: AccountID
    /// Connector type used by application composition.
    public let providerType: ProviderType
    /// User-visible Provider label.
    public let providerDisplayName: String
    /// User-visible, log-safe account alias.
    public let accountDisplayName: String
    /// Personal or organization ownership boundary.
    public let scope: AccountScope
    /// Opaque organization, project, and workspace references.
    public let hierarchy: AccountHierarchy
    /// Opaque Keychain lookup reference, never credential material.
    public let credentialReference: CredentialReference?
    /// Presence-only credential state exposed to presentation.
    public let credentialStatus: CredentialConfigurationStatus
    /// Whether synchronization should include this account.
    public let isEnabled: Bool
    /// Configured synchronization cadence in whole minutes.
    public let refreshIntervalMinutes: Int

    /// Uses the account identifier as stable list identity.
    public var id: AccountID { accountID }

    /// Creates a non-secret configuration restored from persistence.
    public init(
        providerID: ProviderID,
        accountID: AccountID,
        providerType: ProviderType,
        providerDisplayName: String,
        accountDisplayName: String,
        scope: AccountScope,
        hierarchy: AccountHierarchy,
        credentialReference: CredentialReference?,
        credentialStatus: CredentialConfigurationStatus,
        isEnabled: Bool,
        refreshIntervalMinutes: Int
    ) {
        self.providerID = providerID
        self.accountID = accountID
        self.providerType = providerType
        self.providerDisplayName = providerDisplayName
        self.accountDisplayName = accountDisplayName
        self.scope = scope
        self.hierarchy = hierarchy
        self.credentialReference = credentialReference
        self.credentialStatus = credentialStatus
        self.isEnabled = isEnabled
        self.refreshIntervalMinutes = refreshIntervalMinutes
    }

    /// Converts persisted settings into the credential-free account model connectors consume.
    public var accountReference: AccountReference {
        get throws {
            try AccountReference(
                id: accountID,
                providerID: providerID,
                displayName: accountDisplayName,
                scope: scope,
                hierarchy: hierarchy,
                credentialReference: credentialReference
            )
        }
    }
}

/// Editable, non-secret values accepted by the Provider settings persistence boundary.
public struct ProviderAccountDraft: Equatable, Sendable {
    /// Existing Provider identifier, or nil for a new configuration.
    public var providerID: ProviderID?
    /// Existing account identifier, or nil for a new account.
    public var accountID: AccountID?
    /// Connector type selected from the settings catalog.
    public var providerType: String
    /// Editable Provider label.
    public var providerDisplayName: String
    /// Editable, log-safe account alias.
    public var accountDisplayName: String
    /// Editable ownership boundary.
    public var scope: AccountScope
    /// Optional opaque organization reference.
    public var organizationReference: String
    /// Optional opaque project reference.
    public var projectReference: String
    /// Optional opaque workspace reference.
    public var workspaceReference: String
    /// Desired synchronization state.
    public var isEnabled: Bool
    /// Desired synchronization cadence in whole minutes.
    public var refreshIntervalMinutes: Int

    /// Creates an editable draft with privacy-preserving defaults.
    public init(
        providerID: ProviderID? = nil,
        accountID: AccountID? = nil,
        providerType: String = "openai",
        providerDisplayName: String = "OpenAI",
        accountDisplayName: String = "个人账户",
        scope: AccountScope = .personal,
        organizationReference: String = "",
        projectReference: String = "",
        workspaceReference: String = "",
        isEnabled: Bool = true,
        refreshIntervalMinutes: Int = 15
    ) {
        self.providerID = providerID
        self.accountID = accountID
        self.providerType = providerType
        self.providerDisplayName = providerDisplayName
        self.accountDisplayName = accountDisplayName
        self.scope = scope
        self.organizationReference = organizationReference
        self.projectReference = projectReference
        self.workspaceReference = workspaceReference
        self.isEnabled = isEnabled
        self.refreshIntervalMinutes = refreshIntervalMinutes
    }

    /// Creates an editing draft from a persisted configuration.
    public init(configuration: ProviderAccountConfiguration) {
        self.init(
            providerID: configuration.providerID,
            accountID: configuration.accountID,
            providerType: configuration.providerType.rawValue,
            providerDisplayName: configuration.providerDisplayName,
            accountDisplayName: configuration.accountDisplayName,
            scope: configuration.scope,
            organizationReference: configuration.hierarchy.organizationReference ?? "",
            projectReference: configuration.hierarchy.projectReference ?? "",
            workspaceReference: configuration.hierarchy.workspaceReference ?? "",
            isEnabled: configuration.isEnabled,
            refreshIntervalMinutes: configuration.refreshIntervalMinutes
        )
    }
}

/// Whether deleting settings also removes locally retained history.
public enum ProviderHistoryDisposition: Equatable, Sendable {
    case retain
    case delete
}

/// SQLite and Keychain boundary consumed by the settings feature.
public protocol ProviderAccountManaging: Sendable {
    func configurations() async throws -> [ProviderAccountConfiguration]
    func save(_ draft: ProviderAccountDraft, replacingCredential: Credential?) async throws
        -> ProviderAccountConfiguration
    func setEnabled(_ isEnabled: Bool, accountID: AccountID) async throws
    func delete(accountID: AccountID, history: ProviderHistoryDisposition) async throws
}

/// Redacted result of an explicit user-initiated Provider connection test.
public enum ProviderConnectionTestResult: Equatable, Sendable {
    case connected
    case credentialConfigured
    case unsupported(reason: String)
}

/// Official-connector boundary used for connection tests without exposing transport state to UI.
public protocol ProviderConnectionTesting: Sendable {
    func testConnection(for configuration: ProviderAccountConfiguration) async throws
        -> ProviderConnectionTestResult
}
