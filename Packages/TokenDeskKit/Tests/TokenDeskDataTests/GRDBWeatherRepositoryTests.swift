import Foundation
import GRDB
import Testing
import TokenDeskCore
@testable import TokenDeskData

@Test
func weatherCacheRoundTripsAndRecalculatesFreshness() throws {
    let database = try DatabaseQueue(configuration: TokenDeskDatabase.configuration)
    try TokenDeskDatabaseMigrator.migrate(database)
    let repository = GRDBWeatherRepository(writer: database)
    let updatedAt = Date(timeIntervalSince1970: 1_768_521_600)
    let location = try WeatherLocation(
        key: "shanghai",
        cityName: "Shanghai",
        latitude: Decimal(string: "31.23")!,
        longitude: Decimal(string: "121.47")!
    )
    let hour = HourlyWeatherForecast(
        startsAt: updatedAt.addingTimeInterval(3_600),
        temperatureCelsius: 9,
        apparentTemperatureCelsius: 8,
        precipitationProbabilityPercent: 10,
        humidityPercent: 65,
        conditionCode: 2
    )
    let snapshot = WeatherSnapshot(
        location: location,
        observedAt: updatedAt,
        temperatureCelsius: 8,
        apparentTemperatureCelsius: 7,
        precipitationProbabilityPercent: 15,
        humidityPercent: 68,
        conditionCode: 3,
        hourlyForecast: [hour],
        metadata: ObservationMetadata(
            source: try DataSource(kind: .official, identifier: "open_meteo_forecast_api"),
            updatedAt: updatedAt,
            isStale: false
        )
    )

    try repository.saveWeather(snapshot)

    let fresh = try repository.cachedWeather(
        for: location.key,
        now: updatedAt.addingTimeInterval(899),
        staleAfter: .seconds(900)
    )
    let stale = try repository.cachedWeather(
        for: location.key,
        now: updatedAt.addingTimeInterval(901),
        staleAfter: .seconds(900)
    )
    #expect(fresh?.location == location)
    #expect(fresh?.hourlyForecast == [hour])
    #expect(fresh?.metadata.isStale == false)
    #expect(stale?.metadata.isStale == true)
    #expect(
        try repository.cachedWeather(
            for: "another-city",
            now: updatedAt,
            staleAfter: .seconds(900)
        ) == nil
    )
}
