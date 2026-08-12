import SwiftUI
import TokenDeskDesign

/// Fixed 1280×720 application shell shared by all top-level pages.
public struct TokenDeskAppShell: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var router: AppRouter
    @State private var clock: DashboardClock
    @State private var tokensStore: TokensPageStore
    @State private var settingsStore: SettingsStore

    /// Creates an application shell with injectable state for tests and previews.
    @MainActor
    public init(
        router: AppRouter = AppRouter(),
        clock: DashboardClock = DashboardClock(),
        tokensStore: TokensPageStore = TokensPageStore(),
        settingsStore: SettingsStore = SettingsStore()
    ) {
        _router = State(initialValue: router)
        _clock = State(initialValue: clock)
        _tokensStore = State(initialValue: tokensStore)
        _settingsStore = State(initialValue: settingsStore)
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
                SettingsPage(store: settingsStore, clock: clock)
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
