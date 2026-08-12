import Foundation

/// Failures raised while deriving dashboard aggregates from persisted observations.
public enum AggregationError: Error, Equatable, Sendable {
    case invalidBudget
    case tokenCountOverflow
}

/// A stable user choice for the single plan window rendered on the overview.
public struct PrimaryPlanSelection: Codable, Equatable, Hashable, Sendable {
    /// Configured Provider instance that owns the selected plan.
    public let providerID: ProviderID
    /// Local account whose logical account owns the selected plan.
    public let accountID: AccountID
    /// Stable Provider limit identifier that survives reset-window changes.
    public let limitIdentifier: String

    /// Creates a selection while rejecting an empty limit identifier.
    public init(providerID: ProviderID, accountID: AccountID, limitIdentifier: String) throws {
        let trimmedIdentifier = limitIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedIdentifier.isEmpty else {
            throw DomainModelError.emptyIdentifier(field: "limitIdentifier")
        }
        self.providerID = providerID
        self.accountID = accountID
        self.limitIdentifier = trimmedIdentifier
    }
}

/// Current plan windows together with the user's selected overview window.
public struct PlanAggregation: Equatable, Sendable {
    /// Current, de-duplicated plan windows in stable display order.
    public let windows: [PlanWindow]
    /// Window matching the explicit primary selection, or nil when unavailable.
    public let primary: PlanWindow?

    /// Creates an immutable plan aggregation snapshot.
    public init(windows: [PlanWindow], primary: PlanWindow?) {
        self.windows = windows
        self.primary = primary
    }
}

/// Resolves current plan observations without mixing plan values with token or monetary data.
public struct PlanAggregator: Sendable {
    /// Creates a stateless plan aggregator.
    public init() {}

    /// Keeps all current logical windows, de-duplicates duplicate account configurations, and
    /// resolves the explicitly selected primary plan. Official and fresher observations win.
    public func aggregate(
        windows: [PlanWindow],
        accounts: [AccountReference],
        primarySelection: PrimaryPlanSelection?,
        at now: Date
    ) -> PlanAggregation {
        let accountKeys = Dictionary(
            uniqueKeysWithValues: accounts.map { ($0.id, $0.deduplicationKey) }
        )
        var resolved: [PlanIdentity: PlanWindow] = [:]

        for window in windows where window.resetsAt > now {
            guard let accountKey = accountKeys[window.accountID] else { continue }
            let identity = PlanIdentity(
                account: accountKey,
                limitIdentifier: window.limitIdentifier,
                resetsAt: window.resetsAt
            )
            if let current = resolved[identity], !Self.prefers(window, over: current) {
                continue
            }
            resolved[identity] = window
        }

        let ordered = resolved.values.sorted {
            if $0.resetsAt != $1.resetsAt { return $0.resetsAt < $1.resetsAt }
            if $0.providerID != $1.providerID {
                return $0.providerID.rawValue < $1.providerID.rawValue
            }
            if $0.accountID != $1.accountID {
                return $0.accountID.rawValue < $1.accountID.rawValue
            }
            return $0.limitIdentifier < $1.limitIdentifier
        }
        let primary: PlanWindow? = primarySelection.flatMap { selection in
            guard let selectedAccount = accountKeys[selection.accountID] else { return nil }
            return ordered.first {
                $0.providerID == selection.providerID
                    && accountKeys[$0.accountID] == selectedAccount
                    && $0.limitIdentifier == selection.limitIdentifier
            }
        }
        return PlanAggregation(windows: ordered, primary: primary)
    }

    private struct PlanIdentity: Hashable {
        let account: AccountDeduplicationKey
        let limitIdentifier: String
        let resetsAt: Date
    }

    private static func prefers(_ candidate: PlanWindow, over current: PlanWindow) -> Bool {
        let candidateRank = sourceRank(candidate.metadata.source.kind)
        let currentRank = sourceRank(current.metadata.source.kind)
        if candidateRank != currentRank { return candidateRank > currentRank }
        if candidate.metadata.updatedAt != current.metadata.updatedAt {
            return candidate.metadata.updatedAt > current.metadata.updatedAt
        }
        return candidate.metadata.source.identifier < current.metadata.source.identifier
    }
}

/// Calendar ranges supported by the token dashboard.
public enum TokenAggregationRange: String, Codable, CaseIterable, Sendable {
    case day
    case week
    case month

    fileprivate var granularity: UsageGranularity {
        switch self {
        case .day: .day
        case .week: .week
        case .month: .month
        }
    }

    fileprivate var timelineGranularity: UsageGranularity {
        switch self {
        case .day: .hour
        case .week, .month: .day
        }
    }
}

/// Exact token totals for one model or one chart bucket.
public struct TokenAggregate: Equatable, Sendable {
    /// Exact non-cached input token count.
    public let input: TokenCount
    /// Exact generated output token count.
    public let output: TokenCount
    /// Exact cache-read input token count.
    public let cachedInput: TokenCount
    /// Exact cache-write token count.
    public let cacheWrite: TokenCount

    /// Creates an exact four-category token aggregate.
    public init(
        input: TokenCount,
        output: TokenCount,
        cachedInput: TokenCount,
        cacheWrite: TokenCount
    ) {
        self.input = input
        self.output = output
        self.cachedInput = cachedInput
        self.cacheWrite = cacheWrite
    }

    /// Additive identity used for empty aggregation scopes.
    public static let zero = TokenAggregate(
        input: .zero,
        output: .zero,
        cachedInput: .zero,
        cacheWrite: .zero
    )

    fileprivate func adding(_ breakdown: TokenBreakdown) throws -> TokenAggregate {
        do {
            return TokenAggregate(
                input: try input.adding(breakdown.input),
                output: try output.adding(breakdown.output),
                cachedInput: try cachedInput.adding(breakdown.cachedInput),
                cacheWrite: try cacheWrite.adding(breakdown.cacheWrite)
            )
        } catch DomainModelError.tokenCountOverflow {
            throw AggregationError.tokenCountOverflow
        }
    }
}

/// Model-level totals sorted by descending total usage and then model name.
public struct ModelTokenAggregate: Equatable, Sendable {
    /// Provider model name.
    public let model: String
    /// Exact usage attributed to the model.
    public let tokens: TokenAggregate

    /// Creates one model-level total.
    public init(model: String, tokens: TokenAggregate) {
        self.model = model
        self.tokens = tokens
    }
}

/// One end-exclusive chart bucket in the account's requested time zone.
public struct TokenTimelineAggregate: Equatable, Sendable {
    /// End-exclusive chart interval in the requested time zone.
    public let period: UsagePeriod
    /// Exact usage attributed to the interval.
    public let tokens: TokenAggregate

    /// Creates one chart bucket.
    public init(period: UsagePeriod, tokens: TokenAggregate) {
        self.period = period
        self.tokens = tokens
    }
}

/// A monetary total that remains isolated in its original currency.
public struct CurrencyAggregate: Equatable, Sendable {
    /// Exact unrounded total in one currency.
    public let money: Money
    /// Whether any selected component used estimated provenance.
    public let containsEstimatedValues: Bool

    /// Creates one currency-isolated monetary total.
    public init(money: Money, containsEstimatedValues: Bool) {
        self.money = money
        self.containsEstimatedValues = containsEstimatedValues
    }
}

/// Exact month-to-budget result in one currency.
public struct BudgetAggregate: Equatable, Sendable {
    /// Current calendar-month spend in the budget currency.
    public let spent: Money
    /// Configured positive monthly budget.
    public let budget: Money
    /// Exact, unrounded spend-to-budget percentage.
    public let usedPercent: Decimal

    /// Creates one exact monthly budget comparison.
    public init(spent: Money, budget: Money, usedPercent: Decimal) {
        self.spent = spent
        self.budget = budget
        self.usedPercent = usedPercent
    }
}

/// Provider-scoped token dashboard values computed as one immutable snapshot.
public struct TokenAggregation: Equatable, Sendable {
    /// Provider selected by the dashboard.
    public let providerID: ProviderID
    /// Requested day, week, or month boundary.
    public let period: UsagePeriod
    /// Exact totals for the requested period.
    public let tokens: TokenAggregate
    /// Per-model totals sorted by descending usage.
    public let byModel: [ModelTokenAggregate]
    /// Input/output chart buckets derived in the requested time zone.
    public let timeline: [TokenTimelineAggregate]
    /// Cache-read share of input plus cached input, or nil when both are zero.
    public let cacheHitPercent: Decimal?
    /// Requested-period costs, kept separate by currency.
    public let costs: [CurrencyAggregate]
    /// Latest known balances, kept separate by currency.
    public let balances: [CurrencyAggregate]
    /// Current month comparison for the configured budget currency.
    public let monthlyBudget: BudgetAggregate?

    /// Creates one immutable dashboard aggregation snapshot.
    public init(
        providerID: ProviderID,
        period: UsagePeriod,
        tokens: TokenAggregate,
        byModel: [ModelTokenAggregate],
        timeline: [TokenTimelineAggregate],
        cacheHitPercent: Decimal?,
        costs: [CurrencyAggregate],
        balances: [CurrencyAggregate],
        monthlyBudget: BudgetAggregate?
    ) {
        self.providerID = providerID
        self.period = period
        self.tokens = tokens
        self.byModel = byModel
        self.timeline = timeline
        self.cacheHitPercent = cacheHitPercent
        self.costs = costs
        self.balances = balances
        self.monthlyBudget = monthlyBudget
    }
}

/// Aggregates provider usage, costs, balances, and budget comparison while preserving their units.
public struct TokenAggregator: Sendable {
    /// Creates a stateless token aggregator.
    public init() {}

    /// Builds all provider dashboard values from one consistent set of observations.
    public func aggregate(
        providerID: ProviderID,
        accounts: [AccountReference],
        usage: [TokenUsageBucket],
        costs: [CostSnapshot],
        balances: [BalanceSnapshot],
        range: TokenAggregationRange,
        at now: Date,
        calendar: Calendar = Calendar(identifier: .gregorian),
        timeZone: TimeZone,
        monthlyBudget: Money? = nil
    ) throws -> TokenAggregation {
        if let monthlyBudget, monthlyBudget.amount <= 0 {
            throw AggregationError.invalidBudget
        }
        let period = try UsagePeriod.containing(
            now,
            granularity: range.granularity,
            calendar: calendar,
            timeZone: timeZone
        )
        let month = try UsagePeriod.containing(
            now,
            granularity: .month,
            calendar: calendar,
            timeZone: timeZone
        )
        let accountKeys = Dictionary(
            uniqueKeysWithValues: accounts.lazy
                .filter { $0.providerID == providerID }
                .map { ($0.id, $0.deduplicationKey) }
        )
        let selectedUsage = Self.resolveUsage(
            usage,
            providerID: providerID,
            accountKeys: accountKeys,
            in: period.interval
        )

        var total = TokenAggregate.zero
        var modelTotals: [String: TokenAggregate] = [:]
        var timelineTotals: [UsagePeriod: TokenAggregate] = [:]
        for bucket in selectedUsage {
            total = try total.adding(bucket.tokens)
            modelTotals[bucket.model] = try (modelTotals[bucket.model] ?? .zero).adding(
                bucket.tokens
            )
            let timelinePeriod = try UsagePeriod.containing(
                bucket.period.interval.start,
                granularity: range.timelineGranularity,
                calendar: calendar,
                timeZone: timeZone
            )
            timelineTotals[timelinePeriod] = try (timelineTotals[timelinePeriod] ?? .zero).adding(
                bucket.tokens
            )
        }

        let byModel = try modelTotals.map { model, tokens in
            (ModelTokenAggregate(model: model, tokens: tokens), try Self.total(tokens))
        }.sorted {
            if $0.1 != $1.1 { return $0.1 > $1.1 }
            return $0.0.model < $1.0.model
        }.map(\.0)
        let timeline = timelineTotals.map(TokenTimelineAggregate.init).sorted {
            $0.period.interval.start < $1.period.interval.start
        }
        let cacheDenominator = Decimal(total.input.rawValue) + Decimal(total.cachedInput.rawValue)
        let cacheHitPercent =
            cacheDenominator == 0
            ? nil : Decimal(total.cachedInput.rawValue) * 100 / cacheDenominator

        let selectedCosts = Self.resolveCosts(
            costs,
            providerID: providerID,
            accountKeys: accountKeys,
            in: period.interval
        )
        let rangeCosts = try Self.sumCosts(selectedCosts)
        let selectedMonthlyCosts = Self.resolveCosts(
            costs,
            providerID: providerID,
            accountKeys: accountKeys,
            in: month.interval
        )
        let monthlyCosts = try Self.sumCosts(selectedMonthlyCosts)
        let budgetAggregate = monthlyBudget.flatMap { budget in
            guard let spent = monthlyCosts.first(where: { $0.money.currency == budget.currency })
            else {
                return BudgetAggregate(
                    spent: Money(amount: 0, currency: budget.currency),
                    budget: budget,
                    usedPercent: 0
                )
            }
            return BudgetAggregate(
                spent: spent.money,
                budget: budget,
                usedPercent: spent.money.amount * 100 / budget.amount
            )
        }

        return TokenAggregation(
            providerID: providerID,
            period: period,
            tokens: total,
            byModel: byModel,
            timeline: timeline,
            cacheHitPercent: cacheHitPercent,
            costs: rangeCosts,
            balances: try Self.sumLatestBalances(
                balances,
                providerID: providerID,
                accountKeys: accountKeys
            ),
            monthlyBudget: budgetAggregate
        )
    }

    private struct UsageIdentity: Hashable {
        let account: AccountDeduplicationKey
        let projectReference: String?
        let workspaceReference: String?
        let model: String
        let interval: DateInterval
    }

    private struct CostIdentity: Hashable {
        let account: AccountDeduplicationKey
        let projectReference: String?
        let workspaceReference: String?
        let interval: DateInterval
        let currency: CurrencyCode
    }

    private struct BalanceIdentity: Hashable {
        let account: AccountDeduplicationKey
        let currency: CurrencyCode
    }

    private static func resolveUsage(
        _ usage: [TokenUsageBucket],
        providerID: ProviderID,
        accountKeys: [AccountID: AccountDeduplicationKey],
        in interval: DateInterval
    ) -> [TokenUsageBucket] {
        var resolved: [UsageIdentity: TokenUsageBucket] = [:]
        for bucket in usage {
            guard bucket.providerID == providerID,
                let account = accountKeys[bucket.accountID],
                interval.contains(bucket.period.interval)
            else { continue }
            let identity = UsageIdentity(
                account: account,
                projectReference: bucket.projectReference,
                workspaceReference: bucket.workspaceReference,
                model: bucket.model,
                interval: bucket.period.interval
            )
            if let current = resolved[identity], !prefers(bucket.metadata, over: current.metadata) {
                continue
            }
            resolved[identity] = bucket
        }
        return Array(resolved.values)
    }

    private static func resolveCosts(
        _ costs: [CostSnapshot],
        providerID: ProviderID,
        accountKeys: [AccountID: AccountDeduplicationKey],
        in interval: DateInterval
    ) -> [CostSnapshot] {
        var resolved: [CostIdentity: CostSnapshot] = [:]
        for cost in costs {
            guard cost.providerID == providerID,
                let account = accountKeys[cost.accountID],
                interval.contains(cost.period.interval)
            else { continue }
            let identity = CostIdentity(
                account: account,
                projectReference: cost.projectReference,
                workspaceReference: cost.workspaceReference,
                interval: cost.period.interval,
                currency: cost.money.currency
            )
            if let current = resolved[identity], !prefers(cost.metadata, over: current.metadata) {
                continue
            }
            resolved[identity] = cost
        }
        return Array(resolved.values)
    }

    private static func sumCosts(_ costs: [CostSnapshot]) throws -> [CurrencyAggregate] {
        var totals: [CurrencyCode: Money] = [:]
        var estimated: Set<CurrencyCode> = []
        for cost in costs {
            let currency = cost.money.currency
            totals[currency] = try (totals[currency] ?? Money(amount: 0, currency: currency))
                .adding(cost.money)
            if cost.isEstimated { estimated.insert(currency) }
        }
        return totals.map { currency, money in
            CurrencyAggregate(money: money, containsEstimatedValues: estimated.contains(currency))
        }.sorted { $0.money.currency.rawValue < $1.money.currency.rawValue }
    }

    private static func sumLatestBalances(
        _ balances: [BalanceSnapshot],
        providerID: ProviderID,
        accountKeys: [AccountID: AccountDeduplicationKey]
    ) throws -> [CurrencyAggregate] {
        var latest: [BalanceIdentity: BalanceSnapshot] = [:]
        for balance in balances {
            guard balance.providerID == providerID, let account = accountKeys[balance.accountID]
            else { continue }
            let identity = BalanceIdentity(account: account, currency: balance.available.currency)
            if let current = latest[identity],
                !prefers(balance.metadata, over: current.metadata)
            {
                continue
            }
            latest[identity] = balance
        }
        var totals: [CurrencyCode: Money] = [:]
        var estimated: Set<CurrencyCode> = []
        for balance in latest.values {
            let currency = balance.available.currency
            totals[currency] = try (totals[currency] ?? Money(amount: 0, currency: currency))
                .adding(balance.available)
            if balance.metadata.source.isEstimated { estimated.insert(currency) }
        }
        return totals.map { currency, money in
            CurrencyAggregate(money: money, containsEstimatedValues: estimated.contains(currency))
        }.sorted { $0.money.currency.rawValue < $1.money.currency.rawValue }
    }

    private static func total(_ tokens: TokenAggregate) throws -> Int64 {
        let first = try tokens.input.adding(tokens.output)
        let second = try first.adding(tokens.cachedInput)
        return try second.adding(tokens.cacheWrite).rawValue
    }
}

private func sourceRank(_ kind: DataSourceKind) -> Int {
    switch kind {
    case .official: 4
    case .locallyAggregated: 3
    case .estimated: 2
    case .demonstration: 1
    }
}

private func prefers(_ candidate: ObservationMetadata, over current: ObservationMetadata) -> Bool {
    let candidateRank = sourceRank(candidate.source.kind)
    let currentRank = sourceRank(current.source.kind)
    if candidateRank != currentRank { return candidateRank > currentRank }
    if candidate.updatedAt != current.updatedAt { return candidate.updatedAt > current.updatedAt }
    return candidate.source.identifier < current.source.identifier
}

private extension DateInterval {
    func contains(_ other: DateInterval) -> Bool {
        other.start >= start && other.end <= end
    }
}
