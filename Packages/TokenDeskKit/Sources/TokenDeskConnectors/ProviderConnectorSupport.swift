import Foundation
import TokenDeskCore

enum ConnectorAuthorization {
    case bearer
    case anthropicAdmin
}

struct ProviderConnectorRuntime: Sendable {
    let descriptor: ProviderDescriptor
    let credentialStore: any CredentialStore
    let httpClient: any ConnectorHTTPClient
    let baseURL: URL
    let now: @Sendable () -> Date

    func validate(
        account: AccountReference,
        capability: ProviderCapability? = nil,
        permittedScopes: Set<AccountScope> = Set(AccountScope.allCases)
    ) throws {
        guard account.providerID == descriptor.id, permittedScopes.contains(account.scope) else {
            throw ConnectorError.permissionDenied
        }
        if let capability, !descriptor.capabilities.contains(capability) {
            throw ConnectorError.unsupported(capability: capability)
        }
    }

    func validateCredentials(for account: AccountReference) throws {
        try validate(account: account)
        _ = try credential(for: account)
    }

    func request(
        path: String,
        account: AccountReference,
        authorization: ConnectorAuthorization,
        queryItems: [URLQueryItem] = []
    ) async throws -> ConnectorHTTPResponse {
        guard baseURL.scheme?.lowercased() == "https", baseURL.host != nil else {
            throw ConnectorError.network
        }
        let endpoint = baseURL.appending(path: path)
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)
        components?.queryItems = queryItems.isEmpty ? nil : queryItems
        guard let url = components?.url else { throw ConnectorError.decoding }

        var request = URLRequest(url: url, timeoutInterval: 30)
        let value = try credential(for: account)
        switch authorization {
        case .bearer:
            request.setValue("Bearer " + value, forHTTPHeaderField: "Authorization")
        case .anthropicAdmin:
            request.setValue(value, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            request.setValue("TokenDesk/1.0", forHTTPHeaderField: "User-Agent")
        }

        let response = try await httpClient.data(for: request)
        try Task.checkCancellation()
        try ConnectorHTTPStatus.validate(response)
        return response
    }

    func decode<Value: Decodable>(_ type: Value.Type, from response: ConnectorHTTPResponse) throws
        -> Value
    {
        do {
            return try JSONDecoder().decode(type, from: response.data)
        } catch {
            throw ConnectorError.decoding
        }
    }

    private func credential(for account: AccountReference) throws -> String {
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
}

struct LocalMeteredUsageContext: Sendable {
    let repository: any LocallyAggregatedUsageRepository
    let pricingCatalog: (any PricingCatalog)?
    let estimatedCostCurrency: CurrencyCode?
    let pricingRegion: String

    func usage(
        for account: AccountReference,
        in interval: DateInterval
    ) throws -> ConnectorReadResult<TokenUsageBucket> {
        .available(
            try repository.cachedUsage(for: account, in: interval, granularity: .minute)
        )
    }

    func costs(
        descriptor: ProviderDescriptor,
        account: AccountReference,
        interval: DateInterval,
        calculatedAt: Date
    ) throws -> ConnectorReadResult<CostSnapshot> {
        guard let pricingCatalog, let estimatedCostCurrency else {
            return .notSynchronized
        }
        let usage = try repository.cachedUsage(
            for: account,
            in: interval,
            granularity: .minute
        )
        var costs: [CostSnapshot] = []
        let calculator = CostCalculator()
        for bucket in usage {
            guard
                let rule = try pricingCatalog.rule(
                    providerType: descriptor.type,
                    model: bucket.model,
                    currency: estimatedCostCurrency,
                    region: pricingRegion,
                    effectiveAt: bucket.period.interval.start
                )
            else {
                return .notSynchronized
            }
            do {
                costs.append(
                    try calculator.estimate(
                        usage: bucket,
                        providerType: descriptor.type,
                        rule: rule,
                        at: calculatedAt
                    )
                )
            } catch {
                throw ConnectorError.decoding
            }
        }
        return .available(costs)
    }

    func record(_ bucket: TokenUsageBucket) throws {
        try repository.addLocallyAggregatedUsage([bucket])
    }
}

enum ProviderMapping {
    static func date(_ value: String) throws -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        guard let date = formatter.date(from: value) else { throw ConnectorError.decoding }
        return date
    }

    static func dateString(_ value: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = .gmt
        return formatter.string(from: value)
    }

    static func period(start: String, end: String) throws -> UsagePeriod {
        try UsagePeriod(
            interval: DateInterval(start: date(start), end: date(end)),
            timeZoneIdentifier: "UTC"
        )
    }

    static func minutePeriod(containing date: Date) throws -> UsagePeriod {
        try UsagePeriod.containing(
            date,
            granularity: .minute,
            calendar: Calendar(identifier: .gregorian),
            timeZone: TimeZone(secondsFromGMT: 0) ?? .gmt
        )
    }

    static func metadata(kind: DataSourceKind, identifier: String, updatedAt: Date) throws
        -> ObservationMetadata
    {
        ObservationMetadata(
            source: try DataSource(kind: kind, identifier: identifier),
            updatedAt: updatedAt,
            isStale: false
        )
    }
}

struct LosslessDecimalDTO: Decodable {
    let value: Decimal

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let decimal = try? container.decode(Decimal.self) {
            value = decimal
            return
        }
        let string = try container.decode(String.self)
        guard let decimal = Decimal(string: string, locale: Locale(identifier: "en_US_POSIX"))
        else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Expected an exact decimal string"
            )
        }
        value = decimal
    }
}
