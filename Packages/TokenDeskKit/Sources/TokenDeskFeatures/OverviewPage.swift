import SwiftUI
import TokenDeskDesign

/// Time, weather, primary plan, and provider summaries for ambient viewing.
public struct OverviewPage: View {
    private let state: DashboardContentState<OverviewSnapshot>
    @Bindable private var clock: DashboardClock

    /// Creates an overview from a render state and independently observable clock.
    @MainActor
    public init(
        state: DashboardContentState<OverviewSnapshot> = .loaded(DashboardFixtures.overview),
        clock: DashboardClock
    ) {
        self.state = state
        self.clock = clock
    }

    /// Fixed overview layout optimized for the 1280×720 canvas.
    public var body: some View {
        DashboardStateView(state: state) { snapshot in
            HStack(spacing: TokenDeskDesign.Spacing.large) {
                VStack(spacing: TokenDeskDesign.Spacing.large) {
                    clockPanel
                    weatherPanel(snapshot.weather)
                }
                .frame(width: 374)

                usagePanel(snapshot)
            }
        }
        .padding(20)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("总览页面")
        .accessibilityIdentifier("page-overview")
    }

    private var clockPanel: some View {
        TokenDeskPanel("当前时间") {
            let presentation = clock.presentation
            VStack(alignment: .leading, spacing: TokenDeskDesign.Spacing.small) {
                Text(presentation.date)
                    .font(TokenDeskTextStyle.body.font)
                Text(presentation.time)
                    .font(TokenDeskTextStyle.clock.font)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .contentTransition(.numericText())
                    .accessibilityIdentifier("overview-clock")
                Text("上海 · \(presentation.timeZone)")
                    .font(TokenDeskTextStyle.body.font)
            }
        }
        .frame(height: 248)
    }

    private func weatherPanel(_ weather: WeatherSnapshot) -> some View {
        TokenDeskPanel("\(weather.city)天气 · MOCK") {
            VStack(alignment: .leading, spacing: TokenDeskDesign.Spacing.small) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: TokenDeskDesign.Spacing.extraSmall) {
                        Text("\(weather.temperature)°")
                            .font(TokenDeskTextStyle.primaryMetric.font)
                        Text("\(weather.condition) · 体感 \(weather.feelsLike)°")
                            .font(TokenDeskTextStyle.body.font)
                        Text("降雨 \(weather.precipitationPercent)% · 湿度 \(weather.humidityPercent)%")
                            .font(TokenDeskTextStyle.auxiliary.font)
                    }
                    Spacer()
                    Text("☀")
                        .font(.system(size: 46))
                        .accessibilityHidden(true)
                }
                Divider()
                HStack(spacing: 0) {
                    ForEach(weather.hours) { hour in
                        VStack(spacing: 3) {
                            Text(hour.label)
                            Text(hour.symbol).font(.system(size: 20))
                            Text("\(hour.temperature)°").bold()
                        }
                        .font(TokenDeskTextStyle.auxiliary.font)
                        .frame(maxWidth: .infinity)
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    private func usagePanel(_ snapshot: OverviewSnapshot) -> some View {
        TokenDeskPanel("今日用量 · MOCK / DEMO") {
            VStack(spacing: TokenDeskDesign.Spacing.medium) {
                Text("总览页面")
                    .font(TokenDeskTextStyle.auxiliary.font)
                    .frame(maxWidth: .infinity, alignment: .leading)
                planSummary(snapshot.primaryPlan)
                ForEach(snapshot.providers) { provider in
                    providerSummary(provider)
                }
                Spacer(minLength: 0)
                Text("套餐额度、Token、费用与余额保持独立口径")
                    .font(TokenDeskTextStyle.auxiliary.font)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func planSummary(_ plan: PlanWindowSnapshot) -> some View {
        HStack(spacing: TokenDeskDesign.Spacing.large) {
            VStack(alignment: .leading, spacing: TokenDeskDesign.Spacing.extraSmall) {
                Text(plan.name)
                    .font(TokenDeskTextStyle.cardTitle.font)
                Text(plan.window)
                    .font(TokenDeskTextStyle.body.font)
                Text(plan.source.rawValue)
                    .font(TokenDeskTextStyle.auxiliary.font)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: TokenDeskDesign.Spacing.extraSmall) {
                Text("\(plan.usedPercent)%")
                    .font(TokenDeskTextStyle.primaryMetric.font)
                Text(plan.resetDescription)
                    .font(TokenDeskTextStyle.auxiliary.font)
            }
        }
        .padding(TokenDeskDesign.Spacing.large)
        .frame(height: 142)
        .background(TokenDeskDesign.Palette.surfaceMuted.color)
        .overlay {
            Rectangle().stroke(TokenDeskDesign.Palette.ink.color, lineWidth: 2)
        }
        .accessibilityElement(children: .combine)
    }

    private func providerSummary(_ provider: ProviderSummarySnapshot) -> some View {
        HStack(spacing: TokenDeskDesign.Spacing.medium) {
            VStack(alignment: .leading, spacing: TokenDeskDesign.Spacing.extraSmall) {
                Text(provider.name)
                    .font(TokenDeskTextStyle.cardTitle.font)
                TokenDeskStatusBadge(provider.status)
            }
            .frame(width: 180, alignment: .leading)
            Divider()
            summaryValue("TOKEN", provider.usage)
            Divider()
            summaryValue("费用", provider.cost)
            Divider()
            summaryValue("余额", provider.balance)
        }
        .padding(TokenDeskDesign.Spacing.medium)
        .frame(height: 118)
        .overlay {
            Rectangle().stroke(TokenDeskDesign.Palette.ink.color, lineWidth: 2)
        }
    }

    private func summaryValue(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: TokenDeskDesign.Spacing.small) {
            Text(label).font(TokenDeskTextStyle.auxiliary.font)
            Text(value)
                .font(TokenDeskTextStyle.body.font)
                .bold()
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
