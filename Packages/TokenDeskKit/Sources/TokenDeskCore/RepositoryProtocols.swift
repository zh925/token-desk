import Foundation

/// The database-facing contract used by synchronization without exposing GRDB records to Core.
public protocol ProviderSyncRepository: Sendable {
    func savePlans(_ plans: [PlanWindow]) throws
    func saveUsage(_ usage: [TokenUsageBucket]) throws
    func saveCosts(_ costs: [CostSnapshot]) throws
    func saveBalances(_ balances: [BalanceSnapshot]) throws
}

/// Cache-first usage and cost reads consumed by features before a network refresh completes.
public protocol UsageRepository: ProviderSyncRepository {
    func cachedUsage(
        for account: AccountReference,
        in interval: DateInterval,
        granularity: UsageGranularity
    ) throws -> [TokenUsageBucket]

    func cachedCosts(
        for account: AccountReference,
        in interval: DateInterval
    ) throws -> [CostSnapshot]

    /// Aggregates expired fine-grained usage before deleting it in one transaction.
    func performRetention(now: Date) throws -> RetentionReport
}

/// Counts produced by one atomic retention pass.
public struct RetentionReport: Equatable, Sendable {
    /// Minute rows consumed into hourly buckets.
    public let minuteRowsAggregated: Int
    /// Hour rows consumed into daily buckets.
    public let hourRowsAggregated: Int
    /// Daily rows removed after exceeding the long-term window.
    public let dayRowsDeleted: Int

    /// Creates the counters returned by one completed retention transaction.
    public init(
        minuteRowsAggregated: Int,
        hourRowsAggregated: Int,
        dayRowsDeleted: Int
    ) {
        self.minuteRowsAggregated = minuteRowsAggregated
        self.hourRowsAggregated = hourRowsAggregated
        self.dayRowsDeleted = dayRowsDeleted
    }
}
