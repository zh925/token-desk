import Foundation
import TokenDeskCore

/// Runs an explicit, redacted read against supported official Provider endpoints.
public struct OfficialProviderConnectionTester: ProviderConnectionTesting, Sendable {
    private let credentialStore: any CredentialStore
    private let localUsageRepository: any LocallyAggregatedUsageRepository
    private let httpClient: any ConnectorHTTPClient
    private let now: @Sendable () -> Date

    /// Creates a tester backed by Keychain, local aggregation, and an injectable HTTPS client.
    public init(
        credentialStore: any CredentialStore,
        localUsageRepository: any LocallyAggregatedUsageRepository,
        httpClient: any ConnectorHTTPClient = URLSessionConnectorHTTPClient(),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.credentialStore = credentialStore
        self.localUsageRepository = localUsageRepository
        self.httpClient = httpClient
        self.now = now
    }

    /// Performs the smallest official read that proves the configured account can connect.
    public func testConnection(
        for configuration: ProviderAccountConfiguration
    ) async throws -> ProviderConnectionTestResult {
        try Task.checkCancellation()
        let account = try configuration.accountReference
        let descriptor = try descriptor(for: configuration)
        let end = now()
        let interval = DateInterval(start: end.addingTimeInterval(-86_400), end: end)

        switch configuration.providerType.rawValue.lowercased() {
        case "openai":
            let connector = OpenAIConnector(
                descriptor: descriptor,
                credentialStore: credentialStore,
                httpClient: httpClient,
                now: now
            )
            let result = try await connector.fetchUsage(for: account, in: interval)
            return result.state == .unsupported
                ? .unsupported(reason: "该账户不提供 Usage 连接测试。") : .connected
        case "anthropic":
            let connector = AnthropicConnector(
                descriptor: descriptor,
                credentialStore: credentialStore,
                httpClient: httpClient,
                now: now
            )
            let result = try await connector.fetchUsage(for: account, in: interval)
            return result.state == .unsupported
                ? .unsupported(reason: "该账户不提供 Usage 连接测试。") : .connected
        case "deepseek":
            let connector = DeepSeekConnector(
                descriptor: descriptor,
                credentialStore: credentialStore,
                localUsageRepository: localUsageRepository,
                httpClient: httpClient,
                now: now
            )
            _ = try await connector.fetchBalance(for: account)
            return .connected
        case "kimi":
            let connector = KimiConnector(
                descriptor: descriptor,
                credentialStore: credentialStore,
                localUsageRepository: localUsageRepository,
                balanceCurrency: try CurrencyCode(rawValue: "CNY"),
                httpClient: httpClient,
                now: now
            )
            _ = try await connector.fetchBalance(for: account)
            return .connected
        case "openrouter":
            let connector = OpenRouterConnector(
                descriptor: descriptor,
                credentialStore: credentialStore,
                creditCurrency: try CurrencyCode(rawValue: "USD"),
                httpClient: httpClient,
                now: now
            )
            _ = try await connector.fetchBalance(for: account)
            return .connected
        default:
            if let reference = configuration.credentialReference {
                guard try credentialStore.configurationStatus(for: reference) == .configured else {
                    throw ConnectorError.authentication
                }
                return .credentialConfigured
            }
            return .unsupported(reason: "该 Provider 尚无公开的连接测试端点。")
        }
    }

    private func descriptor(
        for configuration: ProviderAccountConfiguration
    ) throws -> ProviderDescriptor {
        let capabilities: Set<ProviderCapability> =
            switch configuration.providerType.rawValue
                .lowercased()
            {
            case "openai", "anthropic": [.usage, .cost]
            case "deepseek", "kimi": [.usage, .cost, .balance, .localEstimate]
            case "openrouter": [.balance]
            default: []
            }
        return try ProviderDescriptor(
            id: configuration.providerID,
            type: configuration.providerType,
            displayName: configuration.providerDisplayName,
            capabilities: ProviderCapabilities(capabilities)
        )
    }
}
