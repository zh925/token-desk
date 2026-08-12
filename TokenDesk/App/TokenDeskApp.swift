import SwiftUI
import TokenDeskConnectors
import TokenDeskCore
import TokenDeskData
import TokenDeskFeatures
import TokenDeskPlatform

@main
@MainActor
struct TokenDeskApp: App {
    @StateObject private var displayController: DisplayController
    @State private var clock: DashboardClock
    @State private var settingsStore: SettingsStore

    init() {
        let displayController = DisplayController()
        _displayController = StateObject(wrappedValue: displayController)
        let preferencesStore = UserDefaultsSettingsPreferencesStore()
        let preferences = preferencesStore.load()
        _clock = State(
            initialValue: DashboardClock(
                timeZoneOverrideIdentifier: preferences.timeZoneOverrideIdentifier
            )
        )
        let providerServices = ApplicationProviderServices()
        _settingsStore = State(
            initialValue: SettingsStore(
                preferencesStore: preferencesStore,
                locationService: CoreLocationService(),
                notificationService: NotificationService(),
                launchAtLoginService: LaunchAtLoginService(),
                displayService: displayController,
                exportService: SavePanelHistoryExportService(),
                providerManager: providerServices,
                connectionTester: providerServices
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

/// Lazily opens SQLite away from the main actor before serving Provider settings work.
private actor ApplicationProviderServices: ProviderAccountManaging, ProviderConnectionTesting {
    private let credentialStore = KeychainCredentialStore()
    private var manager: GRDBProviderAccountManager?
    private var tester: OfficialProviderConnectionTester?

    func configurations() async throws -> [ProviderAccountConfiguration] {
        try await services().manager.configurations()
    }

    func save(
        _ draft: ProviderAccountDraft,
        replacingCredential: Credential?
    ) async throws -> ProviderAccountConfiguration {
        try await services().manager.save(draft, replacingCredential: replacingCredential)
    }

    func setEnabled(_ isEnabled: Bool, accountID: AccountID) async throws {
        try await services().manager.setEnabled(isEnabled, accountID: accountID)
    }

    func delete(accountID: AccountID, history: ProviderHistoryDisposition) async throws {
        try await services().manager.delete(accountID: accountID, history: history)
    }

    func testConnection(
        for configuration: ProviderAccountConfiguration
    ) async throws -> ProviderConnectionTestResult {
        try await services().tester.testConnection(for: configuration)
    }

    private func services() throws -> (
        manager: GRDBProviderAccountManager,
        tester: OfficialProviderConnectionTester
    ) {
        if let manager, let tester { return (manager, tester) }
        let database = try TokenDeskDatabase.openApplicationDatabase()
        let manager = GRDBProviderAccountManager(
            writer: database,
            credentialStore: credentialStore
        )
        let tester = OfficialProviderConnectionTester(
            credentialStore: credentialStore,
            localUsageRepository: GRDBUsageRepository(writer: database)
        )
        self.manager = manager
        self.tester = tester
        return (manager, tester)
    }
}
