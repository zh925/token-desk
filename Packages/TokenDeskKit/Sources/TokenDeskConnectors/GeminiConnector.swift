import Foundation
import TokenDeskCore

/// Gemini response-usage connector. It never claims remote history, plan, or balance access.
public struct GeminiConnector: ProviderConnector, Sendable {
    /// Configured Gemini instance with local usage and optional estimated-cost capabilities.
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

    /// Returns unsupported because response metadata exposes no plan window.
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

    /// Returns unsupported because response usage metadata contains no balance.
    public func fetchBalance(for account: AccountReference) async throws
        -> ConnectorReadResult<BalanceSnapshot>
    {
        try Task.checkCancellation()
        return .unsupported
    }

    /// Records metadata from one successful `generateContent` response at the local receipt time.
    /// Response IDs, candidates, prompts, and generated content are neither decoded nor persisted.
    @discardableResult
    public func recordResponseUsage(
        from responseBody: Data,
        for account: AccountReference
    ) throws -> TokenUsageBucket {
        try Task.checkCancellation()
        let payload: GeminiGenerateContentResponseDTO
        do {
            payload = try JSONDecoder().decode(
                GeminiGenerateContentResponseDTO.self,
                from: responseBody
            )
        } catch {
            throw ConnectorError.decoding
        }

        let usage = payload.usageMetadata
        let (visibleOutput, outputOverflow) = usage.candidatesTokenCount.addingReportingOverflow(
            usage.thoughtsTokenCount ?? 0
        )
        let (derivedOutput, subtractionOverflow) = usage.totalTokenCount
            .subtractingReportingOverflow(usage.promptTokenCount)
        guard !outputOverflow, !subtractionOverflow, derivedOutput == visibleOutput else {
            throw ConnectorError.decoding
        }
        let bucket = try context.recordResponseUsage(
            for: account,
            model: payload.modelVersion,
            observedAt: context.runtime.now(),
            promptTokens: usage.promptTokenCount,
            outputTokens: derivedOutput,
            cachedInputTokens: usage.cachedContentTokenCount ?? 0,
            reportedTotalTokens: usage.totalTokenCount,
            sourceIdentifier: "gemini_response_usage_metadata"
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
        components.host = "generativelanguage.googleapis.com"
        components.path = "/v1beta/"
        guard let url = components.url else {
            preconditionFailure("The compile-time Gemini URL must be valid")
        }
        return url
    }
}
