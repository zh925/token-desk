import Foundation
import TokenDeskCore

/// GLM response-usage connector with explicit local-only metering semantics.
public struct GLMConnector: ProviderConnector, Sendable {
    /// Configured GLM instance and its explicit local metering capabilities.
    public let descriptor: ProviderDescriptor
    private let context: LocalResponseUsageConnectorContext

    /// Creates a local aggregation connector backed by an atomic usage repository.
    public init(
        descriptor: ProviderDescriptor,
        credentialStore: any CredentialStore,
        localUsageRepository: any LocallyAggregatedUsageRepository,
        pricingCatalog: (any PricingCatalog)? = nil,
        estimatedCostCurrency: CurrencyCode? = nil,
        pricingRegion: String = "global",
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.descriptor = descriptor
        self.context = LocalResponseUsageConnectorContext(
            runtime: ProviderConnectorRuntime(
                descriptor: descriptor,
                credentialStore: credentialStore,
                httpClient: URLSessionConnectorHTTPClient(),
                baseURL: Self.productionBaseURL,
                now: now
            ),
            localUsage: LocalMeteredUsageContext(
                repository: localUsageRepository,
                pricingCatalog: pricingCatalog,
                estimatedCostCurrency: estimatedCostCurrency,
                pricingRegion: pricingRegion
            )
        )
    }

    /// Checks that the configured account owns a non-empty Keychain credential reference.
    public func validateCredentials(for account: AccountReference) async throws {
        try Task.checkCancellation()
        try context.validateCredentials(for: account)
    }

    /// Returns not synchronized because no public account-discovery read is used.
    public func fetchAccounts() async throws -> ConnectorReadResult<RemoteAccount> {
        try Task.checkCancellation()
        return .notSynchronized
    }

    /// Returns unsupported because no stable public plan-window response is mapped.
    public func fetchPlan(for account: AccountReference) async throws
        -> ConnectorReadResult<PlanWindow>
    {
        try Task.checkCancellation()
        return .unsupported
    }

    /// Reads only the usage buckets previously recorded on this device.
    public func fetchUsage(
        for account: AccountReference,
        in interval: DateInterval
    ) async throws -> ConnectorReadResult<TokenUsageBucket> {
        try Task.checkCancellation()
        return try context.fetchUsage(for: account, in: interval)
    }

    /// Estimates local usage only when an effective pricing rule is configured.
    public func fetchCosts(
        for account: AccountReference,
        in interval: DateInterval
    ) async throws -> ConnectorReadResult<CostSnapshot> {
        try Task.checkCancellation()
        return try context.fetchCosts(
            descriptor: descriptor,
            account: account,
            interval: interval
        )
    }

    /// Returns unsupported because this connector maps no official balance response.
    public func fetchBalance(for account: AccountReference) async throws
        -> ConnectorReadResult<BalanceSnapshot>
    {
        try Task.checkCancellation()
        return .unsupported
    }

    /// Records only the documented usage fields from one successful chat completion response.
    @discardableResult
    public func recordResponseUsage(
        from responseBody: Data,
        for account: AccountReference
    ) throws -> TokenUsageBucket {
        try Task.checkCancellation()
        let payload: GLMCompletionResponseDTO
        do {
            payload = try JSONDecoder().decode(GLMCompletionResponseDTO.self, from: responseBody)
        } catch {
            throw ConnectorError.decoding
        }
        let bucket = try context.recordResponseUsage(
            for: account,
            model: payload.model,
            observedAt: Date(timeIntervalSince1970: TimeInterval(payload.created)),
            promptTokens: payload.usage.promptTokens,
            outputTokens: payload.usage.completionTokens,
            cachedInputTokens: payload.usage.promptTokenDetails?.cachedTokens ?? 0,
            reportedTotalTokens: payload.usage.totalTokens,
            sourceIdentifier: "glm_response_usage"
        )
        return bucket
    }

    /// Returns a redacted initial state until synchronization records a concrete outcome.
    public func fetchHealth() async -> ConnectorHealth {
        context.health()
    }

    private static var productionBaseURL: URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "open.bigmodel.cn"
        components.path = "/api/paas/v4/"
        guard let url = components.url else {
            preconditionFailure("The compile-time GLM URL must be valid")
        }
        return url
    }
}
