import SwiftUI
import TokenDeskDesign

/// Fixed 1280×720 application shell shared by all top-level pages.
public struct TokenDeskAppShell: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var router: AppRouter
    @State private var clock: DashboardClock
    @State private var dashboardStore: DashboardStore
    @State private var settingsStore: SettingsStore

    /// Creates an application shell with injectable state for tests and previews.
    @MainActor
    public init(
        router: AppRouter = AppRouter(),
        clock: DashboardClock = DashboardClock(),
        dashboardStore: DashboardStore = DashboardStore(),
        settingsStore: SettingsStore = SettingsStore()
    ) {
        _router = State(initialValue: router)
        _clock = State(initialValue: clock)
        _dashboardStore = State(initialValue: dashboardStore)
        _settingsStore = State(initialValue: settingsStore)
    }

    /// The header and current route content, clipped to the design canvas.
    public var body: some View {
        VStack(spacing: 0) {
            AppHeader(router: router, dashboardStore: dashboardStore) {
                await dashboardStore.refresh(location: settingsStore.resolvedLocation)
            }
            routeContent
        }
        .frame(width: TokenDeskDesign.Canvas.width, height: TokenDeskDesign.Canvas.height)
        .background(TokenDeskDesign.Palette.surfaceMid.color)
        .foregroundStyle(TokenDeskDesign.Palette.ink.color)
        .clipped()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("app-shell-canvas")
        .task {
            clock.start()
            await settingsStore.prepareWeatherLocation()
            await dashboardStore.start(location: settingsStore.resolvedLocation)
        }
        .task(id: pollingTaskID) {
            guard scenePhase == .active else { return }
            await dashboardStore.runPolling(
                location: settingsStore.resolvedLocation,
                weatherRefreshMinutes: settingsStore.preferences.weatherRefreshMinutes
            )
        }
        .onDisappear {
            clock.stop()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                clock.resume()
                Task {
                    await dashboardStore.refresh(location: settingsStore.resolvedLocation)
                }
            } else {
                clock.stop()
            }
        }
    }

    @ViewBuilder
    private var routeContent: some View {
        Group {
            switch router.route {
            case .overview:
                OverviewPage(state: dashboardStore.overviewState, clock: clock)
            case .plans:
                PlansPage(
                    state: dashboardStore.plansState,
                    capabilityStatuses: dashboardStore.capabilityStatuses
                )
            case .tokens:
                TokensPage(store: dashboardStore.tokensStore)
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

    private var pollingTaskID: String {
        let locationKey = settingsStore.resolvedLocation?.key ?? "no-weather-location"
        return "\(scenePhase)-\(settingsStore.preferences.weatherRefreshMinutes)-\(locationKey)"
    }
}
