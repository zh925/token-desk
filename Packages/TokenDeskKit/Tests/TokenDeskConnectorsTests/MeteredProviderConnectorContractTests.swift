import Foundation
import TokenDeskCore
@testable import TokenDeskConnectors
import XCTest

final class AnthropicConnectorContractTests: ProviderConnectorContractTestCase {
    func testUsageAndFractionalCentCostFixturesSatisfyOrganizationContract() async throws {
        let client = StubHTTPClient(responses: [
            ConnectorHTTPResponse(
                data: try fixtureData("v1/anthropic/usage.success.json"),
                statusCode: 200
            ),
            ConnectorHTTPResponse(
                data: try fixtureData("v1/anthropic/cost.success.json"),
                statusCode: 200
            ),
            ConnectorHTTPResponse(
                data: try fixtureData("v1/anthropic/usage.success.json"),
                statusCode: 200
            ),
            ConnectorHTTPResponse(
                data: try fixtureData("v1/anthropic/cost.success.json"),
                statusCode: 200
            ),
        ])
        let descriptor = try makeDescriptor(
            id: "anthropic-primary",
            type: "anthropic",
            capabilities: [.usage, .cost]
        )
        let (account, credentialStore) = try makeAccountAndCredential(
            descriptor: descriptor,
            scope: .organization,
            workspace: "fixture-redacted"
        )
        let connector = AnthropicConnector(
            descriptor: descriptor,
            credentialStore: credentialStore,
            httpClient: client,
            baseURL: try XCTUnwrap(URL(string: "https://api.anthropic.test/v1/")),
            now: fixtureNow
        )
        let interval = fixtureInterval

        try await assertConnectorContract(connector, account: account, interval: interval)

        let mappedUsage = try await connector.fetchUsage(for: account, in: interval)
        let mappedCosts = try await connector.fetchCosts(for: account, in: interval)
        let usage = try XCTUnwrap(mappedUsage.values.first)
        let cost = try XCTUnwrap(mappedCosts.values.first)
        XCTAssertEqual(usage.tokens.input.rawValue, 900)
        XCTAssertEqual(usage.tokens.cachedInput.rawValue, 200)
        XCTAssertEqual(usage.tokens.cacheWrite.rawValue, 100)
        XCTAssertEqual(usage.workspaceReference, "fixture-redacted")
        XCTAssertEqual(cost.money.amount, Decimal(string: "1.2345"))
        XCTAssertEqual(cost.money.currency.rawValue, "USD")
        XCTAssertFalse(cost.isEstimated)

        let requests = await client.requests
        XCTAssertEqual(requests.first?.value(forHTTPHeaderField: "anthropic-version"), "2023-06-01")
        XCTAssertEqual(requests.first?.url?.path, "/v1/organizations/usage_report/messages")
        XCTAssertEqual(requests[1].url?.path, "/v1/organizations/cost_report")
        XCTAssertTrue(requests.first?.url?.query?.contains("group_by%5B%5D=model") == true)
    }

    func testPersonalScopeIsRejectedBeforeTransport() async throws {
        let descriptor = try makeDescriptor(
            id: "anthropic-primary",
            type: "anthropic",
            capabilities: [.usage]
        )
        let (account, credentialStore) = try makeAccountAndCredential(
            descriptor: descriptor,
            scope: .personal
        )
        let client = StubHTTPClient(responses: [])
        let connector = AnthropicConnector(
            descriptor: descriptor,
            credentialStore: credentialStore,
            httpClient: client
        )

        do {
            _ = try await connector.fetchUsage(for: account, in: fixtureInterval)
            XCTFail("Expected organization-only scope rejection")
        } catch let error as ConnectorError {
            XCTAssertEqual(error, .permissionDenied)
        }
        let requests = await client.requests
        XCTAssertTrue(requests.isEmpty)
    }
}

final class DeepSeekConnectorContractTests: ProviderConnectorContractTestCase {
    func testBalanceResponseUsageAndEstimatedCostsSatisfyContract() async throws {
        let descriptor = try makeDescriptor(
            id: "deepseek-primary",
            type: "deepseek",
            capabilities: [.usage, .cost, .balance, .localEstimate]
        )
        let (account, credentialStore) = try makeAccountAndCredential(descriptor: descriptor)
        let usageRepository = InMemoryLocalUsageRepository()
        let pricing = try StaticPricingCatalog(
            providerType: descriptor.type,
            currency: CurrencyCode(rawValue: "CNY"),
            model: "deepseek-chat-example"
        )
        let client = StubHTTPClient(responses: [
            ConnectorHTTPResponse(
                data: try fixtureData("v1/deepseek/balance.success.json"),
                statusCode: 200
            ),
            ConnectorHTTPResponse(
                data: try fixtureData("v1/deepseek/balance.success.json"),
                statusCode: 200
            ),
        ])
        let connector = DeepSeekConnector(
            descriptor: descriptor,
            credentialStore: credentialStore,
            localUsageRepository: usageRepository,
            pricingCatalog: pricing,
            estimatedCostCurrency: try CurrencyCode(rawValue: "CNY"),
            httpClient: client,
            baseURL: try XCTUnwrap(URL(string: "https://api.deepseek.test/")),
            now: fixtureNow
        )
        let response = try fixtureData("v1/deepseek/usage.success.json")
        try connector.recordResponseUsage(from: response, for: account)
        try connector.recordResponseUsage(from: response, for: account)

        try await assertConnectorContract(connector, account: account, interval: fixtureInterval)

        let usage = try await connector.fetchUsage(for: account, in: fixtureInterval)
        let costs = try await connector.fetchCosts(for: account, in: fixtureInterval)
        let balance = try await connector.fetchBalance(for: account)
        XCTAssertEqual(usage.values.count, 1)
        XCTAssertEqual(usage.values.first?.tokens.input.rawValue, 2_000)
        XCTAssertEqual(usage.values.first?.tokens.cachedInput.rawValue, 400)
        XCTAssertEqual(usage.values.first?.tokens.output.rawValue, 680)
        XCTAssertEqual(usage.values.first?.metadata.source.kind, .locallyAggregated)
        XCTAssertEqual(costs.values.first?.money.amount, Decimal(string: "0.0056"))
        XCTAssertTrue(try XCTUnwrap(costs.values.first).isEstimated)
        XCTAssertEqual(balance.values.first?.available.amount, Decimal(string: "18.2500"))
        XCTAssertEqual(balance.values.first?.available.currency.rawValue, "CNY")
    }
}

final class KimiConnectorContractTests: ProviderConnectorContractTestCase {
    func testConfiguredCurrencyBalanceAndLocalUsageSatisfyContract() async throws {
        let descriptor = try makeDescriptor(
            id: "kimi-primary",
            type: "kimi",
            capabilities: [.usage, .cost, .balance, .localEstimate]
        )
        let (account, credentialStore) = try makeAccountAndCredential(descriptor: descriptor)
        let usageRepository = InMemoryLocalUsageRepository()
        let currency = try CurrencyCode(rawValue: "USD")
        let pricing = try StaticPricingCatalog(
            providerType: descriptor.type,
            currency: currency,
            model: "kimi-example"
        )
        let client = StubHTTPClient(responses: [
            ConnectorHTTPResponse(
                data: try fixtureData("v1/kimi/balance.success.json"),
                statusCode: 200
            ),
            ConnectorHTTPResponse(
                data: try fixtureData("v1/kimi/balance.success.json"),
                statusCode: 200
            ),
        ])
        let connector = KimiConnector(
            descriptor: descriptor,
            credentialStore: credentialStore,
            localUsageRepository: usageRepository,
            balanceCurrency: currency,
            pricingCatalog: pricing,
            estimatedCostCurrency: currency,
            httpClient: client,
            baseURL: try XCTUnwrap(URL(string: "https://api.moonshot.test/v1/")),
            now: fixtureNow
        )
        try connector.recordResponseUsage(
            from: fixtureData("v1/kimi/usage.success.json"),
            for: account
        )

        try await assertConnectorContract(connector, account: account, interval: fixtureInterval)

        let usage = try await connector.fetchUsage(for: account, in: fixtureInterval)
        let balance = try await connector.fetchBalance(for: account)
        XCTAssertEqual(usage.values.first?.tokens.input.rawValue, 1_000)
        XCTAssertEqual(usage.values.first?.tokens.cachedInput.rawValue, 200)
        XCTAssertEqual(usage.values.first?.tokens.output.rawValue, 340)
        XCTAssertEqual(balance.values.first?.available.amount, Decimal(string: "49.58894"))
        XCTAssertEqual(balance.values.first?.available.currency, currency)
    }
}

final class OpenRouterConnectorContractTests: ProviderConnectorContractTestCase {
    func testCreditTotalsAndAvailableBalanceSatisfyContract() async throws {
        let descriptor = try makeDescriptor(
            id: "openrouter-primary",
            type: "openrouter",
            capabilities: [.balance]
        )
        let (account, credentialStore) = try makeAccountAndCredential(descriptor: descriptor)
        let client = StubHTTPClient(responses: [
            ConnectorHTTPResponse(
                data: try fixtureData("v1/openrouter/credits.success.json"),
                statusCode: 200
            ),
            ConnectorHTTPResponse(
                data: try fixtureData("v1/openrouter/credits.success.json"),
                statusCode: 200
            ),
        ])
        let connector = OpenRouterConnector(
            descriptor: descriptor,
            credentialStore: credentialStore,
            creditCurrency: try CurrencyCode(rawValue: "USD"),
            httpClient: client,
            baseURL: try XCTUnwrap(URL(string: "https://openrouter.test/api/v1/")),
            now: fixtureNow
        )

        try await assertConnectorContract(connector, account: account, interval: fixtureInterval)

        let result = try await connector.fetchBalance(for: account)
        let balance = try XCTUnwrap(result.values.first)
        XCTAssertEqual(balance.available.amount, Decimal(string: "21.25"))
        XCTAssertEqual(balance.creditDetails?.totalCredited.amount, Decimal(string: "25.50"))
        XCTAssertEqual(balance.creditDetails?.totalConsumed.amount, Decimal(string: "4.25"))
        let requests = await client.requests
        XCTAssertEqual(requests.first?.url?.path, "/api/v1/credits")
    }

    func testManagementKeyPermissionAndRateLimitAreNormalized() async throws {
        let descriptor = try makeDescriptor(
            id: "openrouter-primary",
            type: "openrouter",
            capabilities: [.balance]
        )
        let (account, credentialStore) = try makeAccountAndCredential(descriptor: descriptor)
        for (response, expected) in [
            (ConnectorHTTPResponse(data: Data(), statusCode: 403), ConnectorError.permissionDenied),
            (
                ConnectorHTTPResponse(
                    data: Data(),
                    statusCode: 429,
                    headers: ["retry-after": "3"]
                ),
                ConnectorError.rateLimited(retryAfter: .seconds(3))
            ),
        ] {
            let connector = OpenRouterConnector(
                descriptor: descriptor,
                credentialStore: credentialStore,
                creditCurrency: try CurrencyCode(rawValue: "USD"),
                httpClient: StubHTTPClient(responses: [response])
            )
            do {
                _ = try await connector.fetchBalance(for: account)
                XCTFail("Expected normalized transport error")
            } catch let error as ConnectorError {
                XCTAssertEqual(error, expected)
            }
        }
    }
}
