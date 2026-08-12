import Foundation
import TokenDeskCore
import TokenDeskDesign

/// The complete cache-first render matrix shared by production dashboard pages.
public enum DashboardContentState<Value: Equatable & Sendable>: Equatable, Sendable {
    /// No display value is available while an asynchronous read is in flight.
    case loading
    /// A successful read returned no display values.
    case empty(title: String, detail: String)
    /// Fresh display values are available.
    case loaded(Value)
    /// Cached display values are available but past their freshness window.
    case stale(Value, lastUpdated: Date)
    /// Some independent sources failed while other production values remain readable.
    case partial(Value, issues: [DashboardIssue])
    /// A read failed, optionally retaining its last successful value.
    case failed(title: String, detail: String, cached: Value?)
}

/// Credential-free, deterministic scenarios supplied for App Review and release verification.
public enum AppReviewDemoScenario: String, CaseIterable, Equatable, Identifiable, Sendable {
    case representative
    case offline
    case authentication
    case rateLimited

    /// Stable identifier used by review automation and SwiftUI controls.
    public var id: String { rawValue }

    /// Short label used by the built-in review controls.
    public var title: String {
        switch self {
        case .representative: "代表性数据"
        case .offline: "离线降级"
        case .authentication: "认证失败"
        case .rateLimited: "限流错误"
        }
    }

    /// Privacy-safe explanation of the state the reviewer should observe.
    public var detail: String {
        switch self {
        case .representative: "四页面使用静态脱敏数据；Codex 保持明确不支持。"
        case .offline: "保留最近数据并显示离线、过期与部分失败状态。"
        case .authentication: "OpenAI 显示认证失败，其他 Provider 仍保持可读。"
        case .rateLimited: "OpenAI 显示 Retry-After 限流错误，不生成替代数值。"
        }
    }
}

/// A redacted, actionable degradation shown without exposing transport payloads.
public struct DashboardIssue: Equatable, Identifiable, Sendable {
    /// Stable failure categories used by presentation and accessibility text.
    public enum Kind: String, Equatable, Sendable {
        case authentication
        case permission
        case rateLimited
        case offline
        case unavailable
        case persistence
    }

    /// Provider identifier, or a stable local subsystem identifier.
    public let id: String
    /// Presentation-safe provider or subsystem name.
    public let providerName: String
    /// Normalized actionable category.
    public let kind: Kind
    /// Redacted recovery guidance.
    public let message: String

    /// Creates a redacted dashboard degradation.
    public init(id: String, providerName: String, kind: Kind, message: String) {
        self.id = id
        self.providerName = providerName
        self.kind = kind
        self.message = message
    }
}

/// Weather values rendered by the overview without exposing provider DTOs.
public struct WeatherSnapshot: Equatable, Sendable {
    /// One forecast point displayed in the compact hourly strip.
    public struct Hour: Equatable, Identifiable, Sendable {
        /// Stable bucket identifier.
        public let id: String
        /// Localized hour label.
        public let label: String
        /// One-bit weather symbol.
        public let symbol: String
        /// Temperature in the configured display unit.
        public let temperature: Int

        /// Creates an hourly forecast point.
        public init(id: String, label: String, symbol: String, temperature: Int) {
            self.id = id
            self.label = label
            self.symbol = symbol
            self.temperature = temperature
        }
    }

    /// Localized city name.
    public let city: String
    /// Current temperature in the configured display unit.
    public let temperature: Int
    /// Current apparent temperature.
    public let feelsLike: Int
    /// Human-readable weather condition.
    public let condition: String
    /// Probability of precipitation from zero through one hundred.
    public let precipitationPercent: Int
    /// Relative humidity from zero through one hundred.
    public let humidityPercent: Int
    /// Compact future-hour forecast points.
    public let hours: [Hour]

    /// Creates a weather view snapshot.
    public init(
        city: String,
        temperature: Int,
        feelsLike: Int,
        condition: String,
        precipitationPercent: Int,
        humidityPercent: Int,
        hours: [Hour]
    ) {
        self.city = city
        self.temperature = temperature
        self.feelsLike = feelsLike
        self.condition = condition
        self.precipitationPercent = precipitationPercent
        self.humidityPercent = humidityPercent
        self.hours = hours
    }
}

/// A plan window remains percentage-based and intentionally has no Token fields.
public struct PlanWindowSnapshot: Equatable, Identifiable, Sendable {
    /// Provenance categories that must remain visible beside plan data.
    public enum Source: String, Equatable, Sendable {
        /// Data returned by an official provider API.
        case official = "● 官方数据"
        /// Data calculated locally with an explicit confidence level.
        case estimated = "○ 本地估算"
        /// Fixture-only data that never represents a real account.
        case demonstration = "◇ 演示数据"
    }

    /// Stable plan-window identifier.
    public let id: String
    /// Provider display name.
    public let provider: String
    /// Plan display name.
    public let name: String
    /// Human-readable quota window length.
    public let window: String
    /// Used percentage clamped to zero through one hundred.
    public let usedPercent: Int
    /// Exact or relative reset description.
    public let resetDescription: String
    /// Visible plan data provenance.
    public let source: Source
    /// Confidence label required for local estimates.
    public let confidence: String?

    /// Creates a percentage-based plan window snapshot.
    public init(
        id: String,
        provider: String,
        name: String,
        window: String,
        usedPercent: Int,
        resetDescription: String,
        source: Source,
        confidence: String? = nil
    ) {
        self.id = id
        self.provider = provider
        self.name = name
        self.window = window
        self.usedPercent = min(max(usedPercent, 0), 100)
        self.resetDescription = resetDescription
        self.source = source
        self.confidence = confidence
    }
}

/// A value-free Provider capability state shown when no numeric card may be rendered.
public struct ProviderCapabilityStatusSnapshot: Equatable, Identifiable, Sendable {
    /// Stable presentation identifier.
    public let id: String
    /// Provider display name.
    public let provider: String
    /// Data operation described by this state.
    public let capability: ProviderCapability
    /// Value-free connector state.
    public let state: ConnectorReadState
    /// Short user-facing explanation.
    public let title: String
    /// Privacy-safe detail that does not imply a numeric value.
    public let detail: String

    /// Creates a value-free capability status for fallback presentation.
    public init(
        id: String,
        provider: String,
        capability: ProviderCapability,
        state: ConnectorReadState,
        title: String,
        detail: String
    ) {
        self.id = id
        self.provider = provider
        self.capability = capability
        self.state = state
        self.title = title
        self.detail = detail
    }
}

/// Cost and balance summary; it never masquerades as a plan quota.
public struct ProviderSummarySnapshot: Equatable, Identifiable, Sendable {
    /// Stable provider identifier.
    public let id: String
    /// Provider display name.
    public let name: String
    /// Token usage summary.
    public let usage: String
    /// Cost summary with currency.
    public let cost: String
    /// Balance summary, using a dash when unknown.
    public let balance: String
    /// Current provider health state.
    public let status: TokenDeskStatus

    /// Creates a provider summary without combining its metric domains.
    public init(
        id: String,
        name: String,
        usage: String,
        cost: String,
        balance: String,
        status: TokenDeskStatus
    ) {
        self.id = id
        self.name = name
        self.usage = usage
        self.cost = cost
        self.balance = balance
        self.status = status
    }
}

/// Complete immutable value rendered by the overview page.
public struct OverviewSnapshot: Equatable, Sendable {
    /// Current and hourly weather values.
    public let weather: WeatherSnapshot?
    /// User-selected primary plan window.
    public let primaryPlan: PlanWindowSnapshot?
    /// Token, cost, and balance provider summaries.
    public let providers: [ProviderSummarySnapshot]

    /// Creates a complete overview snapshot.
    public init(
        weather: WeatherSnapshot?,
        primaryPlan: PlanWindowSnapshot?,
        providers: [ProviderSummarySnapshot]
    ) {
        self.weather = weather
        self.primaryPlan = primaryPlan
        self.providers = providers
    }
}

/// User-selectable aggregation ranges for Token data.
public enum TokenTimeRange: String, CaseIterable, Sendable {
    /// Current local day.
    case day = "今日"
    /// Current seven-day view.
    case week = "本周"
    /// Current thirty-day view.
    case month = "本月"

    /// Expanded range description exposed to assistive technology.
    public var accessibilityDescription: String {
        switch self {
        case .day: "今日 24 小时"
        case .week: "最近 7 天"
        case .month: "最近 30 天"
        }
    }
}

/// Enabled provider entry shown in the Token page selector.
public struct TokenProviderSnapshot: Equatable, Identifiable, Sendable {
    /// Stable provider identifier.
    public let id: String
    /// Provider display name.
    public let name: String
    /// Visible provider health state.
    public let status: TokenDeskStatus

    /// Creates a provider selector entry.
    public init(id: String, name: String, status: TokenDeskStatus) {
        self.id = id
        self.name = name
        self.status = status
    }
}

/// Input and output Token counts for one chart bucket.
public struct TokenUsageBucketSnapshot: Equatable, Identifiable, Sendable {
    /// Stable bucket identifier.
    public let id: String
    /// Localized axis label.
    public let label: String
    /// Input Token count.
    public let input: Int64
    /// Output Token count.
    public let output: Int64

    /// Creates a chart bucket with separate input and output values.
    public init(id: String, label: String, input: Int64, output: Int64) {
        self.id = id
        self.label = label
        self.input = input
        self.output = output
    }
}

/// Complete immutable metric and chart value rendered by the Token page.
public struct TokenDashboardSnapshot: Equatable, Sendable {
    /// Selected provider display name.
    public let providerName: String
    /// Aggregated input Token count.
    public let inputTokens: Int64
    /// Aggregated output Token count.
    public let outputTokens: Int64
    /// Formatted cost with currency.
    public let cost: String
    /// Visible official or estimated cost source.
    public let costSource: String
    /// Formatted balance or a dash when unknown.
    public let balance: String
    /// Most frequently used model.
    public let mostUsedModel: String
    /// Formatted cache-hit percentage.
    public let cacheHitRate: String
    /// Formatted month-to-budget comparison.
    public let monthlyBudget: String
    /// Time-ordered input/output chart buckets.
    public let buckets: [TokenUsageBucketSnapshot]

    /// Creates a complete Token dashboard snapshot.
    public init(
        providerName: String,
        inputTokens: Int64,
        outputTokens: Int64,
        cost: String,
        costSource: String,
        balance: String,
        mostUsedModel: String,
        cacheHitRate: String,
        monthlyBudget: String,
        buckets: [TokenUsageBucketSnapshot]
    ) {
        self.providerName = providerName
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cost = cost
        self.costSource = costSource
        self.balance = balance
        self.mostUsedModel = mostUsedModel
        self.cacheHitRate = cacheHitRate
        self.monthlyBudget = monthlyBudget
        self.buckets = buckets
    }

    /// Text alternative that summarizes the trend chart's key totals.
    public var chartSummary: String {
        "\(providerName)，\(inputTokens.formatted()) 输入 Token，\(outputTokens.formatted()) 输出 Token，费用 \(cost)"
    }
}

/// Deterministic page fixtures. They are permanently identified as mock or demo data in the UI.
public enum DashboardFixtures {
    /// Non-numeric states for local-only and unsupported P0 Provider capabilities.
    public static let providerCapabilityStatuses: [ProviderCapabilityStatusSnapshot] = [
        .init(
            id: "gemini-usage-local",
            provider: "Gemini",
            capability: .usage,
            state: .notSynchronized,
            title: "等待本地用量",
            detail: "仅在本地聚合此设备随后收到的 usage metadata；无远端历史时显示空状态。"
        ),
        .init(
            id: "glm-plan-unsupported",
            provider: "智谱 GLM",
            capability: .plan,
            state: .unsupported,
            title: "套餐窗口暂不支持",
            detail: "仅展示响应 usage 的本地聚合与有版本定价的费用估算。"
        ),
        .init(
            id: "minimax-plan-unsupported",
            provider: "MiniMax",
            capability: .plan,
            state: .unsupported,
            title: "Token Plan 暂不映射",
            detail: "公开页面未给出稳定响应字段契约；按量 Token 与套餐额度保持分离。"
        ),
        .init(
            id: "codex-plan-unsupported",
            provider: "Codex",
            capability: .plan,
            state: .unsupported,
            title: "官方生产接口暂不可用",
            detail: "GATE-02 关闭期间不读取 Cookie、私有容器或用户现有 Codex 进程。"
        ),
    ]

    /// Deterministic overview fixture, permanently labeled mock/demo in the UI.
    public static let overview = OverviewSnapshot(
        weather: WeatherSnapshot(
            city: "上海",
            temperature: 31,
            feelsLike: 34,
            condition: "晴朗",
            precipitationPercent: 10,
            humidityPercent: 63,
            hours: [
                .init(id: "now", label: "现在", symbol: "☀", temperature: 31),
                .init(id: "11", label: "11时", symbol: "☀", temperature: 32),
                .init(id: "13", label: "13时", symbol: "◉", temperature: 34),
                .init(id: "15", label: "15时", symbol: "☀", temperature: 33),
            ]
        ),
        primaryPlan: .init(
            id: "codex-primary",
            provider: "Codex",
            name: "Codex Pro",
            window: "主额度窗口 · 5 小时",
            usedPercent: 42,
            resetDescription: "3 小时 18 分后重置",
            source: .demonstration
        ),
        providers: [
            .init(
                id: "openai",
                name: "OpenAI API",
                usage: "1.82M Token",
                cost: "$28.46 本月费用",
                balance: "余额 —",
                status: .connected
            ),
            .init(
                id: "deepseek",
                name: "DeepSeek",
                usage: "684K Token",
                cost: "¥12.80 本月费用",
                balance: "余额 ¥76.20",
                status: .stale
            ),
        ]
    )

    /// Deterministic plans covering zero, one hundred, and estimated states.
    public static let plans: [PlanWindowSnapshot] = [
        .init(
            id: "codex-primary",
            provider: "Codex",
            name: "Codex Pro",
            window: "5 小时窗口",
            usedPercent: 0,
            resetDescription: "12:59 重置",
            source: .demonstration
        ),
        .init(
            id: "codex-week",
            provider: "Codex",
            name: "其他模型",
            window: "7 天窗口",
            usedPercent: 100,
            resetDescription: "周一 08:00 重置",
            source: .demonstration
        ),
        .init(
            id: "anthropic",
            provider: "Anthropic",
            name: "Max",
            window: "本周估算",
            usedPercent: 31,
            resetDescription: "周一 08:00 重新统计",
            source: .estimated,
            confidence: "中"
        ),
    ]

    /// MVP provider selector entries with representative health states.
    public static let tokenProviders: [TokenProviderSnapshot] = [
        .init(id: "openai", name: "OpenAI", status: .connected),
        .init(id: "anthropic", name: "Anthropic", status: .connected),
        .init(id: "deepseek", name: "DeepSeek", status: .stale),
        .init(id: "glm", name: "智谱 GLM", status: .connected),
        .init(id: "kimi", name: "Kimi", status: .syncing),
        .init(id: "minimax", name: "MiniMax", status: .connected),
        .init(id: "openrouter", name: "OpenRouter", status: .warning),
        .init(id: "gemini", name: "Gemini", status: .connected),
        .init(id: "codex", name: "Codex", status: .unavailable),
    ]

    /// Returns the Provider-specific demo state without inventing values for unsupported Codex.
    public static func tokenContentState(
        providerID: String,
        range: TokenTimeRange
    ) -> DashboardContentState<TokenDashboardSnapshot> {
        guard providerID != "codex" else {
            return .empty(
                title: "官方生产接口暂不可用",
                detail: "GATE-02 关闭期间不读取 Cookie、私有容器或真实额度。"
            )
        }
        return .loaded(tokens(providerID: providerID, range: range))
    }

    /// Builds deterministic, internally consistent metrics for a provider and range.
    public static func tokens(providerID: String, range: TokenTimeRange) -> TokenDashboardSnapshot {
        let providerIndex = tokenProviders.firstIndex(where: { $0.id == providerID }) ?? 0
        let provider = tokenProviders[providerIndex]
        let rangeMultiplier: Int64
        let labels: [String]
        switch range {
        case .day:
            rangeMultiplier = 1
            labels = ["00", "04", "08", "12", "16", "20"]
        case .week:
            rangeMultiplier = 7
            labels = ["一", "二", "三", "四", "五", "六", "日"]
        case .month:
            rangeMultiplier = 30
            labels = ["1", "5", "10", "15", "20", "25", "30"]
        }
        let providerMultiplier = Int64(providerIndex + 2)
        let buckets = labels.enumerated().map { index, label in
            TokenUsageBucketSnapshot(
                id: "\(range.rawValue)-\(label)",
                label: label,
                input: Int64(18_000 + (index * 7_200)) * providerMultiplier * rangeMultiplier,
                output: Int64(6_000 + (index * 2_900)) * providerMultiplier * rangeMultiplier
            )
        }
        let input = buckets.reduce(0) { $0 + $1.input }
        let output = buckets.reduce(0) { $0 + $1.output }
        let dollars = Decimal(input + output) / Decimal(1_000_000) * Decimal(325) / Decimal(100)
        let formattedCost = String(
            format: "$%.2f",
            locale: Locale(identifier: "en_US_POSIX"),
            NSDecimalNumber(decimal: dollars).doubleValue
        )
        return TokenDashboardSnapshot(
            providerName: "\(provider.name) API",
            inputTokens: input,
            outputTokens: output,
            cost: formattedCost,
            costSource: provider.id == "openai" ? "◇ 演示 · 官方 Costs 样例" : "◇ 演示 · 价格估算样例",
            balance: provider.id == "deepseek" ? "¥76.20" : "—",
            mostUsedModel: ["gpt-5.6", "claude-sonnet", "deepseek-chat", "glm-4.5"][
                providerIndex % 4],
            cacheHitRate: "\(48 + providerIndex * 4).\(providerIndex)%",
            monthlyBudget: "$\(18 + providerIndex * 3) / $50",
            buckets: buckets
        )
    }
}
