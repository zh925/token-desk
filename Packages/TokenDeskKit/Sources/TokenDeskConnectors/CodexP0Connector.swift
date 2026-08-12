import Foundation
import TokenDeskCore

/// P0 Codex boundary used while GATE-02 remains closed.
///
/// It performs no transport, process launch, cookie access, or private-container read. Every data
/// operation is explicitly unsupported so demo fixtures cannot be mistaken for account data.
public struct CodexP0Connector: ProviderConnector, Sendable {
    /// Configured Codex instance whose P0 data capabilities must all be absent.
    public let descriptor: ProviderDescriptor
    private let now: @Sendable () -> Date

    /// Creates the transport-free P0 connector.
    public init(
        descriptor: ProviderDescriptor,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.descriptor = descriptor
        self.now = now
    }

    /// Validates only account ownership; P0 has no credential to read or persist.
    public func validateCredentials(for account: AccountReference) async throws {
        try Task.checkCancellation()
        guard account.providerID == descriptor.id else {
            throw ConnectorError.permissionDenied
        }
    }

    /// Returns unsupported because P0 performs no remote account discovery.
    public func fetchAccounts() async throws -> ConnectorReadResult<RemoteAccount> {
        try Task.checkCancellation()
        return .unsupported
    }

    /// Returns unsupported while GATE-02 is closed.
    public func fetchPlan(for account: AccountReference) async throws
        -> ConnectorReadResult<PlanWindow>
    {
        try validate(account)
        return .unsupported
    }

    /// Returns unsupported rather than mapping plan percentages into Token values.
    public func fetchUsage(
        for account: AccountReference,
        in interval: DateInterval
    ) async throws -> ConnectorReadResult<TokenUsageBucket> {
        try validate(account)
        return .unsupported
    }

    /// Returns unsupported rather than inventing a Codex subscription cost.
    public func fetchCosts(
        for account: AccountReference,
        in interval: DateInterval
    ) async throws -> ConnectorReadResult<CostSnapshot> {
        try validate(account)
        return .unsupported
    }

    /// Returns unsupported because Codex plan quota is not an API credit balance.
    public func fetchBalance(for account: AccountReference) async throws
        -> ConnectorReadResult<BalanceSnapshot>
    {
        try validate(account)
        return .unsupported
    }

    /// Reports the connector unavailable with a normalized unsupported-plan reason.
    public func fetchHealth() async -> ConnectorHealth {
        ConnectorHealth(
            providerID: descriptor.id,
            state: .unavailable,
            checkedAt: now(),
            failure: .unsupported(capability: .plan)
        )
    }

    private func validate(_ account: AccountReference) throws {
        try Task.checkCancellation()
        guard account.providerID == descriptor.id else {
            throw ConnectorError.permissionDenied
        }
    }
}
