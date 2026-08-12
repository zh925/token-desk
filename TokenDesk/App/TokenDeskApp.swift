import SwiftUI
import TokenDeskFeatures
import TokenDeskPlatform

@main
@MainActor
struct TokenDeskApp: App {
    @StateObject private var displayController = DisplayController()
    @State private var clock: DashboardClock
    @State private var settingsStore: SettingsStore

    init() {
        let preferencesStore = UserDefaultsSettingsPreferencesStore()
        let preferences = preferencesStore.load()
        _clock = State(
            initialValue: DashboardClock(
                timeZoneOverrideIdentifier: preferences.timeZoneOverrideIdentifier
            )
        )
        _settingsStore = State(
            initialValue: SettingsStore(
                preferencesStore: preferencesStore,
                locationService: CoreLocationService(),
                notificationService: NotificationService(),
                launchAtLoginService: LaunchAtLoginService(),
                exportService: SavePanelHistoryExportService()
            )
        )
    }

    var body: some Scene {
        WindowGroup {
            DisplayCanvas {
                ContentView(clock: clock, settingsStore: settingsStore)
            }
            .background(DisplayWindowAttachment(controller: displayController))
            .onAppear {
                displayController.start()
            }
            .onDisappear {
                displayController.stop()
            }
        }
        .defaultSize(width: 1_280, height: 720)
    }
}
