import Foundation

/// A Provider type identifier. The open string representation permits future providers without a core release.
public struct ProviderType: Codable, Hashable, Sendable {
    /// The open Provider type identifier.
    public let rawValue: String

    /// Creates a Provider type, rejecting empty or whitespace-only input.
    public init(rawValue: String) throws {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw DomainModelError.emptyIdentifier(field: "providerType")
        }
        self.rawValue = trimmed
    }

    /// Decodes and validates a single string value.
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        try self.init(rawValue: container.decode(String.self))
    }

    /// Encodes the Provider type as a single string value.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// The ownership boundary of a Provider account.
public enum AccountScope: String, Codable, CaseIterable, Sendable {
    case personal
    case organization
}

/// A Provider data operation that can be independently supported or unavailable.
public enum ProviderCapability: String, Codable, CaseIterable, Sendable {
    case plan
    case usage
    case cost
    case balance
    case localEstimate
}

/// The declared, immutable capability set for a Provider connector.
public struct ProviderCapabilities: Codable, Equatable, Hashable, Sendable {
    private let values: Set<ProviderCapability>

    /// Creates a declaration from the explicitly supported capabilities.
    public init(_ values: Set<ProviderCapability>) {
        self.values = values
    }

    /// Returns whether a connector explicitly declares support for a capability.
    public func contains(_ capability: ProviderCapability) -> Bool {
        values.contains(capability)
    }

    /// A Provider that exposes none of the modeled data operations.
    public static let none = ProviderCapabilities([])
}

/// Describes a configured Provider instance without containing credentials or transport DTOs.
public struct ProviderDescriptor: Codable, Equatable, Hashable, Sendable {
    /// The configured Provider instance identifier.
    public let id: ProviderID
    /// The connector-compatible Provider type.
    public let type: ProviderType
    /// The user-facing Provider name.
    public let displayName: String
    /// The operations explicitly supported by this Provider.
    public let capabilities: ProviderCapabilities

    /// Creates a descriptor, rejecting an empty display name.
    public init(
        id: ProviderID,
        type: ProviderType,
        displayName: String,
        capabilities: ProviderCapabilities
    ) throws {
        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw DomainModelError.emptyIdentifier(field: "providerDisplayName")
        }
        self.id = id
        self.type = type
        self.displayName = trimmedName
        self.capabilities = capabilities
    }
}

/// Provider hierarchy references used for isolation and aggregation. Values are private by default in logs.
public struct AccountHierarchy: Codable, Equatable, Hashable, Sendable {
    /// The opaque remote account identity, when the Provider exposes one.
    public let remoteAccountReference: String?
    /// The opaque organization identity, when applicable.
    public let organizationReference: String?
    /// The opaque project identity, when applicable.
    public let projectReference: String?
    /// The opaque workspace identity, when applicable.
    public let workspaceReference: String?

    /// Creates hierarchy references without interpreting Provider-specific values.
    public init(
        remoteAccountReference: String? = nil,
        organizationReference: String? = nil,
        projectReference: String? = nil,
        workspaceReference: String? = nil
    ) {
        self.remoteAccountReference = remoteAccountReference
        self.organizationReference = organizationReference
        self.projectReference = projectReference
        self.workspaceReference = workspaceReference
    }
}

/// A stable key for preventing duplicate aggregation of the same scoped Provider account.
public struct AccountDeduplicationKey: Codable, Equatable, Hashable, Sendable {
    /// The configured Provider instance boundary.
    public let providerID: ProviderID
    /// The personal or organization ownership boundary.
    public let scope: AccountScope
    /// The remote account reference or a local-ID fallback.
    public let accountReference: String
    /// The organization boundary, when present.
    public let organizationReference: String?
    /// The project boundary, when present.
    public let projectReference: String?
    /// The workspace boundary, when present.
    public let workspaceReference: String?
}

/// A local account configuration. It holds only aliases and opaque references, never credential material.
public struct AccountReference: Codable, Equatable, Hashable, Sendable {
    /// The local account identifier.
    public let id: AccountID
    /// The configured Provider instance that owns the account.
    public let providerID: ProviderID
    /// The user-controlled, log-safe account alias.
    public let displayName: String
    /// The personal or organization ownership boundary.
    public let scope: AccountScope
    /// The remote organization, project, and workspace hierarchy.
    public let hierarchy: AccountHierarchy
    /// An optional Keychain lookup reference; never credential material.
    public let credentialReference: CredentialReference?

    /// Creates an account reference, rejecting an empty display name.
    public init(
        id: AccountID,
        providerID: ProviderID,
        displayName: String,
        scope: AccountScope,
        hierarchy: AccountHierarchy = AccountHierarchy(),
        credentialReference: CredentialReference? = nil
    ) throws {
        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw DomainModelError.emptyIdentifier(field: "accountDisplayName")
        }
        self.id = id
        self.providerID = providerID
        self.displayName = trimmedName
        self.scope = scope
        self.hierarchy = hierarchy
        self.credentialReference = credentialReference
    }

    /// Builds the aggregation identity. A remote reference is preferred; the local ID is a safe fallback.
    public var deduplicationKey: AccountDeduplicationKey {
        AccountDeduplicationKey(
            providerID: providerID,
            scope: scope,
            accountReference: hierarchy.remoteAccountReference ?? id.rawValue,
            organizationReference: hierarchy.organizationReference,
            projectReference: hierarchy.projectReference,
            workspaceReference: hierarchy.workspaceReference
        )
    }
}

/// The provenance category attached to every observed or calculated value.
public enum DataSourceKind: String, Codable, CaseIterable, Sendable {
    case official
    case locallyAggregated
    case estimated
    case demonstration
}

/// A traceable source identifier and its provenance category.
public struct DataSource: Codable, Equatable, Hashable, Sendable {
    /// The provenance category used by presentation and aggregation rules.
    public let kind: DataSourceKind
    /// A traceable, non-secret source name such as `official_cost_api`.
    public let identifier: String

    /// Creates a data source, rejecting an empty identifier.
    public init(kind: DataSourceKind, identifier: String) throws {
        let trimmed = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw DomainModelError.emptyIdentifier(field: "sourceIdentifier")
        }
        self.kind = kind
        self.identifier = trimmed
    }

    /// Whether downstream presentation must label this value as an estimate.
    public var isEstimated: Bool {
        kind == .estimated
    }
}

/// Common freshness and provenance metadata for an observed domain value.
public struct ObservationMetadata: Codable, Equatable, Hashable, Sendable {
    /// The origin of the value.
    public let source: DataSource
    /// The UTC instant at which the value was last updated.
    public let updatedAt: Date
    /// Whether the configured freshness policy considers the value stale.
    public let isStale: Bool

    /// Creates immutable provenance and freshness metadata.
    public init(source: DataSource, updatedAt: Date, isStale: Bool) {
        self.source = source
        self.updatedAt = updatedAt
        self.isStale = isStale
    }
}
