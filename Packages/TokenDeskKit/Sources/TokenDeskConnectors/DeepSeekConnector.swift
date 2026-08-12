import Foundation
import TokenDeskCore

/// DeepSeek official balance and locally aggregated response-usage connector.
public struct DeepSeekConnector: ProviderConnector, Sendable {
    /// Configured DeepSeek instance and its explicit balance/local metering capabilities.
    public let descriptor: ProviderDescriptor

    private let runtime: ProviderConnectorRuntime
    private let localUsage: LocalMeteredUsageContext

    /// Creates a connector with an atomic local usage repository and optional pricing catalog.
    public init(
        descriptor: ProviderDescriptor,
        credentialStore: any CredentialStore,
        localUsageRepository: any LocallyAggregatedUsageRepository,
        pricingCatalog: (any PricingCatalog)? = nil,
        estimatedCostCurrency: CurrencyCode? = nil,
        pricingRegion: String = "global",
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
        self.localUsage = LocalMeteredUsageContext(
            repository: localUsageRepository,
            pricingCatalog: pricingCatalog,
            estimatedCostCurrency: estimatedCostCurrency,
            pricingRegion: pricingRegion
        )
    }

    /// Checks the configured personal or organization credential reference.
    public func validateCredentials(for account: AccountReference) async throws {
        try Task.checkCancellation()
        try runtime.validateCredentials(for: account)
    }

    /// DeepSeek does not expose a public account-discovery API for this connector.
    public func fetchAccounts() async throws -> ConnectorReadResult<RemoteAccount> {
        try Task.checkCancellation()
        return .notSynchronized
    }

    /// DeepSeek API metering does not expose subscription quota windows.
    public func fetchPlan(
        for account: AccountReference
    ) async throws -> ConnectorReadResult<PlanWindow> {
        try Task.checkCancellation()
        return .unsupported
    }

    /// Reads response usage that Token Desk previously aggregated into local minute buckets.
    public func fetchUsage(
        for account: AccountReference,
        in interval: DateInterval
    ) async throws -> ConnectorReadResult<TokenUsageBucket> {
        try Task.checkCancellation()
        try runtime.validate(account: account, capability: .usage)
        return try localUsage.usage(for: account, in: interval)
    }

    /// Estimates costs from local usage only when a versioned matching pricing rule is available.
    public func fetchCosts(
        for account: AccountReference,
        in interval: DateInterval
    ) async throws -> ConnectorReadResult<CostSnapshot> {
        try Task.checkCancellation()
        try runtime.validate(account: account, capability: .cost)
        return try localUsage.costs(
            descriptor: descriptor,
            account: account,
            interval: interval,
            calculatedAt: runtime.now()
        )
    }

    /// Fetches authoritative available balances in every currency returned by DeepSeek.
    public func fetchBalance(
        for account: AccountReference
    ) async throws -> ConnectorReadResult<BalanceSnapshot> {
        try runtime.validate(account: account, capability: .balance)
        let response = try await runtime.request(
            path: "user/balance",
            account: account,
            authorization: .bearer
        )
        let payload = try runtime.decode(DeepSeekBalanceResponseDTO.self, from: response)
        guard payload.isAvailable else { return .empty }
        return .available(
            try payload.balanceInfos.map { info in
                let currency = try CurrencyCode(rawValue: info.currency)
                return BalanceSnapshot(
                    providerID: descriptor.id,
                    accountID: account.id,
                    available: Money(amount: info.totalBalance.value, currency: currency),
                    metadata: try ProviderMapping.metadata(
                        kind: .official,
                        identifier: "deepseek_balance_api",
                        updatedAt: runtime.now()
                    )
                )
            }
        )
    }

    /// Decodes one successful completion response and atomically adds its usage to local history.
    ///
    /// Call exactly once per successful response. The response body is decoded in memory and is
    /// never logged or persisted; prompts, choices, and remote request identifiers are discarded.
    @discardableResult
    public func recordResponseUsage(
        from responseBody: Data,
        for account: AccountReference
    ) throws -> TokenUsageBucket {
        try Task.checkCancellation()
        try runtime.validate(account: account, capability: .usage)
        let payload: DeepSeekCompletionResponseDTO
        do {
            payload = try JSONDecoder().decode(
                DeepSeekCompletionResponseDTO.self, from: responseBody)
        } catch {
            throw ConnectorError.decoding
        }
        let prompt = payload.usage.promptTokens
        let completion = payload.usage.completionTokens
        let (computedTotal, totalOverflow) = prompt.addingReportingOverflow(completion)
        if totalOverflow
            || payload.usage.totalTokens.map({ $0 != computedTotal }) == true
        {
            throw ConnectorError.decoding
        }
        let cached = payload.usage.promptCacheHitTokens ?? 0
        let (derivedUncached, subtractionOverflow) = prompt.subtractingReportingOverflow(cached)
        let uncached = payload.usage.promptCacheMissTokens ?? derivedUncached
        let (reconstructedPrompt, additionOverflow) = cached.addingReportingOverflow(uncached)
        guard !subtractionOverflow, !additionOverflow, cached >= 0, uncached >= 0,
            reconstructedPrompt == prompt
        else {
            throw ConnectorError.decoding
        }
        let observedAt = Date(timeIntervalSince1970: TimeInterval(payload.created))
        let bucket = try TokenUsageBucket(
            providerID: descriptor.id,
            accountID: account.id,
            projectReference: account.hierarchy.projectReference,
            model: payload.model,
            granularity: .minute,
            period: ProviderMapping.minutePeriod(containing: observedAt),
            tokens: TokenBreakdown(
                input: TokenCount(rawValue: uncached),
                output: TokenCount(rawValue: completion),
                cachedInput: TokenCount(rawValue: cached)
            ),
            metadata: ProviderMapping.metadata(
                kind: .locallyAggregated,
                identifier: "deepseek_response_usage",
                updatedAt: runtime.now()
            )
        )
        try Task.checkCancellation()
        try localUsage.record(bucket)
        return bucket
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
        components.host = "api.deepseek.com"
        components.path = "/"
        guard let url = components.url else {
            preconditionFailure("The compile-time DeepSeek URL must be valid")
        }
        return url
    }
}
