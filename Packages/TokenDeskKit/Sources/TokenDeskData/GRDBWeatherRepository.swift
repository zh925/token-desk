import Foundation
import GRDB
import TokenDeskCore

/// Stable failures raised while decoding the weather cache boundary.
public enum WeatherRepositoryError: Error, Equatable, Sendable {
    case invalidStoredValue(field: String)
}

/// GRDB-backed single-slot weather cache used for cache-first and offline rendering.
public struct GRDBWeatherRepository: WeatherRepository, Sendable {
    private let writer: any DatabaseWriter

    /// Creates a weather cache over an already migrated database writer.
    public init(writer: any DatabaseWriter) {
        self.writer = writer
    }

    /// Atomically replaces the single current-location cache slot.
    public func saveWeather(_ snapshot: WeatherSnapshot) throws {
        let hourlyData = try Self.encoder.encode(snapshot.hourlyForecast)
        guard let hourlyJSON = String(data: hourlyData, encoding: .utf8) else {
            throw WeatherRepositoryError.invalidStoredValue(field: "hourlyForecast")
        }
        try writer.write { database in
            try database.execute(
                sql: """
                    INSERT INTO weather_cache (
                        cache_slot, location_key, city_name, latitude_decimal,
                        longitude_decimal, observed_at, temperature_decimal,
                        apparent_temperature_decimal, precipitation_probability_decimal,
                        humidity_percent_decimal, condition_code, hourly_payload_json,
                        source, updated_at
                    ) VALUES (1, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(cache_slot) DO UPDATE SET
                        location_key = excluded.location_key,
                        city_name = excluded.city_name,
                        latitude_decimal = excluded.latitude_decimal,
                        longitude_decimal = excluded.longitude_decimal,
                        observed_at = excluded.observed_at,
                        temperature_decimal = excluded.temperature_decimal,
                        apparent_temperature_decimal = excluded.apparent_temperature_decimal,
                        precipitation_probability_decimal = excluded.precipitation_probability_decimal,
                        humidity_percent_decimal = excluded.humidity_percent_decimal,
                        condition_code = excluded.condition_code,
                        hourly_payload_json = excluded.hourly_payload_json,
                        source = excluded.source,
                        updated_at = excluded.updated_at
                    """,
                arguments: [
                    snapshot.location.key,
                    snapshot.location.cityName,
                    Self.decimalString(snapshot.location.latitude),
                    Self.decimalString(snapshot.location.longitude),
                    Self.dateString(snapshot.observedAt),
                    Self.decimalString(snapshot.temperatureCelsius),
                    Self.decimalString(snapshot.apparentTemperatureCelsius),
                    Self.decimalString(snapshot.precipitationProbabilityPercent),
                    Self.decimalString(snapshot.humidityPercent),
                    String(snapshot.conditionCode),
                    hourlyJSON,
                    snapshot.metadata.source.identifier,
                    Self.dateString(snapshot.metadata.updatedAt),
                ]
            )
        }
    }

    /// Returns the matching cached city with freshness recalculated at the supplied instant.
    public func cachedWeather(
        for locationKey: String,
        now: Date,
        staleAfter: Duration
    ) throws -> WeatherSnapshot? {
        try writer.read { database in
            guard
                let row = try Row.fetchOne(
                    database,
                    sql: "SELECT * FROM weather_cache WHERE cache_slot = 1 AND location_key = ?",
                    arguments: [locationKey]
                )
            else {
                return nil
            }
            let updatedAt = try Self.date(row["updated_at"], field: "updated_at")
            let duration = staleAfter.components
            let staleSeconds =
                Double(duration.seconds)
                + Double(duration.attoseconds) / 1_000_000_000_000_000_000
            let source = try DataSource(
                kind: .official,
                identifier: row["source"] as String
            )
            let hourlyJSON: String = row["hourly_payload_json"]
            guard let hourlyData = hourlyJSON.data(using: .utf8) else {
                throw WeatherRepositoryError.invalidStoredValue(field: "hourly_payload_json")
            }
            let hourly = try Self.decoder.decode(
                [HourlyWeatherForecast].self,
                from: hourlyData
            )
            let location = try WeatherLocation(
                key: row["location_key"],
                cityName: row["city_name"],
                latitude: try Self.decimal(row["latitude_decimal"], field: "latitude_decimal"),
                longitude: try Self.decimal(
                    row["longitude_decimal"],
                    field: "longitude_decimal"
                )
            )
            return WeatherSnapshot(
                location: location,
                observedAt: try Self.date(row["observed_at"], field: "observed_at"),
                temperatureCelsius: try Self.decimal(
                    row["temperature_decimal"],
                    field: "temperature_decimal"
                ),
                apparentTemperatureCelsius: try Self.decimal(
                    row["apparent_temperature_decimal"],
                    field: "apparent_temperature_decimal"
                ),
                precipitationProbabilityPercent: try Self.decimal(
                    row["precipitation_probability_decimal"],
                    field: "precipitation_probability_decimal"
                ),
                humidityPercent: try Self.decimal(
                    row["humidity_percent_decimal"],
                    field: "humidity_percent_decimal"
                ),
                conditionCode: try Self.integer(row["condition_code"], field: "condition_code"),
                hourlyForecast: hourly,
                metadata: ObservationMetadata(
                    source: source,
                    updatedAt: updatedAt,
                    isStale: now.timeIntervalSince(updatedAt) > staleSeconds
                )
            )
        }
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private static let locale = Locale(identifier: "en_US_POSIX")

    private static func decimalString(_ value: Decimal) -> String {
        NSDecimalNumber(decimal: value).stringValue
    }

    private static func decimal(_ value: String?, field: String) throws -> Decimal {
        guard let value, let decimal = Decimal(string: value, locale: locale) else {
            throw WeatherRepositoryError.invalidStoredValue(field: field)
        }
        return decimal
    }

    private static func integer(_ value: String?, field: String) throws -> Int {
        guard let value, let integer = Int(value) else {
            throw WeatherRepositoryError.invalidStoredValue(field: field)
        }
        return integer
    }

    private static func dateString(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    private static func date(_ value: String?, field: String) throws -> Date {
        guard let value, let date = ISO8601DateFormatter().date(from: value) else {
            throw WeatherRepositoryError.invalidStoredValue(field: field)
        }
        return date
    }
}
