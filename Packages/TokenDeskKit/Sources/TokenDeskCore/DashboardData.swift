import Foundation

/// Cache-first domain values consumed by the four-page application shell.
///
/// This value deliberately contains no transport DTOs, SQL rows, or credential material.
public struct DashboardDataSnapshot: Equatable, Sendable {
    /// Enabled non-secret account configurations.
    public let configurations: [ProviderAccountConfiguration]
    /// Cached plan windows, kept independent from token and money values.
    public let plans: [PlanWindow]
    /// Cached token observations.
    public let usage: [TokenUsageBucket]
    /// Cached monetary cost observations.
    public let costs: [CostSnapshot]
    /// Cached known balance observations; absence continues to mean unknown.
    public let balances: [BalanceSnapshot]
    /// Latest cached weather, when a location has previously synchronized.
    public let weather: WeatherSnapshot?

    /// Creates a credential-free cache snapshot.
    public init(
        configurations: [ProviderAccountConfiguration],
        plans: [PlanWindow],
        usage: [TokenUsageBucket],
        costs: [CostSnapshot],
        balances: [BalanceSnapshot],
        weather: WeatherSnapshot?
    ) {
        self.configurations = configurations
        self.plans = plans
        self.usage = usage
        self.costs = costs
        self.balances = balances
        self.weather = weather
    }
}

/// The result of refreshing independent Provider and weather sources.
public struct DashboardRefreshResult: Equatable, Sendable {
    /// Independently isolated Provider outcomes.
    public let providerReport: SyncReport
    /// Optional weather outcome because weather requires a resolved location.
    public let weatherResult: WeatherSyncResult?

    /// Creates one completed dashboard refresh result.
    public init(providerReport: SyncReport, weatherResult: WeatherSyncResult?) {
        self.providerReport = providerReport
        self.weatherResult = weatherResult
    }
}

/// Production data boundary used by feature stores.
public protocol DashboardDataProviding: Sendable {
    /// Reads local cache without waiting for network access.
    func loadCachedDashboardData() async throws -> DashboardDataSnapshot

    /// Refreshes every enabled Provider independently and optionally refreshes weather.
    func refreshDashboardData(location: WeatherLocation?) async -> DashboardRefreshResult
}
