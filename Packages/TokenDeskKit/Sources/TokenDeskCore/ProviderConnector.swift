import Foundation

/// A normalized failure produced at the Provider integration boundary.
///
/// Connector implementations may retain redacted transport diagnostics internally, but must not
/// attach response bodies, credentials, or remote account identifiers to these values.
public enum ConnectorError: Error, Equatable, Sendable {
    /// The configured credential is missing, expired, or otherwise invalid.
    case authentication
    /// The credential is valid but lacks permission for the requested operation.
    case permissionDenied
    /// The Provider rejected the request because of a rate limit.
    case rateLimited(retryAfter: Duration?)
    /// The request could not reach the Provider over the network.
    case network
    /// The Provider returned a server-side failure. The status code is safe diagnostic context.
    case server(statusCode: Int?)
    /// The Provider response could not be decoded or mapped without inventing data.
    case decoding
    /// The requested operation is not supported by this connector.
    case unsupported(capability: ProviderCapability)
    /// The operation was cancelled by the caller.
    case cancelled

    /// Whether an idempotent read may be retried after applying the synchronization policy.
    public var isRetryable: Bool {
        switch self {
        case .rateLimited, .network, .server:
            true
        case .authentication, .permissionDenied, .decoding, .unsupported, .cancelled:
            false
        }
    }
}

/// The non-value states of a collection returned by a Connector read.
public enum ConnectorReadState: String, Codable, CaseIterable, Sendable {
    /// At least one domain value was returned.
    case available
    /// The Provider authoritatively returned no values for the requested scope and interval.
    case empty
    /// The Connector explicitly does not implement the capability.
    case unsupported
    /// The capability is supported, but no synchronization has completed yet.
    case notSynchronized
}

/// A Connector collection that distinguishes unavailable capability, first sync, and true emptiness.
///
/// Permission failures are thrown as ``ConnectorError/permissionDenied`` instead of being folded
/// into any state here. This keeps `403`, an authoritative empty response, and a missing capability
/// independently observable. Use ``available(_:)`` to normalize an empty array to ``empty``.
public struct ConnectorReadResult<Element: Sendable>: Sendable {
    /// The semantic state of this read.
    public let state: ConnectorReadState
    /// Domain values. This is non-empty only when ``state`` is ``ConnectorReadState/available``.
    public let values: [Element]

    private init(state: ConnectorReadState, values: [Element]) {
        self.state = state
        self.values = values
    }

    /// Creates an available result, or an explicit empty result when `values` is empty.
    public static func available(_ values: [Element]) -> Self {
        guard !values.isEmpty else {
            return .empty
        }
        return Self(state: .available, values: values)
    }

    /// The Provider authoritatively returned no values.
    public static var empty: Self {
        Self(state: .empty, values: [])
    }

    /// The Connector does not implement this capability.
    public static var unsupported: Self {
        Self(state: .unsupported, values: [])
    }

    /// The Connector supports this capability, but it has not completed its first sync.
    public static var notSynchronized: Self {
        Self(state: .notSynchronized, values: [])
    }
}

extension ConnectorReadResult: Equatable where Element: Equatable {}

/// A remote account discovered through an official Provider interface.
///
/// The value contains only presentation-safe labels and opaque hierarchy references. Credentials
/// and Provider transport DTOs must remain outside `TokenDeskCore`.
public struct RemoteAccount: Equatable, Hashable, Sendable {
    /// The display label supplied by the Provider or a safe local fallback.
    public let displayName: String
    /// The personal or organization ownership boundary.
    public let scope: AccountScope
    /// Opaque Provider hierarchy references, private by default in logs.
    public let hierarchy: AccountHierarchy

    /// Creates a remote account and rejects a blank display label.
    public init(
        displayName: String,
        scope: AccountScope,
        hierarchy: AccountHierarchy = AccountHierarchy()
    ) throws {
        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw DomainModelError.emptyIdentifier(field: "remoteAccountDisplayName")
        }
        self.displayName = trimmedName
        self.scope = scope
        self.hierarchy = hierarchy
    }
}

/// A high-level health state for one configured Provider instance.
public enum ConnectorHealthState: String, Codable, CaseIterable, Sendable {
    case notSynchronized
    case synchronizing
    case healthy
    case degraded
    case unavailable
}

/// The latest redacted health observation for one configured Provider instance.
public struct ConnectorHealth: Equatable, Sendable {
    /// The configured Provider instance this observation describes.
    public let providerID: ProviderID
    /// The high-level state shown by synchronization and settings features.
    public let state: ConnectorHealthState
    /// The UTC instant at which this health check completed.
    public let checkedAt: Date
    /// The last successful synchronization instant, if one has completed.
    public let lastSuccessfulSyncAt: Date?
    /// A normalized failure category without transport payloads or secrets.
    public let failure: ConnectorError?

    /// Creates a health observation. Callers preserve cached data separately when state is degraded.
    public init(
        providerID: ProviderID,
        state: ConnectorHealthState,
        checkedAt: Date,
        lastSuccessfulSyncAt: Date? = nil,
        failure: ConnectorError? = nil
    ) {
        self.providerID = providerID
        self.state = state
        self.checkedAt = checkedAt
        self.lastSuccessfulSyncAt = lastSuccessfulSyncAt
        self.failure = failure
    }
}

/// The Provider integration contract consumed by synchronization and application composition.
///
/// Implementations must use only official, public, App Sandbox-compatible data sources. All methods
/// are asynchronous and cancellation-aware. A caught `CancellationError` must be rethrown after
/// cleanup rather than converted to a retryable failure.
public protocol ProviderConnector: Sendable {
    /// The immutable identity and explicit capability declaration for this configured instance.
    var descriptor: ProviderDescriptor { get }

    /// Validates the credential reference for an account without exposing credential material.
    func validateCredentials(for account: AccountReference) async throws

    /// Discovers account scopes through an official Provider interface.
    func fetchAccounts() async throws -> ConnectorReadResult<RemoteAccount>

    /// Fetches independent plan windows for one configured account.
    func fetchPlan(for account: AccountReference) async throws -> ConnectorReadResult<PlanWindow>

    /// Fetches exact token usage for an end-exclusive interval.
    func fetchUsage(
        for account: AccountReference,
        in interval: DateInterval
    ) async throws -> ConnectorReadResult<TokenUsageBucket>

    /// Fetches official or explicitly estimated costs for an end-exclusive interval.
    func fetchCosts(
        for account: AccountReference,
        in interval: DateInterval
    ) async throws -> ConnectorReadResult<CostSnapshot>

    /// Fetches known balances. An authoritative zero is a value, not an empty result.
    func fetchBalance(
        for account: AccountReference
    ) async throws -> ConnectorReadResult<BalanceSnapshot>

    /// Performs a redacted health check. Failures are represented in the returned observation so a
    /// registry can preserve results from other Providers.
    func fetchHealth() async -> ConnectorHealth
}
