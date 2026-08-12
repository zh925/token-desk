import Foundation
import TokenDeskCore

/// Official Anthropic organization Usage and Cost Admin API connector.
public struct AnthropicConnector: ProviderConnector, Sendable {
    /// Configured Anthropic organization instance and its explicit capabilities.
    public let descriptor: ProviderDescriptor

    private let runtime: ProviderConnectorRuntime

    /// Creates a connector that reads an Admin API key only through the credential store.
    public init(
        descriptor: ProviderDescriptor,
        credentialStore: any CredentialStore,
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
    }

    /// Checks the local Admin API credential reference and organization-only account scope.
    public func validateCredentials(for account: AccountReference) async throws {
        try Task.checkCancellation()
        try runtime.validate(account: account, permittedScopes: [.organization])
        try runtime.validateCredentials(for: account)
    }

    /// Account discovery is deferred; configured organization/workspace references remain explicit.
    public func fetchAccounts() async throws -> ConnectorReadResult<RemoteAccount> {
        try Task.checkCancellation()
        return .notSynchronized
    }

    /// Anthropic API metering does not expose subscription quota windows.
    public func fetchPlan(
        for account: AccountReference
    ) async throws -> ConnectorReadResult<PlanWindow> {
        try Task.checkCancellation()
        return .unsupported
    }

    /// Fetches paginated daily token usage grouped by model and workspace.
    public func fetchUsage(
        for account: AccountReference,
        in interval: DateInterval
    ) async throws -> ConnectorReadResult<TokenUsageBucket> {
        try runtime.validate(
            account: account,
            capability: .usage,
            permittedScopes: [.organization]
        )
        var page: String?
        var pagesRead = 0
        var usage: [TokenUsageBucket] = []
        repeat {
            try Task.checkCancellation()
            let response = try await runtime.request(
                path: "organizations/usage_report/messages",
                account: account,
                authorization: .anthropicAdmin,
                queryItems: query(interval: interval, account: account, page: page, isCost: false)
            )
            let payload = try runtime.decode(AnthropicUsagePageDTO.self, from: response)
            for bucket in payload.data {
                usage.append(contentsOf: try map(bucket, account: account))
            }
            page = try nextPage(payload.hasMore, payload.nextPage, pagesRead: &pagesRead)
        } while page != nil
        return .available(usage)
    }

    /// Fetches paginated official daily costs and converts fractional cents to USD units exactly.
    public func fetchCosts(
        for account: AccountReference,
        in interval: DateInterval
    ) async throws -> ConnectorReadResult<CostSnapshot> {
        try runtime.validate(
            account: account,
            capability: .cost,
            permittedScopes: [.organization]
        )
        var page: String?
        var pagesRead = 0
        var costs: [CostSnapshot] = []
        repeat {
            try Task.checkCancellation()
            let response = try await runtime.request(
                path: "organizations/cost_report",
                account: account,
                authorization: .anthropicAdmin,
                queryItems: query(interval: interval, account: account, page: page, isCost: true)
            )
            let payload = try runtime.decode(AnthropicCostPageDTO.self, from: response)
            for bucket in payload.data {
                costs.append(contentsOf: try map(bucket, account: account))
            }
            page = try nextPage(payload.hasMore, payload.nextPage, pagesRead: &pagesRead)
        } while page != nil
        return .available(costs)
    }

    /// Anthropic's organization reporting API does not expose an account balance.
    public func fetchBalance(
        for account: AccountReference
    ) async throws -> ConnectorReadResult<BalanceSnapshot> {
        try Task.checkCancellation()
        return .unsupported
    }

    /// Returns a redacted initial state until synchronization records a concrete outcome.
    public func fetchHealth() async -> ConnectorHealth {
        ConnectorHealth(
            providerID: descriptor.id,
            state: .notSynchronized,
            checkedAt: runtime.now()
        )
    }

    private func query(
        interval: DateInterval,
        account: AccountReference,
        page: String?,
        isCost: Bool
    ) -> [URLQueryItem] {
        var items = [
            URLQueryItem(name: "starting_at", value: ProviderMapping.dateString(interval.start)),
            URLQueryItem(name: "ending_at", value: ProviderMapping.dateString(interval.end)),
            URLQueryItem(name: "bucket_width", value: "1d"),
            URLQueryItem(name: "limit", value: "31"),
            URLQueryItem(name: "group_by[]", value: "workspace_id"),
        ]
        if !isCost {
            items.append(URLQueryItem(name: "group_by[]", value: "model"))
        }
        if let workspace = account.hierarchy.workspaceReference {
            items.append(URLQueryItem(name: "workspace_ids[]", value: workspace))
        }
        if let page { items.append(URLQueryItem(name: "page", value: page)) }
        return items
    }

    private func nextPage(
        _ hasMore: Bool,
        _ nextPage: String?,
        pagesRead: inout Int
    ) throws -> String? {
        pagesRead += 1
        guard pagesRead < 100 || !hasMore else { throw ConnectorError.decoding }
        guard !hasMore || nextPage != nil else { throw ConnectorError.decoding }
        return hasMore ? nextPage : nil
    }

    private func map(
        _ bucket: AnthropicUsageBucketDTO,
        account: AccountReference
    ) throws -> [TokenUsageBucket] {
        let period = try ProviderMapping.period(start: bucket.startingAt, end: bucket.endingAt)
        return try bucket.results.map { result in
            let cacheWrite = try TokenCount(
                rawValue: result.cacheCreation.ephemeralFiveMinuteInputTokens
            ).adding(
                TokenCount(rawValue: result.cacheCreation.ephemeralOneHourInputTokens)
            )
            return try TokenUsageBucket(
                providerID: descriptor.id,
                accountID: account.id,
                workspaceReference: result.workspaceID ?? account.hierarchy.workspaceReference,
                model: result.model ?? "all-models",
                granularity: .day,
                period: period,
                tokens: TokenBreakdown(
                    input: TokenCount(rawValue: result.uncachedInputTokens),
                    output: TokenCount(rawValue: result.outputTokens),
                    cachedInput: TokenCount(rawValue: result.cacheReadInputTokens),
                    cacheWrite: cacheWrite
                ),
                metadata: try ProviderMapping.metadata(
                    kind: .official,
                    identifier: "anthropic_organization_usage_api",
                    updatedAt: runtime.now()
                )
            )
        }
    }

    private func map(
        _ bucket: AnthropicCostBucketDTO,
        account: AccountReference
    ) throws -> [CostSnapshot] {
        struct Key: Hashable {
            let workspace: String?
            let currency: CurrencyCode
        }
        var totals: [Key: Decimal] = [:]
        for result in bucket.results {
            guard
                let cents = Decimal(
                    string: result.amount, locale: Locale(identifier: "en_US_POSIX"))
            else {
                throw ConnectorError.decoding
            }
            let key = try Key(
                workspace: result.workspaceID ?? account.hierarchy.workspaceReference,
                currency: CurrencyCode(rawValue: result.currency)
            )
            totals[key, default: 0] += cents / 100
        }
        let period = try ProviderMapping.period(start: bucket.startingAt, end: bucket.endingAt)
        return try totals.map { key, amount in
            CostSnapshot(
                providerID: descriptor.id,
                accountID: account.id,
                workspaceReference: key.workspace,
                period: period,
                money: Money(amount: amount, currency: key.currency),
                metadata: try ProviderMapping.metadata(
                    kind: .official,
                    identifier: "anthropic_organization_cost_api",
                    updatedAt: runtime.now()
                )
            )
        }
    }

    private static var productionBaseURL: URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.anthropic.com"
        components.path = "/v1/"
        guard let url = components.url else {
            preconditionFailure("The compile-time Anthropic URL must be valid")
        }
        return url
    }
}
