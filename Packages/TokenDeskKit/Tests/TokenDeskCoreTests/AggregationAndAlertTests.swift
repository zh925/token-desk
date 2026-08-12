import Foundation
import Testing
import TokenDeskCore

@Test
func planAggregatorKeepsMultipleWindowsAndResolvesSelectedLogicalAccount() throws {
    let provider = try ProviderID(rawValue: "codex-primary")
    let first = try account(
        id: "local-first",
        provider: provider,
        remote: "remote-account",
        scope: .personal
    )
    let duplicate = try account(
        id: "local-duplicate",
        provider: provider,
        remote: "remote-account",
        scope: .personal
    )
    let now = Date(timeIntervalSince1970: 1_786_521_600)
    let reset = now.addingTimeInterval(5 * 60 * 60)
    let official = try plan(
        provider: provider,
        account: first.id,
        limit: "five-hour",
        percent: 42,
        reset: reset,
        source: .official,
        updatedAt: now
    )
    let duplicateEstimate = try plan(
        provider: provider,
        account: duplicate.id,
        limit: "five-hour",
        percent: 99,
        reset: reset,
        source: .estimated,
        confidence: 0.5,
        updatedAt: now.addingTimeInterval(60)
    )
    let weeklyEstimate = try plan(
        provider: provider,
        account: first.id,
        limit: "weekly",
        percent: 11,
        reset: now.addingTimeInterval(7 * 24 * 60 * 60),
        source: .estimated,
        confidence: 0.8,
        updatedAt: now
    )
    let expired = try plan(
        provider: provider,
        account: first.id,
        limit: "expired",
        percent: 100,
        reset: now,
        source: .official,
        updatedAt: now
    )
    let selection = try PrimaryPlanSelection(
        providerID: provider,
        accountID: duplicate.id,
        limitIdentifier: "five-hour"
    )

    let result = PlanAggregator().aggregate(
        windows: [duplicateEstimate, expired, weeklyEstimate, official],
        accounts: [first, duplicate],
        primarySelection: selection,
        at: now
    )

    #expect(result.windows.count == 2)
    #expect(result.primary == official)
    #expect(result.windows.contains(weeklyEstimate))
    #expect(result.windows.first { $0.limitIdentifier == "weekly" }?.confidence?.rawValue == 0.8)
}

@Test
func tokenAggregatorUsesCalendarBoundariesAndDeduplicatesLogicalAccounts() throws {
    let provider = try ProviderID(rawValue: "openai-primary")
    let first = try account(
        id: "local-first",
        provider: provider,
        remote: "remote-team",
        scope: .organization
    )
    let duplicate = try account(
        id: "local-duplicate",
        provider: provider,
        remote: "remote-team",
        scope: .organization
    )
    let timeZone = try #require(TimeZone(identifier: "Asia/Shanghai"))
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    let now = try #require(
        calendar.date(from: DateComponents(year: 2026, month: 8, day: 12, hour: 12))
    )
    let firstHour = try #require(
        calendar.date(from: DateComponents(year: 2026, month: 8, day: 12, hour: 1))
    )
    let secondHour = try #require(calendar.date(byAdding: .hour, value: 1, to: firstHour))
    let beforeDay = try #require(calendar.date(byAdding: .hour, value: -2, to: firstHour))
    let official = try usageBucket(
        provider: provider,
        account: first.id,
        model: "gpt-a",
        start: firstHour,
        granularity: .hour,
        input: 20,
        output: 5,
        cached: 10,
        cacheWrite: 2,
        source: .official
    )
    let duplicateEstimate = try usageBucket(
        provider: provider,
        account: duplicate.id,
        model: "gpt-a",
        start: firstHour,
        granularity: .hour,
        input: 9_999,
        output: 0,
        source: .estimated
    )
    let secondModel = try usageBucket(
        provider: provider,
        account: first.id,
        model: "gpt-b",
        start: secondHour,
        granularity: .hour,
        input: 10,
        output: 15,
        source: .official
    )
    let outside = try usageBucket(
        provider: provider,
        account: first.id,
        model: "outside",
        start: beforeDay,
        granularity: .hour,
        input: 100,
        output: 100,
        source: .official
    )

    let result = try TokenAggregator().aggregate(
        providerID: provider,
        accounts: [first, duplicate],
        usage: [official, duplicateEstimate, secondModel, outside],
        costs: [],
        balances: [],
        range: .day,
        at: now,
        calendar: calendar,
        timeZone: timeZone
    )

    #expect(calendar.component(.hour, from: result.period.interval.start) == 0)
    #expect(result.tokens.input.rawValue == 30)
    #expect(result.tokens.output.rawValue == 20)
    #expect(result.tokens.cachedInput.rawValue == 10)
    #expect(result.tokens.cacheWrite.rawValue == 2)
    #expect(result.cacheHitPercent == 25)
    #expect(result.byModel.map(\.model) == ["gpt-a", "gpt-b"])
    #expect(result.timeline.count == 2)
}

@Test(arguments: TokenAggregationRange.allCases)
func tokenAggregatorBuildsExactDayWeekAndMonthPeriods(range: TokenAggregationRange) throws {
    let provider = try ProviderID(rawValue: "openai-primary")
    let configuredAccount = try account(
        id: "account",
        provider: provider,
        remote: nil,
        scope: .personal
    )
    let timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    let now = try #require(
        calendar.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 12))
    )

    let result = try TokenAggregator().aggregate(
        providerID: provider,
        accounts: [configuredAccount],
        usage: [],
        costs: [],
        balances: [],
        range: range,
        at: now,
        calendar: calendar,
        timeZone: timeZone
    )

    #expect(result.period.timeZoneIdentifier == "America/Los_Angeles")
    if range == .day {
        #expect(result.period.interval.duration == 23 * 60 * 60)
    }
    #expect(result.period.interval.contains(now))
    #expect(now < result.period.interval.end)
}

@Test
func tokenAggregatorKeepsCurrenciesSeparateAndUsesExactMonthlyBudgetPrecision() throws {
    let provider = try ProviderID(rawValue: "deepseek-primary")
    let configuredAccount = try account(
        id: "account",
        provider: provider,
        remote: nil,
        scope: .personal
    )
    let timeZone = try #require(TimeZone(identifier: "UTC"))
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    let now = try #require(
        calendar.date(from: DateComponents(year: 2026, month: 8, day: 12, hour: 12))
    )
    let today = try UsagePeriod.containing(
        now,
        granularity: .day,
        calendar: calendar,
        timeZone: timeZone
    )
    let monthStart = try #require(
        calendar.date(from: DateComponents(year: 2026, month: 8, day: 1))
    )
    let earlierDay = try UsagePeriod.containing(
        monthStart,
        granularity: .day,
        calendar: calendar,
        timeZone: timeZone
    )
    let usd = try CurrencyCode(rawValue: "USD")
    let cny = try CurrencyCode(rawValue: "CNY")
    let officialSource = try DataSource(kind: .official, identifier: "official_cost")
    let estimateSource = try DataSource(kind: .estimated, identifier: "catalog")
    let costs = [
        CostSnapshot(
            providerID: provider,
            accountID: configuredAccount.id,
            period: today,
            money: Money(amount: 0.1, currency: usd),
            metadata: metadata(source: officialSource, updatedAt: now)
        ),
        CostSnapshot(
            providerID: provider,
            accountID: configuredAccount.id,
            period: today,
            money: Money(amount: 999, currency: usd),
            metadata: metadata(source: estimateSource, updatedAt: now.addingTimeInterval(60))
        ),
        CostSnapshot(
            providerID: provider,
            accountID: configuredAccount.id,
            period: today,
            money: Money(amount: 0.2, currency: cny),
            metadata: metadata(source: officialSource, updatedAt: now)
        ),
        CostSnapshot(
            providerID: provider,
            accountID: configuredAccount.id,
            period: earlierDay,
            money: Money(amount: 0.2, currency: usd),
            metadata: metadata(source: officialSource, updatedAt: now)
        ),
    ]
    let balances = [
        BalanceSnapshot(
            providerID: provider,
            accountID: configuredAccount.id,
            available: Money(amount: 5, currency: usd),
            metadata: metadata(source: officialSource, updatedAt: now.addingTimeInterval(-60))
        ),
        BalanceSnapshot(
            providerID: provider,
            accountID: configuredAccount.id,
            available: Money(amount: 4.5, currency: usd),
            metadata: metadata(source: officialSource, updatedAt: now)
        ),
        BalanceSnapshot(
            providerID: provider,
            accountID: configuredAccount.id,
            available: Money(amount: 20, currency: cny),
            metadata: metadata(source: officialSource, updatedAt: now)
        ),
    ]

    let result = try TokenAggregator().aggregate(
        providerID: provider,
        accounts: [configuredAccount],
        usage: [],
        costs: costs,
        balances: balances,
        range: .day,
        at: now,
        calendar: calendar,
        timeZone: timeZone,
        monthlyBudget: Money(amount: 0.9, currency: usd)
    )

    #expect(result.costs.map(\.money.currency.rawValue) == ["CNY", "USD"])
    #expect(result.costs.first { $0.money.currency == usd }?.money.amount == 0.1)
    #expect(result.costs.first { $0.money.currency == cny }?.money.amount == 0.2)
    #expect(result.balances.first { $0.money.currency == usd }?.money.amount == 4.5)
    #expect(result.balances.first { $0.money.currency == cny }?.money.amount == 20)
    #expect(result.monthlyBudget?.spent.amount == 0.3)
    let expectedBudgetPercent =
        try #require(Decimal(string: "0.3")) * 100 / #require(Decimal(string: "0.9"))
    #expect(result.monthlyBudget?.usedPercent == expectedBudgetPercent)
}

@Test
func alertEvaluatorAppliesAllFourThresholdDirections() throws {
    let provider = try ProviderID(rawValue: "provider")
    let accountID = try AccountID(rawValue: "account")
    let usd = try CurrencyCode(rawValue: "USD")
    let now = Date(timeIntervalSince1970: 1_786_521_600)
    let source = try DataSource(kind: .official, identifier: "fixture")
    let cases: [(AlertKind, Decimal, Decimal, CurrencyCode?)] = [
        (.planPercent, 80, 80, nil),
        (.budgetPercent, 95, 100, nil),
        (.balanceFloor, 10, 9.99, usd),
        (.syncFailure, 1_800, 1_800, nil),
    ]

    for (kind, threshold, value, currency) in cases {
        let rule = try AlertRule(
            id: kind.rawValue,
            providerID: provider,
            accountID: accountID,
            kind: kind,
            threshold: threshold,
            currency: currency,
            cooldownSeconds: 3_600
        )
        let observation = try AlertObservation(
            providerID: provider,
            accountID: accountID,
            kind: kind,
            value: value,
            currency: currency,
            observedAt: now,
            source: source
        )
        let evaluation = AlertEvaluator().evaluate(rule: rule, observation: observation, at: now)

        guard case .triggered(let notification) = evaluation.action else {
            Issue.record("Expected \(kind) to trigger")
            continue
        }
        #expect(evaluation.state.notifiedForCurrentBreach)
        #expect(notification.deepLink?.scheme == "tokendesk")
        #expect(!notification.body.contains(provider.rawValue))
        #expect(!notification.body.contains(accountID.rawValue))
    }
}

@Test
func alertEvaluatorDefersQuietAndCooldownBreachesThenRequiresRecovery() throws {
    let provider = try ProviderID(rawValue: "provider")
    let source = try DataSource(kind: .official, identifier: "fixture")
    let quietHours = try AlertQuietHours(
        startMinute: 22 * 60,
        endMinute: 7 * 60,
        timeZoneIdentifier: "UTC"
    )
    let rule = try AlertRule(
        id: "budget",
        providerID: provider,
        kind: .budgetPercent,
        threshold: 80,
        cooldownSeconds: 3_600,
        quietHours: quietHours
    )
    let quietTime = try utcDate(year: 2026, month: 8, day: 12, hour: 23)
    let eligibleTime = try utcDate(year: 2026, month: 8, day: 13, hour: 7)
    let breach = try AlertObservation(
        providerID: provider,
        kind: .budgetPercent,
        value: 90,
        observedAt: quietTime,
        source: source
    )
    let quiet = AlertEvaluator().evaluate(rule: rule, observation: breach, at: quietTime)
    #expect(quiet.action == .suppressed(.quietHours))
    #expect(quiet.state.isBreached)
    #expect(!quiet.state.notifiedForCurrentBreach)

    let triggered = AlertEvaluator().evaluate(
        rule: rule,
        observation: breach,
        previous: quiet.state,
        at: eligibleTime
    )
    guard case .triggered = triggered.action else {
        Issue.record("Expected the deferred breach to trigger after quiet hours")
        return
    }
    let duplicate = AlertEvaluator().evaluate(
        rule: rule,
        observation: breach,
        previous: triggered.state,
        at: eligibleTime.addingTimeInterval(7_200)
    )
    #expect(duplicate.action == .suppressed(.alreadyNotified))

    let recoveredObservation = try AlertObservation(
        providerID: provider,
        kind: .budgetPercent,
        value: 50,
        observedAt: eligibleTime.addingTimeInterval(300),
        source: source
    )
    let recovered = AlertEvaluator().evaluate(
        rule: rule,
        observation: recoveredObservation,
        previous: triggered.state,
        at: recoveredObservation.observedAt
    )
    #expect(recovered.action == .recovered)

    let cooldown = AlertEvaluator().evaluate(
        rule: rule,
        observation: breach,
        previous: recovered.state,
        at: eligibleTime.addingTimeInterval(600)
    )
    #expect(cooldown.action == .suppressed(.cooldown))
    #expect(!cooldown.state.notifiedForCurrentBreach)

    let retriggered = AlertEvaluator().evaluate(
        rule: rule,
        observation: breach,
        previous: cooldown.state,
        at: eligibleTime.addingTimeInterval(3_600)
    )
    guard case .triggered = retriggered.action else {
        Issue.record("Expected a recovered breach to trigger after cooldown")
        return
    }
}

private func account(
    id: String,
    provider: ProviderID,
    remote: String?,
    scope: AccountScope
) throws -> AccountReference {
    try AccountReference(
        id: AccountID(rawValue: id),
        providerID: provider,
        displayName: id,
        scope: scope,
        hierarchy: AccountHierarchy(remoteAccountReference: remote)
    )
}

private func plan(
    provider: ProviderID,
    account: AccountID,
    limit: String,
    percent: Decimal,
    reset: Date,
    source: DataSourceKind,
    confidence: Decimal? = nil,
    updatedAt: Date
) throws -> PlanWindow {
    try PlanWindow(
        providerID: provider,
        accountID: account,
        planName: "Fixture Plan",
        limitIdentifier: limit,
        usedPercent: UsagePercent(rawValue: percent),
        windowDurationMinutes: 300,
        resetsAt: reset,
        timeZoneIdentifier: "UTC",
        confidence: try confidence.map(SourceConfidence.init),
        metadata: metadata(
            source: DataSource(kind: source, identifier: "\(source.rawValue)-fixture"),
            updatedAt: updatedAt
        )
    )
}

private func usageBucket(
    provider: ProviderID,
    account: AccountID,
    model: String,
    start: Date,
    granularity: UsageGranularity,
    input: Int64,
    output: Int64,
    cached: Int64 = 0,
    cacheWrite: Int64 = 0,
    source: DataSourceKind
) throws -> TokenUsageBucket {
    let duration: TimeInterval
    switch granularity {
    case .minute: duration = 60
    case .hour: duration = 3_600
    case .day: duration = 86_400
    case .week: duration = 7 * 86_400
    case .month: duration = 30 * 86_400
    }
    return try TokenUsageBucket(
        providerID: provider,
        accountID: account,
        model: model,
        granularity: granularity,
        period: UsagePeriod(
            interval: DateInterval(start: start, duration: duration),
            timeZoneIdentifier: "Asia/Shanghai"
        ),
        tokens: TokenBreakdown(
            input: TokenCount(rawValue: input),
            output: TokenCount(rawValue: output),
            cachedInput: TokenCount(rawValue: cached),
            cacheWrite: TokenCount(rawValue: cacheWrite)
        ),
        metadata: metadata(
            source: DataSource(kind: source, identifier: "\(source.rawValue)-usage"),
            updatedAt: start
        )
    )
}

private func metadata(source: DataSource, updatedAt: Date) -> ObservationMetadata {
    ObservationMetadata(source: source, updatedAt: updatedAt, isStale: false)
}

private func utcDate(year: Int, month: Int, day: Int, hour: Int) throws -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
    return try #require(
        calendar.date(
            from: DateComponents(year: year, month: month, day: day, hour: hour)
        )
    )
}
