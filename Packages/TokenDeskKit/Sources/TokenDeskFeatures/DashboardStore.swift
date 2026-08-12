import Foundation
import Observation
import TokenDeskCore
import TokenDeskDesign

/// Cache-first application state shared by the header and all data pages.
@MainActor
@Observable
public final class DashboardStore {
    /// Cancellation-aware polling delay hook used by deterministic cadence tests.
    public typealias PollingSleeper = @Sendable (Duration) async throws -> Void

    /// Render state for the overview page.
    public private(set) var overviewState: DashboardContentState<OverviewSnapshot> = .loading
    /// Render state for the plan page.
    public private(set) var plansState: DashboardContentState<[PlanWindowSnapshot]> = .loading
    /// Value-free explanations for intentionally unsupported capabilities.
    public private(set) var capabilityStatuses = DashboardFixtures.providerCapabilityStatuses
    /// Whether a cancellable cache/network refresh is active.
    public private(set) var isSynchronizing = false
    /// Most recent successful cache or synchronization observation.
    public private(set) var lastUpdatedAt: Date?
    /// Active credential-free App Review scenario, or nil while production data is in use.
    public private(set) var reviewScenario: AppReviewDemoScenario?
    /// Provider and range state shared by the Token page.
    public let tokensStore: TokensPageStore

    /// Whether every dashboard value currently comes from bundled demonstration fixtures.
    public var isReviewDemoActive: Bool { reviewScenario != nil }

    /// Aggregate status for the global header; text accompanies every visual symbol.
    public var headerStatus: TokenDeskStatus {
        if isSynchronizing { return .syncing }
        if tokensStore.providers.contains(where: { $0.status == .unavailable }) {
            return tokensStore.providers.contains(where: {
                $0.status == .connected || $0.status == .stale
            })
                ? .warning : .unavailable
        }
        if tokensStore.providers.contains(where: { $0.status == .stale }) { return .stale }
        return tokensStore.providers.isEmpty ? .unavailable : .connected
    }

    private let dataProvider: (any DashboardDataProviding)?
    private let now: @Sendable () -> Date
    private var cachedData: DashboardDataSnapshot?
    private var activeRefresh: Task<Void, Never>?
    private var activeRefreshID: UUID?

    private struct Projection: Sendable {
        let overviewState: DashboardContentState<OverviewSnapshot>
        let plansState: DashboardContentState<[PlanWindowSnapshot]>
        let tokenProviders: [TokenProviderSnapshot]
        let tokenStates: [String: [TokenTimeRange: DashboardContentState<TokenDashboardSnapshot>]]
        let tokenFallback: DashboardContentState<TokenDashboardSnapshot>?
        let lastUpdatedAt: Date?
    }

    /// Creates fixture-backed state when no service is supplied, or production loading state when
    /// a service is injected by the application composition root.
    public init(
        dataProvider: (any DashboardDataProviding)? = nil,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.dataProvider = dataProvider
        self.now = now
        tokensStore = TokensPageStore()
        if dataProvider == nil {
            activateAppReviewDemo(.representative)
        }
    }

    /// Stops production refreshes and atomically selects a deterministic, visibly labeled state.
    public func activateAppReviewDemo(_ scenario: AppReviewDemoScenario) {
        activeRefresh?.cancel()
        activeRefresh = nil
        activeRefreshID = nil
        isSynchronizing = false
        reviewScenario = scenario
        capabilityStatuses = DashboardFixtures.providerCapabilityStatuses

        let updatedAt = now().addingTimeInterval(scenario == .offline ? -3_600 : -300)
        lastUpdatedAt = updatedAt
        tokensStore.applyDemonstration(
            providers: demonstrationProviders(for: scenario),
            states: demonstrationTokenStates(for: scenario)
        )

        switch scenario {
        case .representative:
            overviewState = .loaded(DashboardFixtures.overview)
            plansState = .loaded(DashboardFixtures.plans)
        case .offline:
            let issue = demonstrationIssue(
                id: "network",
                providerName: "演示网络",
                kind: .offline,
                message: "演示离线：显示最近数据，恢复网络后可重试。"
            )
            overviewState = .partial(DashboardFixtures.overview, issues: [issue])
            plansState = .stale(DashboardFixtures.plans, lastUpdated: updatedAt)
        case .authentication:
            let issue = demonstrationIssue(
                id: "openai",
                providerName: "OpenAI 演示账户",
                kind: .authentication,
                message: "演示认证失败：无需输入真实密钥；其他 Provider 不受影响。"
            )
            overviewState = .partial(DashboardFixtures.overview, issues: [issue])
            plansState = .failed(
                title: "演示认证失败",
                detail: "最近套餐数据仍可查看；无需提供高权限凭据。",
                cached: DashboardFixtures.plans
            )
        case .rateLimited:
            let issue = demonstrationIssue(
                id: "openai",
                providerName: "OpenAI 演示账户",
                kind: .rateLimited,
                message: "演示限流：遵循 Retry-After 60 秒，不生成替代数值。"
            )
            overviewState = .partial(DashboardFixtures.overview, issues: [issue])
            plansState = .partial(DashboardFixtures.plans, issues: [issue])
        }
    }

    /// Leaves App Review mode and reloads cache plus live sources through production boundaries.
    public func deactivateAppReviewDemo(location: WeatherLocation?) async {
        guard reviewScenario != nil else { return }
        guard dataProvider != nil else {
            activateAppReviewDemo(.representative)
            return
        }
        reviewScenario = nil
        overviewState = .loading
        plansState = .loading
        tokensStore.applyProduction(providers: [], states: [:], fallback: .loading)
        lastUpdatedAt = nil
        await loadCache()
        await refresh(location: location)
    }

    /// Reads SQLite immediately and then starts one foreground refresh of independent sources.
    public func start(location: WeatherLocation?) async {
        guard dataProvider != nil, reviewScenario == nil else { return }
        await loadCache()
        await refresh(location: location)
    }

    /// Polls active data in tiered lanes: usage each minute, money every five minutes, and weather
    /// at its configured cadence. The loop sleeps with tolerance and ends promptly on cancellation.
    public func runPolling(
        location: WeatherLocation?,
        weatherRefreshMinutes: Int,
        sleeper: @escaping PollingSleeper = {
            try await Task.sleep(for: $0, tolerance: .seconds(5))
        }
    ) async {
        guard reviewScenario == nil else { return }
        let weatherCadence = max(1, weatherRefreshMinutes)
        var elapsedMinutes = 0
        while !Task.isCancelled {
            do {
                try await sleeper(.seconds(60))
            } catch {
                return
            }
            guard !Task.isCancelled, reviewScenario == nil else { return }
            elapsedMinutes += 1
            var scope: DashboardRefreshScope = [.usage]
            if elapsedMinutes.isMultiple(of: 5) { scope.insert(.money) }
            if elapsedMinutes.isMultiple(of: weatherCadence) { scope.insert(.weather) }
            await refresh(location: location, scope: scope)
        }
    }

    /// Cancels an older refresh, preserves cached cards, and publishes the new matrix atomically.
    public func refresh(
        location: WeatherLocation?,
        scope: DashboardRefreshScope = .all
    ) async {
        guard let dataProvider, reviewScenario == nil else { return }
        activeRefresh?.cancel()
        let refreshID = UUID()
        activeRefreshID = refreshID
        let task = Task { [weak self] in
            guard let self else { return }
            isSynchronizing = true
            let result = await dataProvider.refreshDashboardData(location: location, scope: scope)
            guard !Task.isCancelled else {
                if activeRefreshID == refreshID { isSynchronizing = false }
                return
            }
            let issues = Self.issues(from: result)
            do {
                let data = try await dataProvider.loadCachedDashboardData()
                cachedData = data
                let projection = try await project(data, issues: issues)
                guard !Task.isCancelled else { return }
                publish(projection)
                lastUpdatedAt = result.providerReport.completedAt
            } catch is CancellationError {
                if activeRefreshID == refreshID { isSynchronizing = false }
                return
            } catch {
                await applyReadFailure(cached: cachedData)
            }
            isSynchronizing = false
        }
        activeRefresh = task
        await task.value
        if activeRefreshID == refreshID {
            activeRefresh = nil
            activeRefreshID = nil
        }
    }

    private func loadCache() async {
        guard let dataProvider else { return }
        do {
            let data = try await dataProvider.loadCachedDashboardData()
            cachedData = data
            let projection = try await project(data, issues: [])
            guard !Task.isCancelled else { return }
            publish(projection)
        } catch is CancellationError {
            return
        } catch {
            await applyReadFailure(cached: nil)
        }
    }

    private func demonstrationProviders(
        for scenario: AppReviewDemoScenario
    ) -> [TokenProviderSnapshot] {
        DashboardFixtures.tokenProviders.map { provider in
            let status: TokenDeskStatus
            switch scenario {
            case .representative:
                status = provider.status
            case .offline:
                status = provider.id == "codex" ? .unavailable : .stale
            case .authentication, .rateLimited:
                status = provider.id == "openai" ? .unavailable : provider.status
            }
            return TokenProviderSnapshot(id: provider.id, name: provider.name, status: status)
        }
    }

    private func demonstrationTokenStates(
        for scenario: AppReviewDemoScenario
    ) -> [String: [TokenTimeRange: DashboardContentState<TokenDashboardSnapshot>]]? {
        guard scenario != .representative else { return nil }
        var states: [String: [TokenTimeRange: DashboardContentState<TokenDashboardSnapshot>]] = [:]
        for provider in DashboardFixtures.tokenProviders {
            var ranges: [TokenTimeRange: DashboardContentState<TokenDashboardSnapshot>] = [:]
            for range in TokenTimeRange.allCases {
                let fixture = DashboardFixtures.tokenContentState(
                    providerID: provider.id,
                    range: range
                )
                if provider.id == "codex" {
                    ranges[range] = fixture
                    continue
                }
                let snapshot = DashboardFixtures.tokens(providerID: provider.id, range: range)
                switch scenario {
                case .representative:
                    ranges[range] = fixture
                case .offline:
                    ranges[range] = .partial(
                        snapshot,
                        issues: [
                            demonstrationIssue(
                                id: provider.id,
                                providerName: provider.name,
                                kind: .offline,
                                message: "演示离线：保留最近成功数据。"
                            )
                        ]
                    )
                case .authentication where provider.id == "openai":
                    ranges[range] = .failed(
                        title: "OpenAI 演示认证失败",
                        detail: "无需输入真实密钥；其他 Provider 仍可验证。",
                        cached: snapshot
                    )
                case .rateLimited where provider.id == "openai":
                    ranges[range] = .failed(
                        title: "OpenAI 演示限流",
                        detail: "Retry-After 60 秒；此状态不生成替代数值。",
                        cached: nil
                    )
                case .authentication, .rateLimited:
                    ranges[range] = fixture
                }
            }
            states[provider.id] = ranges
        }
        return states
    }

    private func demonstrationIssue(
        id: String,
        providerName: String,
        kind: DashboardIssue.Kind,
        message: String
    ) -> DashboardIssue {
        DashboardIssue(
            id: id,
            providerName: providerName,
            kind: kind,
            message: message
        )
    }

    private func project(
        _ data: DashboardDataSnapshot,
        issues: [DashboardIssue]
    ) async throws -> Projection {
        let current = now()
        // Projection aggregates up to 35 days for every Provider and range. It is intentionally
        // detached from MainActor so chart preparation cannot consume a 16 ms render frame.
        let task = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            let projection = Self.makeProjection(data, issues: issues, current: current)
            try Task.checkCancellation()
            return projection
        }
        defer { task.cancel() }
        return try await task.value
    }

    nonisolated private static func makeProjection(
        _ data: DashboardDataSnapshot,
        issues: [DashboardIssue],
        current: Date
    ) -> Projection {
        let enabled = data.configurations.filter(\.isEnabled)
        let accounts = enabled.compactMap { try? $0.accountReference }
        let names = Dictionary(
            uniqueKeysWithValues: enabled.map { ($0.providerID, $0.providerDisplayName) })
        let namedIssues = issues.map { issue in
            let configuredName = (try? ProviderID(rawValue: issue.id)).flatMap { names[$0] }
            return DashboardIssue(
                id: issue.id,
                providerName: issue.id == "weather"
                    ? issue.providerName : configuredName ?? issue.providerName,
                kind: issue.kind,
                message: issue.message
            )
        }
        let planAggregation = PlanAggregator().aggregate(
            windows: data.plans,
            accounts: accounts,
            primarySelection: nil,
            at: current
        )
        let plans = planAggregation.windows.map { planSnapshot($0, names: names) }
        let providerIDs = Array(Set(enabled.map(\.providerID))).sorted {
            (names[$0] ?? $0.rawValue) < (names[$1] ?? $1.rawValue)
        }

        var tokenProviders: [TokenProviderSnapshot] = []
        var tokenStates: [String: [TokenTimeRange: DashboardContentState<TokenDashboardSnapshot>]] =
            [:]
        var overviewProviders: [ProviderSummarySnapshot] = []
        for providerID in providerIDs {
            let providerName = names[providerID] ?? providerID.rawValue
            let providerIssues = namedIssues.filter {
                $0.id == providerID.rawValue || $0.id == "local-database"
            }
            let providerData = hasData(for: providerID, in: data)
            let status = providerStatus(
                providerID: providerID,
                data: data,
                issues: providerIssues,
                now: current
            )
            tokenProviders.append(
                TokenProviderSnapshot(id: providerID.rawValue, name: providerName, status: status)
            )
            var rangeStates: [TokenTimeRange: DashboardContentState<TokenDashboardSnapshot>] = [:]
            for range in TokenTimeRange.allCases {
                do {
                    let aggregate = try TokenAggregator().aggregate(
                        providerID: providerID,
                        accounts: accounts,
                        usage: data.usage,
                        costs: data.costs,
                        balances: data.balances,
                        range: range.coreRange,
                        at: current,
                        timeZone: .current
                    )
                    let snapshot = tokenSnapshot(
                        aggregate, providerName: providerName, range: range)
                    rangeStates[range] = contentState(
                        value: snapshot,
                        hasData: providerData,
                        issues: providerIssues,
                        metadata: metadata(for: providerID, in: data),
                        emptyTitle: "尚无用量数据",
                        emptyDetail: "首次同步后显示；数值 0 会作为有效数据保留。",
                        now: current
                    )
                    if range == .day {
                        overviewProviders.append(
                            ProviderSummarySnapshot(
                                id: providerID.rawValue,
                                name: providerName,
                                usage:
                                    "\(compact(aggregate.tokens.input.rawValue + aggregate.tokens.output.rawValue)) Token",
                                cost: moneyList(aggregate.costs, unknown: "费用 —"),
                                balance: moneyList(aggregate.balances, unknown: "余额 —"),
                                status: status
                            )
                        )
                    }
                } catch {
                    rangeStates[range] = .failed(
                        title: "数据聚合失败",
                        detail: "已保留其他 Provider 数据，可稍后重试。",
                        cached: nil
                    )
                }
            }
            tokenStates[providerID.rawValue] = rangeStates
        }

        let tokenFallback: DashboardContentState<TokenDashboardSnapshot>? =
            tokenProviders.isEmpty
            ? .empty(
                title: "尚未配置 Provider",
                detail: "请通过右上角唯一设置入口添加账户。"
            ) : nil

        let plansState = contentState(
            value: plans,
            hasData: !plans.isEmpty,
            issues: namedIssues.filter { $0.id != "weather" },
            metadata: data.plans.map(\.metadata),
            emptyTitle: "尚无套餐窗口",
            emptyDetail: "未配置套餐能力，或 Provider 明确不支持公开套餐数据。",
            now: current
        )

        let overview = OverviewSnapshot(
            weather: data.weather.map(weatherSnapshot),
            primaryPlan: (planAggregation.primary ?? planAggregation.windows.first).map {
                planSnapshot($0, names: names)
            },
            providers: Array(overviewProviders.prefix(2))
        )
        let overviewMetadata = metadata(in: data)
        let overviewHasData =
            overview.weather != nil || overview.primaryPlan != nil
            || providerIDs.contains {
                hasData(for: $0, in: data)
            }
        let overviewState = contentState(
            value: overview,
            hasData: overviewHasData,
            issues: namedIssues,
            metadata: overviewMetadata,
            emptyTitle: "尚无看板数据",
            emptyDetail: "本地缓存为空；配置 Provider 或天气位置后即可同步。",
            now: current
        )
        return Projection(
            overviewState: overviewState,
            plansState: plansState,
            tokenProviders: tokenProviders,
            tokenStates: tokenStates,
            tokenFallback: tokenFallback,
            lastUpdatedAt: overviewMetadata.map(\.updatedAt).max()
        )
    }

    private func publish(_ projection: Projection) {
        overviewState = projection.overviewState
        plansState = projection.plansState
        tokensStore.applyProduction(
            providers: projection.tokenProviders,
            states: projection.tokenStates,
            fallback: projection.tokenFallback
        )
        lastUpdatedAt = projection.lastUpdatedAt
    }

    private func applyReadFailure(cached: DashboardDataSnapshot?) async {
        let title = "本地数据不可用"
        let detail = "数据库读取失败；不会用演示数据替代生产数据。"
        if let cached {
            do {
                let projection = try await project(
                    cached,
                    issues: [
                        DashboardIssue(
                            id: "local-database",
                            providerName: "本地缓存",
                            kind: .persistence,
                            message: detail
                        )
                    ]
                )
                publish(projection)
            } catch {
                return
            }
        } else {
            overviewState = .failed(title: title, detail: detail, cached: nil)
            plansState = .failed(title: title, detail: detail, cached: nil)
            tokensStore.applyProduction(
                providers: [],
                states: [:],
                fallback: .failed(title: title, detail: detail, cached: nil)
            )
        }
    }

    nonisolated private static func contentState<Value: Equatable & Sendable>(
        value: Value,
        hasData: Bool,
        issues: [DashboardIssue],
        metadata: [ObservationMetadata],
        emptyTitle: String,
        emptyDetail: String,
        now: Date
    ) -> DashboardContentState<Value> {
        if !issues.isEmpty, hasData { return .partial(value, issues: issues) }
        if !issues.isEmpty, !hasData {
            let issue = issues[0]
            return .failed(title: issue.providerName, detail: issue.message, cached: nil)
        }
        guard hasData else { return .empty(title: emptyTitle, detail: emptyDetail) }
        if let latest = metadata.map(\.updatedAt).max(),
            metadata.contains(where: {
                $0.isStale || now.timeIntervalSince($0.updatedAt) > 30 * 60
            })
        {
            return .stale(value, lastUpdated: latest)
        }
        return .loaded(value)
    }

    nonisolated private static func planSnapshot(
        _ plan: PlanWindow,
        names: [ProviderID: String]
    ) -> PlanWindowSnapshot {
        let source: PlanWindowSnapshot.Source =
            switch plan.metadata.source.kind {
            case .official: .official
            case .estimated, .locallyAggregated: .estimated
            case .demonstration: .demonstration
            }
        let confidence = plan.confidence.map {
            "\(NSDecimalNumber(decimal: $0.rawValue * 100).intValue)%"
        }
        return PlanWindowSnapshot(
            id: "\(plan.providerID.rawValue)-\(plan.accountID.rawValue)-\(plan.limitIdentifier)",
            provider: names[plan.providerID] ?? plan.providerID.rawValue,
            name: plan.planName,
            window: durationDescription(minutes: plan.windowDurationMinutes),
            usedPercent: NSDecimalNumber(decimal: plan.usedPercent.displayValue).intValue,
            resetDescription: "\(plan.resetsAt.formatted(date: .abbreviated, time: .shortened)) 重置",
            source: source,
            confidence: confidence
        )
    }

    nonisolated private static func tokenSnapshot(
        _ aggregate: TokenAggregation,
        providerName: String,
        range: TokenTimeRange
    ) -> TokenDashboardSnapshot {
        let cost = moneyList(aggregate.costs, unknown: "—")
        let estimated = aggregate.costs.contains(where: \.containsEstimatedValues)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = range == .day ? "HH" : "M/d"
        return TokenDashboardSnapshot(
            providerName: providerName,
            inputTokens: aggregate.tokens.input.rawValue,
            outputTokens: aggregate.tokens.output.rawValue,
            cost: cost,
            costSource: estimated ? "○ 版本化价格估算" : "● 官方 Costs",
            balance: moneyList(aggregate.balances, unknown: "—"),
            mostUsedModel: aggregate.byModel.first?.model ?? "—",
            cacheHitRate: aggregate.cacheHitPercent.map {
                "\(NSDecimalNumber(decimal: $0).doubleValue.formatted(.number.precision(.fractionLength(1))))%"
            } ?? "—",
            monthlyBudget: aggregate.monthlyBudget.map {
                "\(money($0.spent)) / \(money($0.budget))"
            } ?? "未设置",
            buckets: aggregate.timeline.map {
                TokenUsageBucketSnapshot(
                    id: ISO8601DateFormatter().string(from: $0.period.interval.start),
                    label: formatter.string(from: $0.period.interval.start),
                    input: $0.tokens.input.rawValue,
                    output: $0.tokens.output.rawValue
                )
            }
        )
    }

    nonisolated private static func weatherSnapshot(
        _ weather: TokenDeskCore.WeatherSnapshot
    ) -> WeatherSnapshot {
        WeatherSnapshot(
            city: weather.location.cityName,
            temperature: decimalInteger(weather.temperatureCelsius),
            feelsLike: decimalInteger(weather.apparentTemperatureCelsius),
            condition: weatherDescription(code: weather.conditionCode),
            precipitationPercent: decimalInteger(weather.precipitationProbabilityPercent),
            humidityPercent: decimalInteger(weather.humidityPercent),
            hours: weather.hourlyForecast.map {
                WeatherSnapshot.Hour(
                    id: ISO8601DateFormatter().string(from: $0.startsAt),
                    label: $0.startsAt.formatted(date: .omitted, time: .shortened),
                    symbol: weatherSymbol(code: $0.conditionCode),
                    temperature: decimalInteger($0.temperatureCelsius)
                )
            }
        )
    }

    nonisolated private static func providerStatus(
        providerID: ProviderID,
        data: DashboardDataSnapshot,
        issues: [DashboardIssue],
        now: Date
    ) -> TokenDeskStatus {
        if let issue = issues.first {
            return issue.kind == .rateLimited ? .warning : .unavailable
        }
        let values = metadata(for: providerID, in: data)
        if values.isEmpty { return .unavailable }
        if values.contains(where: { $0.isStale || now.timeIntervalSince($0.updatedAt) > 30 * 60 }) {
            return .stale
        }
        return .connected
    }

    nonisolated private static func hasData(
        for providerID: ProviderID,
        in data: DashboardDataSnapshot
    ) -> Bool {
        data.usage.contains { $0.providerID == providerID }
            || data.costs.contains { $0.providerID == providerID }
            || data.balances.contains { $0.providerID == providerID }
    }

    nonisolated private static func metadata(
        for providerID: ProviderID,
        in data: DashboardDataSnapshot
    )
        -> [ObservationMetadata]
    {
        data.usage.filter { $0.providerID == providerID }.map(\.metadata)
            + data.costs.filter { $0.providerID == providerID }.map(\.metadata)
            + data.balances.filter { $0.providerID == providerID }.map(\.metadata)
    }

    nonisolated private static func metadata(
        in data: DashboardDataSnapshot
    ) -> [ObservationMetadata] {
        data.plans.map(\.metadata) + data.usage.map(\.metadata) + data.costs.map(\.metadata)
            + data.balances.map(\.metadata) + [data.weather?.metadata].compactMap { $0 }
    }

    nonisolated private static func issues(
        from result: DashboardRefreshResult
    ) -> [DashboardIssue] {
        var issues = result.providerReport.providers.compactMap { provider -> DashboardIssue? in
            switch provider.status {
            case .succeeded:
                return nil
            case .failed(let error):
                return issue(
                    id: provider.providerID.rawValue, name: provider.providerID.rawValue,
                    error: error)
            case .persistenceFailed:
                return DashboardIssue(
                    id: provider.providerID.rawValue,
                    providerName: provider.providerID.rawValue,
                    kind: .persistence,
                    message: "同步成功但本地保存失败，请稍后重试。"
                )
            case .cancelled:
                return DashboardIssue(
                    id: provider.providerID.rawValue,
                    providerName: provider.providerID.rawValue,
                    kind: .unavailable,
                    message: "同步已取消。"
                )
            }
        }
        if let weather = result.weatherResult, let error = weather.failure {
            issues.append(issue(id: "weather", name: "天气", error: error))
        }
        return issues
    }

    nonisolated private static func issue(
        id: String,
        name: String,
        error: ConnectorError
    ) -> DashboardIssue {
        let kind: DashboardIssue.Kind
        let message: String
        switch error {
        case .authentication:
            kind = .authentication
            message = "需要重新认证；请在设置中替换凭据。"
        case .permissionDenied:
            kind = .permission
            message = "凭据权限不足；请检查只读账户范围。"
        case .rateLimited(let retryAfter):
            kind = .rateLimited
            message =
                retryAfter == nil ? "Provider 已限流，将按退避策略重试。" : "Provider 已限流，将在 Retry-After 后重试。"
        case .network:
            kind = .offline
            message = "网络离线；继续显示最近成功数据。"
        case .server, .decoding, .unsupported:
            kind = .unavailable
            message = "接口暂不可用；不会清空最近成功数据。"
        case .cancelled:
            kind = .unavailable
            message = "同步已取消。"
        }
        return DashboardIssue(id: id, providerName: name, kind: kind, message: message)
    }
}

private extension TokenTimeRange {
    var coreRange: TokenAggregationRange {
        switch self {
        case .day: .day
        case .week: .week
        case .month: .month
        }
    }
}

private func durationDescription(minutes: Int64) -> String {
    if minutes % 1_440 == 0 { return "\(minutes / 1_440) 天窗口" }
    if minutes % 60 == 0 { return "\(minutes / 60) 小时窗口" }
    return "\(minutes) 分钟窗口"
}

private func compact(_ value: Int64) -> String {
    if value >= 1_000_000 { return String(format: "%.2fM", Double(value) / 1_000_000) }
    if value >= 1_000 { return String(format: "%.1fK", Double(value) / 1_000) }
    return value.formatted()
}

private func money(_ value: Money) -> String {
    let amount = NSDecimalNumber(decimal: value.amount).doubleValue
    return "\(value.currency.rawValue) \(amount.formatted(.number.precision(.fractionLength(2))))"
}

private func moneyList(_ values: [CurrencyAggregate], unknown: String) -> String {
    guard !values.isEmpty else { return unknown }
    return values.map { money($0.money) }.joined(separator: " / ")
}

private func decimalInteger(_ value: Decimal) -> Int {
    NSDecimalNumber(decimal: value).intValue
}

private func weatherDescription(code: Int) -> String {
    switch code {
    case 0: "晴朗"
    case 1...3: "多云"
    case 45, 48: "雾"
    case 51...67, 80...82: "降雨"
    case 71...77, 85, 86: "降雪"
    case 95...99: "雷雨"
    default: "天气代码 \(code)"
    }
}

private func weatherSymbol(code: Int) -> String {
    switch code {
    case 0: "☀"
    case 1...3: "◉"
    case 45, 48: "≋"
    case 51...67, 80...82, 95...99: "☂"
    case 71...77, 85, 86: "✣"
    default: "·"
    }
}
