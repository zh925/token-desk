import SwiftUI
import TokenDeskDesign

/// Fixed 1280×720 application shell shared by all top-level pages.
public struct TokenDeskAppShell: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var router: AppRouter
    @State private var clock: DashboardClock
    @State private var tokensStore: TokensPageStore

    /// Creates an application shell with injectable state for tests and previews.
    @MainActor
    public init(
        router: AppRouter = AppRouter(),
        clock: DashboardClock = DashboardClock(),
        tokensStore: TokensPageStore = TokensPageStore()
    ) {
        _router = State(initialValue: router)
        _clock = State(initialValue: clock)
        _tokensStore = State(initialValue: tokensStore)
    }

    /// The header and current route content, clipped to the design canvas.
    public var body: some View {
        VStack(spacing: 0) {
            AppHeader(router: router)
            routeContent
                .id(router.route)
        }
        .frame(width: TokenDeskDesign.Canvas.width, height: TokenDeskDesign.Canvas.height)
        .background(TokenDeskDesign.Palette.surfaceMid.color)
        .foregroundStyle(TokenDeskDesign.Palette.ink.color)
        .clipped()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("app-shell-canvas")
        .task {
            clock.start()
        }
        .onDisappear {
            clock.stop()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                clock.resume()
            }
        }
    }

    @ViewBuilder
    private var routeContent: some View {
        Group {
            switch router.route {
            case .overview:
                OverviewPage(clock: clock)
            case .plans:
                PlansPage()
            case .tokens:
                TokensPage(store: tokensStore)
            case .settings:
                SettingsPlaceholder(clock: clock)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            TokenDeskPatternFill(
                .dots,
                foreground: TokenDeskDesign.Palette.surfaceMid.color,
                background: TokenDeskDesign.Palette.surfaceMuted.color
            )
        }
    }
}

private struct SettingsPlaceholder: View {
    @Bindable var clock: DashboardClock

    var body: some View {
        VStack(spacing: TokenDeskDesign.Spacing.large) {
            PageHeading(
                title: "设置页面",
                subtitle: "所有配置均从顶部唯一入口进入",
                code: "SETTINGS · SINGLE ENTRY"
            )
            TokenDeskPanel("时间与时区") {
                VStack(alignment: .leading, spacing: TokenDeskDesign.Spacing.large) {
                    Text("当前：\(clock.presentation.timeZone)")
                        .font(TokenDeskTextStyle.cardTitle.font)
                    Text("默认跟随 macOS；可选择常用时区覆盖。")
                        .font(TokenDeskTextStyle.body.font)
                    HStack(spacing: TokenDeskDesign.Spacing.small) {
                        timezoneButton("跟随系统", identifier: nil)
                        timezoneButton("上海", identifier: "Asia/Shanghai")
                        timezoneButton("东京", identifier: "Asia/Tokyo")
                        timezoneButton("洛杉矶", identifier: "America/Los_Angeles")
                    }
                    Spacer()
                    Text("Provider、天气、显示、通知、数据与导出将在后续批次接线。")
                        .font(TokenDeskTextStyle.body.font)
                }
            }
        }
        .padding(TokenDeskDesign.Spacing.extraLarge)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("设置页面")
        .accessibilityIdentifier("page-settings")
    }

    private func timezoneButton(_ title: String, identifier: String?) -> some View {
        Button(title) {
            clock.setTimeZoneOverride(identifier: identifier)
        }
        .buttonStyle(
            TokenDeskButtonStyle(isSelected: clock.timeZoneOverrideIdentifier == identifier)
        )
    }
}
