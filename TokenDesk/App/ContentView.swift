import AppKit
import SwiftUI
import TokenDeskFeatures

struct ContentView: View {
    @State private var clock: DashboardClock
    @State private var dashboardStore: DashboardStore
    @State private var settingsStore: SettingsStore

    @MainActor
    init(
        clock: DashboardClock = DashboardClock(),
        dashboardStore: DashboardStore = DashboardStore(),
        settingsStore: SettingsStore = SettingsStore()
    ) {
        _clock = State(initialValue: clock)
        _dashboardStore = State(initialValue: dashboardStore)
        _settingsStore = State(initialValue: settingsStore)
    }

    var body: some View {
        TokenDeskAppShell(
            clock: clock,
            dashboardStore: dashboardStore,
            settingsStore: settingsStore
        )
            .onReceive(
                NSWorkspace.shared.notificationCenter.publisher(
                    for: NSWorkspace.didWakeNotification
                )
            ) { _ in
                clock.resume()
            }
    }
}

#Preview {
    ContentView()
        .frame(width: 1280, height: 720)
}
