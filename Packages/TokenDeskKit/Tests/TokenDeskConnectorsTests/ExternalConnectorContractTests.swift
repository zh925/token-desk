import Foundation
import TokenDeskCore
@testable import TokenDeskConnectors
import XCTest

final class OpenAIConnectorContractTests: ProviderConnectorContractTestCase {
    func testSanitizedUsageAndCostFixturesSatisfyContract() async throws {
        let usageData = try fixtureData("v1/openai/usage.success.json")
        let costData = try fixtureData("v1/openai/cost.success.json")
        let client = StubHTTPClient(responses: [
            ConnectorHTTPResponse(data: usageData, statusCode: 200),
            ConnectorHTTPResponse(data: costData, statusCode: 200),
        ])
        let descriptor = try ProviderDescriptor(
            id: ProviderID(rawValue: "openai-primary"),
            type: ProviderType(rawValue: "openai"),
            displayName: "OpenAI",
            capabilities: ProviderCapabilities([.usage, .cost])
        )
        let credentialReference = try CredentialReference(rawValue: "credential-fixture")
        let account = try AccountReference(
            id: AccountID(rawValue: "organization-account"),
            providerID: descriptor.id,
            displayName: "Organization",
            scope: .organization,
            hierarchy: AccountHierarchy(
                organizationReference: "fixture-redacted",
                projectReference: "fixture-redacted"
            ),
            credentialReference: credentialReference
        )
        let connector = OpenAIConnector(
            descriptor: descriptor,
            credentialStore: try StaticCredentialStore(
                reference: credentialReference,
                value: "fixture-redacted"
            ),
            httpClient: client,
            baseURL: try XCTUnwrap(URL(string: "https://api.openai.test/v1/")),
            now: { Date(timeIntervalSince1970: 1_768_521_600) }
        )
        let interval = DateInterval(
            start: Date(timeIntervalSince1970: 1_768_435_200),
            end: Date(timeIntervalSince1970: 1_768_521_600)
        )

        try await assertConnectorContract(connector, account: account, interval: interval)

        let requests = await client.requests
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests[0].url?.path, "/v1/organization/usage/completions")
        XCTAssertEqual(requests[1].url?.path, "/v1/organization/costs")
        XCTAssertFalse(requests[0].url?.query?.contains("credential-fixture") == true)
    }

    func testMapsTokenCategoriesAndOfficialCostWithoutMixingThem() async throws {
        let client = StubHTTPClient(responses: [
            ConnectorHTTPResponse(
                data: try fixtureData("v1/openai/usage.success.json"),
                statusCode: 200
            ),
            ConnectorHTTPResponse(
                data: try fixtureData("v1/openai/cost.success.json"),
                statusCode: 200
            ),
        ])
        let (connector, account) = try makeOpenAIConnector(client: client)
        let interval = DateInterval(
            start: Date(timeIntervalSince1970: 1_768_435_200),
            end: Date(timeIntervalSince1970: 1_768_521_600)
        )

        let usage = try await connector.fetchUsage(for: account, in: interval)
        let costs = try await connector.fetchCosts(for: account, in: interval)

        XCTAssertEqual(usage.values.first?.tokens.input.rawValue, 1_000)
        XCTAssertEqual(usage.values.first?.tokens.cachedInput.rawValue, 200)
        XCTAssertEqual(usage.values.first?.tokens.output.rawValue, 340)
        XCTAssertEqual(usage.values.first?.projectReference, "fixture-redacted")
        XCTAssertEqual(costs.values.first?.money.amount, Decimal(string: "12.3456"))
        XCTAssertEqual(costs.values.first?.money.currency.rawValue, "USD")
        XCTAssertFalse(try XCTUnwrap(costs.values.first).isEstimated)
    }

    func testMapsAuthenticationPermissionRateLimitAndCancellation() async throws {
        let cases: [(Int, ConnectorError)] = [
            (401, .authentication),
            (403, .permissionDenied),
            (429, .rateLimited(retryAfter: .seconds(60))),
        ]
        for (status, expected) in cases {
            let client = StubHTTPClient(responses: [
                ConnectorHTTPResponse(
                    data: Data(),
                    statusCode: status,
                    headers: status == 429 ? ["retry-after": "60"] : [:]
                )
            ])
            let (connector, account) = try makeOpenAIConnector(client: client)
            do {
                _ = try await connector.fetchUsage(
                    for: account,
                    in: DateInterval(start: .distantPast, duration: 1)
                )
                XCTFail("Expected normalized HTTP failure")
            } catch let error as ConnectorError {
                XCTAssertEqual(error, expected)
            }
        }

        let client = StubHTTPClient(responses: [], delay: .seconds(60))
        let (connector, account) = try makeOpenAIConnector(client: client)
        let task = Task {
            try await connector.fetchUsage(
                for: account,
                in: DateInterval(start: .distantPast, duration: 1)
            )
        }
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Expected CancellationError")
        } catch is CancellationError {
            // Cancellation stays distinct from a network failure.
        }
    }

    private func makeOpenAIConnector(
        client: StubHTTPClient
    ) throws -> (OpenAIConnector, AccountReference) {
        let descriptor = try ProviderDescriptor(
            id: ProviderID(rawValue: "openai-primary"),
            type: ProviderType(rawValue: "openai"),
            displayName: "OpenAI",
            capabilities: ProviderCapabilities([.usage, .cost])
        )
        let reference = try CredentialReference(rawValue: "credential-fixture")
        let account = try AccountReference(
            id: AccountID(rawValue: "organization-account"),
            providerID: descriptor.id,
            displayName: "Organization",
            scope: .organization,
            hierarchy: AccountHierarchy(projectReference: "fixture-redacted"),
            credentialReference: reference
        )
        return (
            OpenAIConnector(
                descriptor: descriptor,
                credentialStore: try StaticCredentialStore(
                    reference: reference,
                    value: "fixture-redacted"
                ),
                httpClient: client,
                baseURL: try XCTUnwrap(URL(string: "https://api.openai.test/v1/")),
                now: { Date(timeIntervalSince1970: 1_768_521_600) }
            ),
            account
        )
    }
}

final class OpenMeteoConnectorContractTests: XCTestCase {
    func testMapsCurrentConditionsAndFourFutureHours() async throws {
        let client = StubHTTPClient(responses: [
            ConnectorHTTPResponse(
                data: try fixtureData("v1/open-meteo/weather.success.json"),
                statusCode: 200
            )
        ])
        let connector = OpenMeteoConnector(
            httpClient: client,
            baseURL: try XCTUnwrap(URL(string: "https://api.open-meteo.test/v1/forecast")),
            now: { Date(timeIntervalSince1970: 1_768_521_600) }
        )
        let location = try WeatherLocation(
            key: "shanghai",
            cityName: "Shanghai",
            latitude: Decimal(string: "31.23")!,
            longitude: Decimal(string: "121.47")!
        )

        let weather = try await connector.fetchWeather(for: location)

        XCTAssertEqual(weather.temperatureCelsius, Decimal(string: "8.4"))
        XCTAssertEqual(weather.apparentTemperatureCelsius, Decimal(string: "6.9"))
        XCTAssertEqual(weather.precipitationProbabilityPercent, 15)
        XCTAssertEqual(weather.humidityPercent, 68)
        XCTAssertEqual(weather.hourlyForecast.count, 4)
        XCTAssertEqual(weather.hourlyForecast.first?.temperatureCelsius, Decimal(string: "8.8"))
        XCTAssertEqual(weather.metadata.source.kind, .official)
        let requests = await client.requests
        let request = try XCTUnwrap(requests.first)
        XCTAssertTrue(request.url?.query?.contains("timezone=UTC") == true)
    }

    func testRejectsMisalignedHourlyArrays() async throws {
        let payload = Data(
            """
            {"current":{"time":"2026-01-15T08:15","temperature_2m":8,
            "apparent_temperature":7,"precipitation_probability":0,
            "relative_humidity_2m":50,"weather_code":1},"hourly":{"time":["2026-01-15T09:00"],
            "temperature_2m":[],"apparent_temperature":[7],"precipitation_probability":[0],
            "relative_humidity_2m":[50],"weather_code":[1]}}
            """.utf8
        )
        let connector = OpenMeteoConnector(
            httpClient: StubHTTPClient(
                responses: [ConnectorHTTPResponse(data: payload, statusCode: 200)]
            )
        )
        let location = try WeatherLocation(
            key: "city",
            cityName: "City",
            latitude: 0,
            longitude: 0
        )

        do {
            _ = try await connector.fetchWeather(for: location)
            XCTFail("Expected a decoding error")
        } catch let error as ConnectorError {
            XCTAssertEqual(error, .decoding)
        }
    }
}

actor StubHTTPClient: ConnectorHTTPClient {
    private var responses: [ConnectorHTTPResponse]
    private let delay: Duration?
    private(set) var requests: [URLRequest] = []

    init(responses: [ConnectorHTTPResponse], delay: Duration? = nil) {
        self.responses = responses
        self.delay = delay
    }

    func data(for request: URLRequest) async throws -> ConnectorHTTPResponse {
        requests.append(request)
        if let delay {
            try await Task.sleep(for: delay)
        }
        try Task.checkCancellation()
        guard !responses.isEmpty else {
            throw ConnectorError.network
        }
        return responses.removeFirst()
    }
}

final class StaticCredentialStore: CredentialStore, @unchecked Sendable {
    private let reference: CredentialReference
    private let credential: Credential

    init(reference: CredentialReference, value: String) throws {
        self.reference = reference
        self.credential = try Credential(utf8Value: value)
    }

    func save(_ credential: Credential, for accountID: AccountID) throws -> CredentialReference {
        reference
    }

    func credential(for reference: CredentialReference) throws -> Credential {
        guard reference == self.reference else { throw CredentialStoreError.notFound }
        return credential
    }

    func replace(_ credential: Credential, for reference: CredentialReference) throws {}
    func delete(for reference: CredentialReference) throws {}

    func configurationStatus(
        for reference: CredentialReference
    ) throws -> CredentialConfigurationStatus {
        reference == self.reference ? .configured : .notConfigured
    }
}

func fixtureData(_ path: String) throws -> Data {
    var root = URL(fileURLWithPath: #filePath)
    while root.lastPathComponent != "token-desk", root.pathComponents.count > 1 {
        root.deleteLastPathComponent()
    }
    return try Data(contentsOf: root.appending(path: "Fixtures").appending(path: path))
}
