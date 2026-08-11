import Foundation
import TokenDeskCore

/// Official OpenAI organization Usage and Costs API connector.
public struct OpenAIConnector: ProviderConnector, Sendable {
    /// Configured OpenAI instance and its explicit Usage/Costs capabilities.
    public let descriptor: ProviderDescriptor

    private let credentialStore: any CredentialStore
    private let httpClient: any ConnectorHTTPClient
    private let baseURL: URL
    private let now: @Sendable () -> Date

    /// Creates an OpenAI connector without retaining credential material outside Keychain access.
    public init(
        descriptor: ProviderDescriptor,
        credentialStore: any CredentialStore,
        httpClient: any ConnectorHTTPClient = URLSessionConnectorHTTPClient(),
        baseURL: URL? = nil,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.descriptor = descriptor
        self.credentialStore = credentialStore
        self.httpClient = httpClient
        self.baseURL = baseURL ?? Self.productionBaseURL
        self.now = now
    }

    /// Confirms that the account owns a readable credential reference without exposing its value.
    public func validateCredentials(for account: AccountReference) async throws {
        try Task.checkCancellation()
        _ = try authorizationValue(for: account)
    }

    /// Account discovery remains explicit because the Usage API is scoped by configured credentials.
    public func fetchAccounts() async throws -> ConnectorReadResult<RemoteAccount> {
        try Task.checkCancellation()
        return .notSynchronized
    }

    /// OpenAI API metering does not expose subscription plan windows.
    public func fetchPlan(
        for account: AccountReference
    ) async throws -> ConnectorReadResult<PlanWindow> {
        try Task.checkCancellation()
        return .unsupported
    }

    /// Fetches paginated organization completion usage and maps tokens by project and model.
    public func fetchUsage(
        for account: AccountReference,
        in interval: DateInterval
    ) async throws -> ConnectorReadResult<TokenUsageBucket> {
        try validate(account: account, capability: .usage)
        var page: String?
        var pagesRead = 0
        var buckets: [TokenUsageBucket] = []
        repeat {
            try Task.checkCancellation()
            let response = try await request(
                path: "organization/usage/completions",
                account: account,
                queryItems: usageQuery(interval: interval, account: account, page: page)
            )
            let payload: OpenAIUsagePageDTO = try decode(response)
            for bucket in payload.data {
                buckets.append(
                    contentsOf: try normalizedMapping { try mapUsage(bucket, account: account) }
                )
            }
            page = payload.hasMore ? payload.nextPage : nil
            pagesRead += 1
            guard pagesRead < 100 || page == nil else {
                throw ConnectorError.decoding
            }
            if payload.hasMore, page == nil {
                throw ConnectorError.decoding
            }
        } while page != nil
        return .available(buckets)
    }

    /// Fetches paginated official organization costs and preserves their returned currency.
    public func fetchCosts(
        for account: AccountReference,
        in interval: DateInterval
    ) async throws -> ConnectorReadResult<CostSnapshot> {
        try validate(account: account, capability: .cost)
        var page: String?
        var pagesRead = 0
        var costs: [CostSnapshot] = []
        repeat {
            try Task.checkCancellation()
            let response = try await request(
                path: "organization/costs",
                account: account,
                queryItems: costQuery(interval: interval, account: account, page: page)
            )
            let payload: OpenAICostPageDTO = try decode(response)
            for bucket in payload.data {
                costs.append(
                    contentsOf: try normalizedMapping { try mapCosts(bucket, account: account) }
                )
            }
            page = payload.hasMore ? payload.nextPage : nil
            pagesRead += 1
            guard pagesRead < 100 || page == nil else {
                throw ConnectorError.decoding
            }
            if payload.hasMore, page == nil {
                throw ConnectorError.decoding
            }
        } while page != nil
        return .available(costs)
    }

    /// OpenAI's organization metering API does not expose an account balance capability.
    public func fetchBalance(
        for account: AccountReference
    ) async throws -> ConnectorReadResult<BalanceSnapshot> {
        try Task.checkCancellation()
        return .unsupported
    }

    /// Returns a redacted initial health value until synchronization records a concrete outcome.
    public func fetchHealth() async -> ConnectorHealth {
        ConnectorHealth(
            providerID: descriptor.id,
            state: .notSynchronized,
            checkedAt: now()
        )
    }

    private func validate(account: AccountReference, capability: ProviderCapability) throws {
        guard account.providerID == descriptor.id else {
            throw ConnectorError.permissionDenied
        }
        guard descriptor.capabilities.contains(capability) else {
            throw ConnectorError.unsupported(capability: capability)
        }
    }

    private func request(
        path: String,
        account: AccountReference,
        queryItems: [URLQueryItem]
    ) async throws -> ConnectorHTTPResponse {
        let endpoint = baseURL.appending(path: path)
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)
        components?.queryItems = queryItems
        guard let url = components?.url else {
            throw ConnectorError.decoding
        }
        var request = URLRequest(url: url)
        request.setValue(
            "Bearer " + (try authorizationValue(for: account)), forHTTPHeaderField: "Authorization")
        if let organization = account.hierarchy.organizationReference {
            request.setValue(organization, forHTTPHeaderField: "OpenAI-Organization")
        }
        let response = try await httpClient.data(for: request)
        try Task.checkCancellation()
        try ConnectorHTTPStatus.validate(response)
        return response
    }

    private func authorizationValue(for account: AccountReference) throws -> String {
        guard let reference = account.credentialReference else {
            throw ConnectorError.authentication
        }
        do {
            return try credentialStore.credential(for: reference).withData { data in
                guard let value = String(data: data, encoding: .utf8), !value.isEmpty else {
                    throw ConnectorError.authentication
                }
                return value
            }
        } catch let error as ConnectorError {
            throw error
        } catch {
            throw ConnectorError.authentication
        }
    }

    private func usageQuery(
        interval: DateInterval,
        account: AccountReference,
        page: String?
    ) -> [URLQueryItem] {
        var items = commonQuery(interval: interval, account: account, page: page)
        items.append(URLQueryItem(name: "group_by", value: "project_id"))
        items.append(URLQueryItem(name: "group_by", value: "model"))
        return items
    }

    private func costQuery(
        interval: DateInterval,
        account: AccountReference,
        page: String?
    ) -> [URLQueryItem] {
        var items = commonQuery(interval: interval, account: account, page: page)
        items.append(URLQueryItem(name: "group_by", value: "project_id"))
        return items
    }

    private func commonQuery(
        interval: DateInterval,
        account: AccountReference,
        page: String?
    ) -> [URLQueryItem] {
        var items = [
            URLQueryItem(
                name: "start_time", value: String(Int64(interval.start.timeIntervalSince1970))),
            URLQueryItem(
                name: "end_time", value: String(Int64(interval.end.timeIntervalSince1970))),
            URLQueryItem(name: "bucket_width", value: "1d"),
            URLQueryItem(name: "limit", value: "31"),
        ]
        if let project = account.hierarchy.projectReference {
            items.append(URLQueryItem(name: "project_ids", value: project))
        }
        if let page {
            items.append(URLQueryItem(name: "page", value: page))
        }
        return items
    }

    private func decode<Value: Decodable>(_ response: ConnectorHTTPResponse) throws -> Value {
        do {
            return try JSONDecoder().decode(Value.self, from: response.data)
        } catch {
            throw ConnectorError.decoding
        }
    }

    private func normalizedMapping<Value>(_ body: () throws -> Value) throws -> Value {
        do {
            return try body()
        } catch let error as ConnectorError {
            throw error
        } catch {
            throw ConnectorError.decoding
        }
    }

    private func mapUsage(
        _ bucket: OpenAIUsageBucketDTO,
        account: AccountReference
    ) throws -> [TokenUsageBucket] {
        let period = try usagePeriod(start: bucket.startTime, end: bucket.endTime)
        return try bucket.results.map { result in
            let cached = result.inputCachedTokens ?? 0
            let cacheWrite = result.inputCacheCreationTokens ?? 0
            let uncached =
                result.inputUncachedTokens
                ?? max(0, result.inputTokens - cached - cacheWrite)
            return try TokenUsageBucket(
                providerID: descriptor.id,
                accountID: account.id,
                projectReference: result.projectID ?? account.hierarchy.projectReference,
                model: result.model ?? "all-models",
                granularity: .day,
                period: period,
                tokens: TokenBreakdown(
                    input: TokenCount(rawValue: uncached),
                    output: TokenCount(rawValue: result.outputTokens),
                    cachedInput: TokenCount(rawValue: cached),
                    cacheWrite: TokenCount(rawValue: cacheWrite)
                ),
                metadata: ObservationMetadata(
                    source: try DataSource(
                        kind: .official,
                        identifier: "openai_organization_usage_api"
                    ),
                    updatedAt: now(),
                    isStale: false
                )
            )
        }
    }

    private func mapCosts(
        _ bucket: OpenAICostBucketDTO,
        account: AccountReference
    ) throws -> [CostSnapshot] {
        struct Key: Hashable {
            let project: String?
            let currency: CurrencyCode
        }
        var totals: [Key: Decimal] = [:]
        for result in bucket.results {
            guard let amount = result.amount else { continue }
            let currency = try CurrencyCode(rawValue: amount.currency)
            let key = Key(
                project: result.projectID ?? account.hierarchy.projectReference,
                currency: currency
            )
            totals[key, default: 0] += amount.value
        }
        let period = try usagePeriod(start: bucket.startTime, end: bucket.endTime)
        return try totals.map { key, value in
            CostSnapshot(
                providerID: descriptor.id,
                accountID: account.id,
                projectReference: key.project,
                period: period,
                money: Money(amount: value, currency: key.currency),
                metadata: ObservationMetadata(
                    source: try DataSource(
                        kind: .official,
                        identifier: "openai_organization_costs_api"
                    ),
                    updatedAt: now(),
                    isStale: false
                )
            )
        }
    }

    private func usagePeriod(start: Int64, end: Int64) throws -> UsagePeriod {
        try UsagePeriod(
            interval: DateInterval(
                start: Date(timeIntervalSince1970: TimeInterval(start)),
                end: Date(timeIntervalSince1970: TimeInterval(end))
            ),
            timeZoneIdentifier: "UTC"
        )
    }

    private static var productionBaseURL: URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.openai.com"
        components.path = "/v1/"
        guard let url = components.url else {
            preconditionFailure("The compile-time OpenAI URL must be valid")
        }
        return url
    }
}
