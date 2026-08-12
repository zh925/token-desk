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

/// Independent refresh lanes used to avoid polling slow-changing data at the Token cadence.
public struct DashboardRefreshScope: OptionSet, Equatable, Sendable {
    /// Bit field backing the selected refresh lanes.
    public let rawValue: UInt8

    /// Creates a scope from its stable bit field.
    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    /// Plan windows and Token usage, refreshed once per minute while the app is active.
    public static let usage = Self(rawValue: 1 << 0)
    /// Costs and balances, refreshed every five minutes while the app is active.
    public static let money = Self(rawValue: 1 << 1)
    /// Weather, refreshed at the user-configured cadence (15 minutes by default).
    public static let weather = Self(rawValue: 1 << 2)
    /// Every Provider-backed lane, excluding weather.
    public static let providers: Self = [.usage, .money]
    /// Every supported refresh lane.
    public static let all: Self = [.providers, .weather]

    /// Connector capabilities due for this refresh without conflating their data domains.
    public var providerCapabilities: Set<ProviderCapability> {
        var capabilities: Set<ProviderCapability> = []
        if contains(.usage) {
            capabilities.formUnion([.plan, .usage, .localEstimate])
        }
        if contains(.money) {
            capabilities.formUnion([.cost, .balance])
        }
        return capabilities
    }
}

/// Production data boundary used by feature stores.
public protocol DashboardDataProviding: Sendable {
    /// Reads local cache without waiting for network access.
    func loadCachedDashboardData() async throws -> DashboardDataSnapshot

    /// Refreshes only the due lanes, keeping high- and low-frequency sources independent.
    func refreshDashboardData(
        location: WeatherLocation?,
        scope: DashboardRefreshScope
    ) async -> DashboardRefreshResult
}
