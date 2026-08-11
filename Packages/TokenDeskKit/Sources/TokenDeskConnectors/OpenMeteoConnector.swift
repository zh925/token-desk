import Foundation
import TokenDeskCore

/// Official Open-Meteo forecast implementation using only its public HTTPS API.
public struct OpenMeteoConnector: WeatherService, Sendable {
    private let httpClient: any ConnectorHTTPClient
    private let baseURL: URL
    private let now: @Sendable () -> Date

    /// Creates an Open-Meteo client with injectable transport, endpoint, and observation clock.
    public init(
        httpClient: any ConnectorHTTPClient = URLSessionConnectorHTTPClient(),
        baseURL: URL? = nil,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.httpClient = httpClient
        self.baseURL = baseURL ?? Self.productionBaseURL
        self.now = now
    }

    /// Fetches official current conditions and the next four hourly points in UTC.
    public func fetchWeather(for location: WeatherLocation) async throws -> WeatherSnapshot {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "latitude", value: decimalString(location.latitude)),
            URLQueryItem(name: "longitude", value: decimalString(location.longitude)),
            URLQueryItem(
                name: "current",
                value: [
                    "temperature_2m", "apparent_temperature", "precipitation_probability",
                    "relative_humidity_2m", "weather_code",
                ].joined(separator: ",")
            ),
            URLQueryItem(
                name: "hourly",
                value: [
                    "temperature_2m", "apparent_temperature", "precipitation_probability",
                    "relative_humidity_2m", "weather_code",
                ].joined(separator: ",")
            ),
            URLQueryItem(name: "forecast_hours", value: "6"),
            URLQueryItem(name: "timezone", value: "UTC"),
        ]
        guard let url = components?.url else {
            throw ConnectorError.decoding
        }
        let response = try await httpClient.data(for: URLRequest(url: url))
        try Task.checkCancellation()
        try ConnectorHTTPStatus.validate(response)

        let payload: OpenMeteoForecastResponseDTO
        do {
            payload = try JSONDecoder().decode(
                OpenMeteoForecastResponseDTO.self, from: response.data)
        } catch {
            throw ConnectorError.decoding
        }
        let observedAt = try parseDate(payload.current.time)
        let hourly = try mapHourly(payload.hourly, from: observedAt)
        return WeatherSnapshot(
            location: location,
            observedAt: observedAt,
            temperatureCelsius: payload.current.temperature,
            apparentTemperatureCelsius: payload.current.apparentTemperature,
            precipitationProbabilityPercent: payload.current.precipitationProbability,
            humidityPercent: payload.current.humidity,
            conditionCode: payload.current.weatherCode,
            hourlyForecast: hourly,
            metadata: ObservationMetadata(
                source: try DataSource(kind: .official, identifier: "open_meteo_forecast_api"),
                updatedAt: now(),
                isStale: false
            )
        )
    }

    private func mapHourly(
        _ hourly: OpenMeteoHourlyDTO,
        from observedAt: Date
    ) throws -> [HourlyWeatherForecast] {
        let count = hourly.time.count
        guard
            count == hourly.temperature.count,
            count == hourly.apparentTemperature.count,
            count == hourly.precipitationProbability.count,
            count == hourly.humidity.count,
            count == hourly.weatherCode.count
        else {
            throw ConnectorError.decoding
        }
        return try hourly.time.indices.compactMap { index in
            let startsAt = try parseDate(hourly.time[index])
            guard startsAt >= observedAt else { return nil }
            return HourlyWeatherForecast(
                startsAt: startsAt,
                temperatureCelsius: hourly.temperature[index],
                apparentTemperatureCelsius: hourly.apparentTemperature[index],
                precipitationProbabilityPercent: hourly.precipitationProbability[index],
                humidityPercent: hourly.humidity[index],
                conditionCode: hourly.weatherCode[index]
            )
        }
    }

    private func parseDate(_ value: String) throws -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: value) ?? formatter.date(from: value + ":00Z") {
            return date
        }
        throw ConnectorError.decoding
    }

    private func decimalString(_ value: Decimal) -> String {
        NSDecimalNumber(decimal: value).stringValue
    }

    private static var productionBaseURL: URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.open-meteo.com"
        components.path = "/v1/forecast"
        guard let url = components.url else {
            preconditionFailure("The compile-time Open-Meteo URL must be valid")
        }
        return url
    }
}

private struct OpenMeteoForecastResponseDTO: Decodable {
    let current: OpenMeteoCurrentDTO
    let hourly: OpenMeteoHourlyDTO
}

private struct OpenMeteoCurrentDTO: Decodable {
    let time: String
    let temperature: Decimal
    let apparentTemperature: Decimal
    let precipitationProbability: Decimal
    let humidity: Decimal
    let weatherCode: Int

    enum CodingKeys: String, CodingKey {
        case time
        case temperature = "temperature_2m"
        case apparentTemperature = "apparent_temperature"
        case precipitationProbability = "precipitation_probability"
        case humidity = "relative_humidity_2m"
        case weatherCode = "weather_code"
    }
}

private struct OpenMeteoHourlyDTO: Decodable {
    let time: [String]
    let temperature: [Decimal]
    let apparentTemperature: [Decimal]
    let precipitationProbability: [Decimal]
    let humidity: [Decimal]
    let weatherCode: [Int]

    enum CodingKeys: String, CodingKey {
        case time
        case temperature = "temperature_2m"
        case apparentTemperature = "apparent_temperature"
        case precipitationProbability = "precipitation_probability"
        case humidity = "relative_humidity_2m"
        case weatherCode = "weather_code"
    }
}
