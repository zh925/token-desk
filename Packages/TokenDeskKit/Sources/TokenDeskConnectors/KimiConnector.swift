import Foundation
import TokenDeskCore

/// Kimi/Moonshot official balance and locally aggregated response-usage connector.
public struct KimiConnector: ProviderConnector, Sendable {
    /// Configured Kimi/Moonshot instance and its explicit balance/local metering capabilities.
    public let descriptor: ProviderDescriptor

    private let runtime: ProviderConnectorRuntime
    private let localUsage: LocalMeteredUsageContext
    private let balanceCurrency: CurrencyCode

    /// Creates a connector with an explicit account currency because the balance payload omits it.
    public init(
        descriptor: ProviderDescriptor,
        credentialStore: any CredentialStore,
        localUsageRepository: any LocallyAggregatedUsageRepository,
        balanceCurrency: CurrencyCode,
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
        self.balanceCurrency = balanceCurrency
    }

    /// Checks the configured personal or organization credential reference.
    public func validateCredentials(for account: AccountReference) async throws {
        try Task.checkCancellation()
        try runtime.validateCredentials(for: account)
    }

    /// Kimi does not expose a public account-discovery API for this connector.
    public func fetchAccounts() async throws -> ConnectorReadResult<RemoteAccount> {
        try Task.checkCancellation()
        return .notSynchronized
    }

    /// Kimi metering does not expose a normalized public subscription quota window.
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

    /// Fetches the official available balance using the explicitly configured account currency.
    public func fetchBalance(
        for account: AccountReference
    ) async throws -> ConnectorReadResult<BalanceSnapshot> {
        try runtime.validate(account: account, capability: .balance)
        let response = try await runtime.request(
            path: "users/me/balance",
            account: account,
            authorization: .bearer
        )
        let payload = try runtime.decode(KimiBalanceResponseDTO.self, from: response)
        guard payload.status else { throw ConnectorError.server(statusCode: nil) }
        return .available([
            BalanceSnapshot(
                providerID: descriptor.id,
                accountID: account.id,
                available: Money(
                    amount: payload.data.availableBalance.value,
                    currency: balanceCurrency
                ),
                metadata: try ProviderMapping.metadata(
                    kind: .official,
                    identifier: "kimi_balance_api",
                    updatedAt: runtime.now()
                )
            )
        ])
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
        let payload: KimiCompletionResponseDTO
        do {
            payload = try JSONDecoder().decode(KimiCompletionResponseDTO.self, from: responseBody)
        } catch {
            throw ConnectorError.decoding
        }
        let prompt = payload.usage.promptTokens
        let completion = payload.usage.completionTokens
        let cached = payload.usage.cachedTokens ?? 0
        guard prompt >= 0, completion >= 0, cached >= 0, cached <= prompt else {
            throw ConnectorError.decoding
        }
        let (computedTotal, totalOverflow) = prompt.addingReportingOverflow(completion)
        if totalOverflow
            || payload.usage.totalTokens.map({ $0 != computedTotal }) == true
        {
            throw ConnectorError.decoding
        }
        let (uncached, subtractionOverflow) = prompt.subtractingReportingOverflow(cached)
        guard !subtractionOverflow else { throw ConnectorError.decoding }
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
                identifier: "kimi_response_usage",
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
        components.host = "api.moonshot.ai"
        components.path = "/v1/"
        guard let url = components.url else {
            preconditionFailure("The compile-time Kimi URL must be valid")
        }
        return url
    }
}
