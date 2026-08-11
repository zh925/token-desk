import Foundation
import Testing
@testable import TokenDeskCore

@Test
func weatherSyncPreservesCachedDataOnOfflineFailureAndCancellation() async throws {
    let location = try WeatherLocation(
        key: "city",
        cityName: "City",
        latitude: 0,
        longitude: 0
    )
    let snapshot = WeatherSnapshot(
        location: location,
        observedAt: .distantPast,
        temperatureCelsius: 1,
        apparentTemperatureCelsius: 0,
        precipitationProbabilityPercent: 0,
        humidityPercent: 50,
        conditionCode: 1,
        hourlyForecast: [],
        metadata: ObservationMetadata(
            source: try DataSource(kind: .official, identifier: "weather"),
            updatedAt: .distantPast,
            isStale: false
        )
    )
    let repository = WeatherMemoryRepository(snapshot: snapshot)
    let coordinator = WeatherSyncCoordinator(
        service: FailingWeatherService(error: .network),
        repository: repository,
        now: { .distantFuture }
    )

    let result = try await coordinator.sync(location: location)

    #expect(result.state == .cached)
    #expect(result.failure == .network)
    #expect(result.snapshot?.metadata.isStale == true)

    let cancelled = WeatherSyncCoordinator(
        service: FailingWeatherService(error: .cancelled),
        repository: repository
    )
    let task = Task { try await cancelled.sync(location: location) }
    task.cancel()
    await #expect(throws: CancellationError.self) {
        try await task.value
    }
}

private struct FailingWeatherService: WeatherService {
    let error: ConnectorError

    func fetchWeather(for location: WeatherLocation) async throws -> WeatherSnapshot {
        try Task.checkCancellation()
        if error == .cancelled { throw CancellationError() }
        throw error
    }
}

private final class WeatherMemoryRepository: WeatherRepository, @unchecked Sendable {
    private let snapshot: WeatherSnapshot

    init(snapshot: WeatherSnapshot) {
        self.snapshot = snapshot
    }

    func saveWeather(_ snapshot: WeatherSnapshot) throws {}

    func cachedWeather(
        for locationKey: String,
        now: Date,
        staleAfter: Duration
    ) throws -> WeatherSnapshot? {
        guard snapshot.location.key == locationKey else { return nil }
        return snapshot.markingStale(true)
    }
}
