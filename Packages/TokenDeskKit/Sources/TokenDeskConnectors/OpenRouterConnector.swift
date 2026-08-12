import Foundation
import TokenDeskCore

/// Official OpenRouter management-key Credits API connector.
public struct OpenRouterConnector: ProviderConnector, Sendable {
    /// Configured OpenRouter instance and its explicit credit-balance capability.
    public let descriptor: ProviderDescriptor

    private let runtime: ProviderConnectorRuntime
    private let creditCurrency: CurrencyCode

    /// Creates a connector with an explicit credit currency because the payload omits a code.
    public init(
        descriptor: ProviderDescriptor,
        credentialStore: any CredentialStore,
        creditCurrency: CurrencyCode,
        httpClient: any ConnectorHTTPClient = URLSessionConnectorHTTPClient(),
        baseURL: URL? = nil,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.descriptor = descriptor
        self.runtime = ProviderConnectorRuntime(
            descriptor: descriptor,
            credentialStore: credentialStore,
            httpClient: httpClient,
            baseURL: baseURL ?? Self.productionBaseURL,
            now: now
        )
        self.creditCurrency = creditCurrency
    }

    /// Checks the configured management-key credential reference.
    public func validateCredentials(for account: AccountReference) async throws {
        try Task.checkCancellation()
        try runtime.validateCredentials(for: account)
    }

    /// OpenRouter credit reads use the explicitly configured account scope.
    public func fetchAccounts() async throws -> ConnectorReadResult<RemoteAccount> {
        try Task.checkCancellation()
        return .notSynchronized
    }

    /// OpenRouter Credits does not expose subscription quota windows.
    public func fetchPlan(
        for account: AccountReference
    ) async throws -> ConnectorReadResult<PlanWindow> {
        try Task.checkCancellation()
        return .unsupported
    }

    /// OpenRouter Credits does not expose token history.
    public func fetchUsage(
        for account: AccountReference,
        in interval: DateInterval
    ) async throws -> ConnectorReadResult<TokenUsageBucket> {
        try Task.checkCancellation()
        return .unsupported
    }

    /// Cumulative credit consumption is not an interval cost and remains outside cost buckets.
    public func fetchCosts(
        for account: AccountReference,
        in interval: DateInterval
    ) async throws -> ConnectorReadResult<CostSnapshot> {
        try Task.checkCancellation()
        return .unsupported
    }

    /// Fetches total credited, total consumed, and computed available Credits independently.
    public func fetchBalance(
        for account: AccountReference
    ) async throws -> ConnectorReadResult<BalanceSnapshot> {
        try runtime.validate(account: account, capability: .balance)
        let response = try await runtime.request(
            path: "credits",
            account: account,
            authorization: .bearer
        )
        let payload = try runtime.decode(OpenRouterCreditsResponseDTO.self, from: response)
        let credited = Money(amount: payload.data.totalCredits.value, currency: creditCurrency)
        let consumed = Money(amount: payload.data.totalUsage.value, currency: creditCurrency)
        let available = Money(
            amount: payload.data.totalCredits.value - payload.data.totalUsage.value,
            currency: creditCurrency
        )
        return .available([
            BalanceSnapshot(
                providerID: descriptor.id,
                accountID: account.id,
                available: available,
                creditDetails: try CreditBalanceDetails(
                    totalCredited: credited,
                    totalConsumed: consumed,
                    balanceCurrency: creditCurrency
                ),
                metadata: try ProviderMapping.metadata(
                    kind: .official,
                    identifier: "openrouter_credits_api",
                    updatedAt: runtime.now()
                )
            )
        ])
    }

    /// Returns a redacted initial state until synchronization records a concrete outcome.
    public func fetchHealth() async -> ConnectorHealth {
        ConnectorHealth(
            providerID: descriptor.id,
            state: .notSynchronized,
            checkedAt: runtime.now()
        )
    }

    private static var productionBaseURL: URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "openrouter.ai"
        components.path = "/api/v1/"
        guard let url = components.url else {
            preconditionFailure("The compile-time OpenRouter URL must be valid")
        }
        return url
    }
}
