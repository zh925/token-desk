import Foundation

/// A user-approved location used for weather retrieval without retaining location history.
public struct WeatherLocation: Codable, Equatable, Hashable, Sendable {
    /// Stable local key for replacing the single weather cache slot.
    public let key: String
    /// Presentation-safe city label selected by the user or geocoder.
    public let cityName: String
    /// WGS84 latitude.
    public let latitude: Decimal
    /// WGS84 longitude.
    public let longitude: Decimal

    /// Creates a weather location with bounded coordinates and non-empty identifiers.
    public init(key: String, cityName: String, latitude: Decimal, longitude: Decimal) throws {
        let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCity = cityName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            throw DomainModelError.emptyIdentifier(field: "weatherLocationKey")
        }
        guard !trimmedCity.isEmpty else {
            throw DomainModelError.emptyIdentifier(field: "weatherCityName")
        }
        guard (-90...90).contains(latitude), (-180...180).contains(longitude) else {
            throw DomainModelError.invalidCoordinate
        }
        self.key = trimmedKey
        self.cityName = trimmedCity
        self.latitude = latitude
        self.longitude = longitude
    }
}

/// One hourly weather forecast point returned by an official weather source.
public struct HourlyWeatherForecast: Codable, Equatable, Hashable, Sendable {
    /// UTC beginning of the forecast hour.
    public let startsAt: Date
    /// Forecast air temperature in degrees Celsius.
    public let temperatureCelsius: Decimal
    /// Forecast perceived temperature in degrees Celsius.
    public let apparentTemperatureCelsius: Decimal
    /// Forecast precipitation probability percentage.
    public let precipitationProbabilityPercent: Decimal
    /// Forecast relative humidity percentage.
    public let humidityPercent: Decimal
    /// WMO weather interpretation code returned by the source.
    public let conditionCode: Int

    /// Creates a forecast point while preserving out-of-range upstream observations.
    public init(
        startsAt: Date,
        temperatureCelsius: Decimal,
        apparentTemperatureCelsius: Decimal,
        precipitationProbabilityPercent: Decimal,
        humidityPercent: Decimal,
        conditionCode: Int
    ) {
        self.startsAt = startsAt
        self.temperatureCelsius = temperatureCelsius
        self.apparentTemperatureCelsius = apparentTemperatureCelsius
        self.precipitationProbabilityPercent = precipitationProbabilityPercent
        self.humidityPercent = humidityPercent
        self.conditionCode = conditionCode
    }
}

/// Current weather and its next four hourly forecast points.
public struct WeatherSnapshot: Codable, Equatable, Hashable, Sendable {
    /// Approved location represented by this observation.
    public let location: WeatherLocation
    /// UTC instant associated with the current conditions.
    public let observedAt: Date
    /// Current air temperature in degrees Celsius.
    public let temperatureCelsius: Decimal
    /// Current perceived temperature in degrees Celsius.
    public let apparentTemperatureCelsius: Decimal
    /// Current precipitation probability percentage.
    public let precipitationProbabilityPercent: Decimal
    /// Current relative humidity percentage.
    public let humidityPercent: Decimal
    /// Current WMO weather interpretation code.
    public let conditionCode: Int
    /// Up to four hourly forecast points.
    public let hourlyForecast: [HourlyWeatherForecast]
    /// Official source, update time, and cache freshness.
    public let metadata: ObservationMetadata

    /// Creates a weather snapshot. The hourly collection is intentionally capped at four points.
    public init(
        location: WeatherLocation,
        observedAt: Date,
        temperatureCelsius: Decimal,
        apparentTemperatureCelsius: Decimal,
        precipitationProbabilityPercent: Decimal,
        humidityPercent: Decimal,
        conditionCode: Int,
        hourlyForecast: [HourlyWeatherForecast],
        metadata: ObservationMetadata
    ) {
        self.location = location
        self.observedAt = observedAt
        self.temperatureCelsius = temperatureCelsius
        self.apparentTemperatureCelsius = apparentTemperatureCelsius
        self.precipitationProbabilityPercent = precipitationProbabilityPercent
        self.humidityPercent = humidityPercent
        self.conditionCode = conditionCode
        self.hourlyForecast = Array(hourlyForecast.prefix(4))
        self.metadata = metadata
    }

    /// Returns the same observation with freshness recalculated by the cache policy.
    public func markingStale(_ isStale: Bool) -> WeatherSnapshot {
        WeatherSnapshot(
            location: location,
            observedAt: observedAt,
            temperatureCelsius: temperatureCelsius,
            apparentTemperatureCelsius: apparentTemperatureCelsius,
            precipitationProbabilityPercent: precipitationProbabilityPercent,
            humidityPercent: humidityPercent,
            conditionCode: conditionCode,
            hourlyForecast: hourlyForecast,
            metadata: ObservationMetadata(
                source: metadata.source,
                updatedAt: metadata.updatedAt,
                isStale: isStale
            )
        )
    }
}

/// Official weather transport boundary used by the weather sync coordinator.
public protocol WeatherService: Sendable {
    /// Fetches current conditions and the next four hourly points for one approved location.
    func fetchWeather(for location: WeatherLocation) async throws -> WeatherSnapshot
}

/// Single-slot cache boundary used to render weather before or after a network refresh.
public protocol WeatherRepository: Sendable {
    func saveWeather(_ snapshot: WeatherSnapshot) throws
    func cachedWeather(
        for locationKey: String,
        now: Date,
        staleAfter: Duration
    ) throws -> WeatherSnapshot?
}

/// Outcome of a weather refresh, including a cached fallback when the network is unavailable.
public enum WeatherSyncState: Equatable, Sendable {
    case refreshed
    case cached
    case unavailable
}

/// One cancellable weather refresh result.
public struct WeatherSyncResult: Equatable, Sendable {
    /// Whether this run refreshed, fell back to cache, or had no usable value.
    public let state: WeatherSyncState
    /// Fresh or cached weather suitable for rendering, when available.
    public let snapshot: WeatherSnapshot?
    /// Normalized network or Provider failure that caused fallback.
    public let failure: ConnectorError?

    /// Creates an explicit weather refresh outcome.
    public init(
        state: WeatherSyncState,
        snapshot: WeatherSnapshot?,
        failure: ConnectorError? = nil
    ) {
        self.state = state
        self.snapshot = snapshot
        self.failure = failure
    }
}

/// Coordinates a 15-minute weather refresh while preserving an independently readable cache.
public actor WeatherSyncCoordinator {
    /// Required elapsed time between automatic weather refreshes.
    public static let refreshInterval: Duration = .seconds(15 * 60)
    /// Age after which cached weather is visibly marked stale.
    public static let staleAfter: Duration = .seconds(30 * 60)

    private let service: any WeatherService
    private let repository: any WeatherRepository
    private let now: @Sendable () -> Date

    /// Creates a coordinator from transport, cache, and deterministic clock boundaries.
    public init(
        service: any WeatherService,
        repository: any WeatherRepository,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.service = service
        self.repository = repository
        self.now = now
    }

    /// Refreshes from the network and falls back to the matching cached city on normalized failures.
    public func sync(location: WeatherLocation) async throws -> WeatherSyncResult {
        do {
            let snapshot = try await service.fetchWeather(for: location)
            try Task.checkCancellation()
            try repository.saveWeather(snapshot)
            return WeatherSyncResult(state: .refreshed, snapshot: snapshot)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as ConnectorError {
            let cached = try repository.cachedWeather(
                for: location.key,
                now: now(),
                staleAfter: Self.staleAfter
            )
            return WeatherSyncResult(
                state: cached == nil ? .unavailable : .cached,
                snapshot: cached,
                failure: error
            )
        }
    }
}
