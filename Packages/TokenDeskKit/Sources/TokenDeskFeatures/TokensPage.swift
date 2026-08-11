import Charts
import Observation
import SwiftUI
import TokenDeskDesign

/// Selection and whole-snapshot state for the Token page.
@MainActor
@Observable
public final class TokensPageStore {
    /// Enabled providers available for viewing.
    public private(set) var providers: [TokenProviderSnapshot]
    /// Identifier of the provider currently rendered.
    public private(set) var selectedProviderID: String
    /// Selected aggregation range.
    public private(set) var selectedRange: TokenTimeRange
    /// Current render state for all Token metrics and chart data.
    public var contentState: DashboardContentState<TokenDashboardSnapshot>

    /// Creates a store with deterministic fixture-backed defaults.
    public init(
        providers: [TokenProviderSnapshot] = DashboardFixtures.tokenProviders,
        selectedProviderID: String = "openai",
        selectedRange: TokenTimeRange = .week,
        contentState: DashboardContentState<TokenDashboardSnapshot>? = nil
    ) {
        self.providers = providers
        self.selectedProviderID =
            providers.contains(where: { $0.id == selectedProviderID })
            ? selectedProviderID : providers.first?.id ?? selectedProviderID
        self.selectedRange = selectedRange
        self.contentState =
            contentState
            ?? .loaded(
                DashboardFixtures.tokens(providerID: selectedProviderID, range: selectedRange))
    }

    /// Selects an enabled provider and atomically replaces the displayed snapshot.
    public func selectProvider(_ id: String) {
        guard providers.contains(where: { $0.id == id }) else { return }
        selectedProviderID = id
        contentState = .loaded(DashboardFixtures.tokens(providerID: id, range: selectedRange))
    }

    /// Selects an aggregation range and atomically replaces the displayed snapshot.
    public func selectRange(_ range: TokenTimeRange) {
        selectedRange = range
        contentState = .loaded(
            DashboardFixtures.tokens(providerID: selectedProviderID, range: range)
        )
    }
}

/// Provider-selectable Token metrics and Swift Charts trend page.
public struct TokensPage: View {
    @Bindable private var store: TokensPageStore

    /// Creates the page with an injectable observable store.
    @MainActor
    public init(store: TokensPageStore = TokensPageStore()) {
        self.store = store
    }

    /// Fixed provider-list, metric, chart, and footer layout.
    public var body: some View {
        VStack(spacing: TokenDeskDesign.Spacing.small) {
            HStack(alignment: .center) {
                PageHeading(
                    title: "Token页面",
                    subtitle: "输入、输出、缓存、费用与余额分别展示",
                    code: "TOKEN USAGE · MOCK"
                )
                Spacer(minLength: 20)
                rangePicker
            }

            HStack(spacing: TokenDeskDesign.Spacing.large) {
                providerList
                    .frame(width: TokenDeskDesign.Canvas.providerColumnWidth)

                DashboardStateView(state: store.contentState) { snapshot in
                    tokenDetails(snapshot)
                }
            }
            .frame(maxHeight: .infinity)
        }
        .padding(.horizontal, TokenDeskDesign.Spacing.extraLarge)
        .padding(.vertical, TokenDeskDesign.Spacing.medium)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Token页面")
        .accessibilityIdentifier("page-tokens")
    }

    private var rangePicker: some View {
        HStack(spacing: TokenDeskDesign.Spacing.extraSmall) {
            ForEach(TokenTimeRange.allCases, id: \.self) { range in
                Button(range.rawValue) {
                    store.selectRange(range)
                }
                .buttonStyle(TokenDeskButtonStyle(isSelected: store.selectedRange == range))
                .accessibilityIdentifier("token-range-\(range)")
            }
        }
    }

    private var providerList: some View {
        VStack(spacing: 0) {
            Text("PROVIDERS")
                .font(TokenDeskTextStyle.cardTitle.font)
                .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
                .padding(.horizontal, TokenDeskDesign.Spacing.medium)
                .background(TokenDeskDesign.Palette.surfaceMuted.color)
            ForEach(store.providers) { provider in
                Button {
                    store.selectProvider(provider.id)
                } label: {
                    HStack(spacing: TokenDeskDesign.Spacing.small) {
                        Text(provider.status.symbol)
                            .accessibilityHidden(true)
                        Text(provider.name)
                            .lineLimit(1)
                        Spacer()
                        if provider.status != .connected {
                            Text(provider.status.label)
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                        }
                    }
                }
                .buttonStyle(
                    TokenDeskButtonStyle(isSelected: store.selectedProviderID == provider.id)
                )
                .accessibilityLabel("\(provider.name)，\(provider.status.label)")
                .accessibilityIdentifier("token-provider-\(provider.id)")
            }
            Spacer(minLength: 0)
        }
        .background(TokenDeskDesign.Palette.paper.color)
        .overlay {
            Rectangle().stroke(TokenDeskDesign.Palette.ink.color, lineWidth: 2)
        }
    }

    private func tokenDetails(_ snapshot: TokenDashboardSnapshot) -> some View {
        VStack(spacing: TokenDeskDesign.Spacing.small) {
            HStack(spacing: TokenDeskDesign.Spacing.small) {
                MetricTile(label: "输入 TOKEN", value: compact(snapshot.inputTokens))
                MetricTile(label: "输出 TOKEN", value: compact(snapshot.outputTokens))
                MetricTile(label: "费用", value: snapshot.cost, detail: snapshot.costSource)
                MetricTile(label: "余额", value: snapshot.balance, detail: "未知不显示为 0")
            }
            .frame(height: 104)

            TokenUsageChart(snapshot: snapshot, range: store.selectedRange)

            HStack(spacing: 0) {
                footerMetric("最常用模型", snapshot.mostUsedModel)
                footerMetric("缓存命中率", snapshot.cacheHitRate)
                footerMetric("月度预算", snapshot.monthlyBudget)
            }
            .frame(height: 70)
            .overlay {
                Rectangle().stroke(TokenDeskDesign.Palette.ink.color, lineWidth: 2)
            }
        }
    }

    private func footerMetric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: TokenDeskDesign.Spacing.extraSmall) {
            Text(label).font(TokenDeskTextStyle.auxiliary.font)
            Text(value).font(TokenDeskTextStyle.body.font).bold().lineLimit(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(.horizontal, TokenDeskDesign.Spacing.medium)
        .overlay(alignment: .trailing) {
            Rectangle().fill(TokenDeskDesign.Palette.ink.color).frame(width: 1)
        }
        .accessibilityElement(children: .combine)
    }

    private func compact(_ value: Int64) -> String {
        if value >= 1_000_000 {
            return String(format: "%.2fM", Double(value) / 1_000_000)
        }
        if value >= 1_000 {
            return String(format: "%.1fK", Double(value) / 1_000)
        }
        return value.formatted()
    }
}

private struct TokenUsageChart: View {
    let snapshot: TokenDashboardSnapshot
    let range: TokenTimeRange

    var body: some View {
        VStack(alignment: .leading, spacing: TokenDeskDesign.Spacing.small) {
            HStack {
                Text("\(snapshot.providerName) · \(range.accessibilityDescription)")
                    .font(TokenDeskTextStyle.cardTitle.font)
                Spacer()
                Text("■ 输入   ▧ 输出")
                    .font(TokenDeskTextStyle.auxiliary.font)
            }

            Chart(snapshot.buckets) { bucket in
                BarMark(
                    x: .value("时间", bucket.label),
                    y: .value("输入", bucket.input)
                )
                .foregroundStyle(TokenDeskDesign.Palette.ink.color)
                .position(by: .value("类型", "输入"))

                BarMark(
                    x: .value("时间", bucket.label),
                    y: .value("输出", bucket.output)
                )
                .foregroundStyle(TokenDeskDesign.Palette.surfaceMid.color)
                .position(by: .value("类型", "输出"))
            }
            .chartForegroundStyleScale([
                "输入": TokenDeskDesign.Palette.ink.color,
                "输出": TokenDeskDesign.Palette.surfaceMid.color,
            ])
            .chartLegend(.hidden)
            .chartYAxis {
                AxisMarks(position: .leading)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Token 使用趋势图")
            .accessibilityValue(snapshot.chartSummary)

            Text("图表摘要：\(snapshot.chartSummary)")
                .font(TokenDeskTextStyle.auxiliary.font)
                .lineLimit(1)
        }
        .padding(TokenDeskDesign.Spacing.medium)
        .frame(maxHeight: .infinity)
        .background(TokenDeskDesign.Palette.paper.color)
        .overlay {
            Rectangle().stroke(TokenDeskDesign.Palette.ink.color, lineWidth: 2)
        }
    }
}
