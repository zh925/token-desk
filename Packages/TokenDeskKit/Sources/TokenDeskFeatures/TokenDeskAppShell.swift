import SwiftUI
import TokenDeskDesign

/// Fixed 1280×720 application shell shared by all top-level pages.
public struct TokenDeskAppShell: View {
    @State private var router: AppRouter

    /// Creates an application shell with an injectable router for tests and previews.
    @MainActor
    public init(router: AppRouter = AppRouter()) {
        _router = State(initialValue: router)
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
    }

    private var routeContent: some View {
        RoutePage(route: router.route)
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

private struct RoutePage: View {
    let route: AppRoute

    var body: some View {
        VStack(alignment: .leading, spacing: TokenDeskDesign.Spacing.large) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: TokenDeskDesign.Spacing.extraSmall) {
                    Text("\(route.title)页面")
                        .font(TokenDeskTextStyle.pageTitle.font)
                    Text(subtitle)
                        .font(TokenDeskTextStyle.body.font)
                }

                Spacer()

                Text(routeCode)
                    .font(TokenDeskTextStyle.auxiliary.font)
            }

            HStack(spacing: TokenDeskDesign.Spacing.large) {
                TokenDeskPanel(panelTitle) {
                    VStack(alignment: .leading, spacing: TokenDeskDesign.Spacing.large) {
                        Text(primaryValue)
                            .font(TokenDeskTextStyle.primaryMetric.font)
                        Text(primaryDescription)
                            .font(TokenDeskTextStyle.body.font)
                        TokenDeskStatusBadge(status)
                    }
                }

                TokenDeskPanel("应用壳层") {
                    VStack(alignment: .leading, spacing: TokenDeskDesign.Spacing.medium) {
                        shellRow("画布", value: "1280 × 720")
                        shellRow("导航", value: "鼠标 / 键盘")
                        shellRow("状态", value: status.label)
                        Divider()
                        Text(settingsExplanation)
                            .font(TokenDeskTextStyle.body.font)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(width: 360)
            }
            .frame(maxHeight: .infinity)
        }
        .padding(TokenDeskDesign.Spacing.extraLarge)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("page-\(route.rawValue)")
    }

    private func shellRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(TokenDeskTextStyle.body.font)
            Spacer()
            Text(value)
                .font(TokenDeskTextStyle.auxiliary.font)
        }
    }

    private var subtitle: String {
        switch route {
        case .overview: "时间、天气、套餐与费用摘要"
        case .plans: "套餐窗口保持独立口径"
        case .tokens: "Token、费用与余额分别展示"
        case .settings: "所有配置均从顶部唯一入口进入"
        }
    }

    private var routeCode: String {
        switch route {
        case .overview: "ROUTE 1 / OVERVIEW"
        case .plans: "ROUTE 2 / PLANS"
        case .tokens: "ROUTE 3 / TOKENS"
        case .settings: "SETTINGS / SINGLE ENTRY"
        }
    }

    private var panelTitle: String {
        switch route {
        case .overview: "今日概览"
        case .plans: "套餐状态"
        case .tokens: "Token 用量"
        case .settings: "设置中心"
        }
    }

    private var primaryValue: String {
        switch route {
        case .overview: "10:09"
        case .plans: "72%"
        case .tokens: "1.82M"
        case .settings: "5 GROUPS"
        }
    }

    private var primaryDescription: String {
        switch route {
        case .overview: "核心信息保持三秒可读。"
        case .plans: "仅表示当前套餐窗口使用比例。"
        case .tokens: "输入、输出与缓存 Token 不混算。"
        case .settings: "Providers、天气、显示、通知、数据与导出集中管理。"
        }
    }

    private var status: TokenDeskStatus {
        switch route {
        case .overview: .connected
        case .plans: .stale
        case .tokens: .syncing
        case .settings: .connected
        }
    }

    private var settingsExplanation: String {
        switch route {
        case .overview, .settings: "设置按钮只存在于全局头部，内容区不复制配置入口。"
        case .plans: "套餐页只展示额度状态，不提供添加或配置入口。"
        case .tokens: "Token 页只展示用量与费用，不提供添加或配置入口。"
        }
    }
}
