import Foundation
import TokenDeskCore

/// MiniMax response-usage connector. Token Plan and balance reads remain explicit unsupported.
public struct MiniMaxConnector: ProviderConnector, Sendable {
    /// Configured MiniMax instance and its explicit local metering capabilities.
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

    /// Returns unsupported until the Token Plan response schema is an accepted contract.
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

    /// Returns unsupported because plan quota and pay-as-you-go balance remain independent.
    public func fetchBalance(for account: AccountReference) async throws
        -> ConnectorReadResult<BalanceSnapshot>
    {
        try Task.checkCancellation()
        return .unsupported
    }

    /// Records only usage metadata and the model/timestamp from a successful text response.
    @discardableResult
    public func recordResponseUsage(
        from responseBody: Data,
        for account: AccountReference
    ) throws -> TokenUsageBucket {
        try Task.checkCancellation()
        let payload: MiniMaxCompletionResponseDTO
        do {
            payload = try JSONDecoder().decode(
                MiniMaxCompletionResponseDTO.self,
                from: responseBody
            )
        } catch {
            throw ConnectorError.decoding
        }
        guard payload.baseResponse?.statusCode ?? 0 == 0 else {
            throw ConnectorError.server(statusCode: nil)
        }
        let bucket = try context.recordResponseUsage(
            for: account,
            model: payload.model,
            observedAt: Date(timeIntervalSince1970: TimeInterval(payload.created)),
            promptTokens: payload.usage.promptTokens,
            outputTokens: payload.usage.completionTokens,
            cachedInputTokens: payload.usage.promptTokenDetails?.cachedTokens ?? 0,
            reportedTotalTokens: payload.usage.totalTokens,
            sourceIdentifier: "minimax_response_usage"
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
        components.host = "api.minimax.io"
        components.path = "/v1/"
        guard let url = components.url else {
            preconditionFailure("The compile-time MiniMax URL must be valid")
        }
        return url
    }
}
