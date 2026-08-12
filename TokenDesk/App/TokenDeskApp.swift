import AppKit
import SwiftUI
import TokenDeskConnectors
import TokenDeskCore
import TokenDeskData
import TokenDeskDesign
import TokenDeskFeatures
import TokenDeskPlatform

@main
@MainActor
struct TokenDeskApp: App {
    @StateObject private var displayController: DisplayController
    @State private var clock: DashboardClock
    @State private var dashboardStore: DashboardStore
    @State private var settingsStore: SettingsStore
    private let uiTestConfiguration: UITestConfiguration

    init() {
        let uiTestConfiguration = UITestConfiguration(arguments: ProcessInfo.processInfo.arguments)
        self.uiTestConfiguration = uiTestConfiguration
        let displayController = DisplayController()
        _displayController = StateObject(wrappedValue: displayController)
        let preferencesStore = uiTestConfiguration.makePreferencesStore()
        let preferences = uiTestConfiguration.preferences ?? preferencesStore.load()
        if uiTestConfiguration.isEnabled {
            try? preferencesStore.save(preferences)
        }
        _clock = State(
            initialValue: uiTestConfiguration.makeClock(preferences: preferences)
        )
        let providerServices = ApplicationProviderServices()
        let dashboardStore = DashboardStore(dataProvider: providerServices)
        if ProcessInfo.processInfo.arguments.contains("--app-review-demo") {
            dashboardStore.activateAppReviewDemo(.representative)
        }
        _dashboardStore = State(initialValue: dashboardStore)
        if uiTestConfiguration.isEnabled {
            _settingsStore = State(
                initialValue: SettingsStore(preferencesStore: preferencesStore)
            )
        } else {
            _settingsStore = State(
                initialValue: SettingsStore(
                    preferencesStore: preferencesStore,
                    locationService: CoreLocationService(),
                    notificationService: NotificationService(),
                    launchAtLoginService: LaunchAtLoginService(),
                    displayService: displayController,
                    exportService: SavePanelHistoryExportService(),
                    historyDataService: providerServices,
                    providerManager: providerServices,
                    connectionTester: providerServices
                )
            )
        }
    }

    var body: some Scene {
        WindowGroup {
            UITestEnvironment(configuration: uiTestConfiguration) {
                DisplayCanvas {
                    ContentView(
                        clock: clock,
                        dashboardStore: dashboardStore,
                        settingsStore: settingsStore
                    )
                }
                .modifier(
                    DisplayControllerAttachment(
                        controller: displayController,
                        isEnabled: !uiTestConfiguration.isEnabled
                    )
                )
            }
        }
        .defaultSize(width: 1_280, height: 720)
    }
}

private struct DisplayControllerAttachment: ViewModifier {
    @ObservedObject var controller: DisplayController
    let isEnabled: Bool

    func body(content: Content) -> some View {
        if isEnabled {
            content
                .background(DisplayWindowAttachment(controller: controller))
                .onAppear { controller.start() }
                .onDisappear { controller.stop() }
        } else {
            content.background(UITestWindowAttachment())
        }
    }
}

private struct UITestWindowAttachment: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        UITestWindowAttachmentView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

@MainActor
private final class UITestWindowAttachmentView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        Task { @MainActor [weak window] in
            await Task.yield()
            guard let window, let screen = window.screen ?? NSScreen.main else { return }
            window.styleMask = [.borderless]
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.isMovable = false
            let designSize = NSSize(width: 1_280, height: 720)
            let availableFrame = screen.visibleFrame.insetBy(dx: 8, dy: 8)
            let scale = min(
                1,
                availableFrame.width / designSize.width,
                availableFrame.height / designSize.height
            )
            let targetSize = NSSize(
                width: designSize.width * scale,
                height: designSize.height * scale
            )
            let targetFrame = NSRect(
                // Hosted runners can expose less than the 1,280×720 design size. Keep the
                // fixed canvas uniformly scaled inside the interactive desktop so trailing
                // controls and screenshot pixels are not clipped by the window or Dock.
                x: availableFrame.midX - targetSize.width / 2,
                y: availableFrame.midY - targetSize.height / 2,
                width: targetSize.width,
                height: targetSize.height
            )
            window.setFrame(targetFrame, display: true, animate: false)
        }
    }
}

private struct UITestConfiguration {
    let isEnabled: Bool
    let forcesReduceMotion: Bool
    let fixedDate: Date?

    init(arguments: [String]) {
        isEnabled = arguments.contains("--ui-testing")
        forcesReduceMotion = arguments.contains("--ui-test-reduce-motion")
        fixedDate =
            arguments.contains("--ui-test-fixed-clock")
            ? Date(timeIntervalSince1970: 1_735_789_445)
            : nil
    }

    var preferences: SettingsPreferences? {
        guard isEnabled else { return nil }
        return SettingsPreferences(timeZoneOverrideIdentifier: "Asia/Shanghai")
    }

    @MainActor
    func makePreferencesStore() -> UserDefaultsSettingsPreferencesStore {
        guard isEnabled else { return UserDefaultsSettingsPreferencesStore() }
        let suiteName = "app.tokendesk.TokenDesk.ui-tests"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)
        return UserDefaultsSettingsPreferencesStore(defaults: defaults)
    }

    @MainActor
    func makeClock(preferences: SettingsPreferences) -> DashboardClock {
        guard let fixedDate else {
            return DashboardClock(
                timeZoneOverrideIdentifier: preferences.timeZoneOverrideIdentifier
            )
        }
        return DashboardClock(
            now: fixedDate,
            timeZoneOverrideIdentifier: preferences.timeZoneOverrideIdentifier,
            nowProvider: { fixedDate }
        )
    }
}

private struct UITestEnvironment<Content: View>: View {
    let configuration: UITestConfiguration
    let content: Content

    init(configuration: UITestConfiguration, @ViewBuilder content: () -> Content) {
        self.configuration = configuration
        self.content = content()
    }

    var body: some View {
        if configuration.isEnabled && configuration.forcesReduceMotion {
            content
                .environment(\.tokenDeskReduceMotionOverride, true)
                .overlay(alignment: .bottomTrailing) {
                    reduceMotionProbe
                }
        } else {
            content
        }
    }

    private var reduceMotionProbe: some View {
        Text("Reduce Motion enabled")
            .accessibilityIdentifier("ui-test-reduce-motion-enabled")
            .frame(width: 1, height: 1)
            .opacity(0.01)
    }
}

/// Lazily opens SQLite away from the main actor before serving Provider settings work.
private actor ApplicationProviderServices: ProviderAccountManaging, ProviderConnectionTesting,
    HistoryDataServicing, DashboardDataProviding
{
    private let credentialStore = KeychainCredentialStore()
    private var manager: GRDBProviderAccountManager?
    private var tester: OfficialProviderConnectionTester?
    private var historyDataService: GRDBHistoryDataService?
    private var usageRepository: GRDBUsageRepository?
    private var weatherRepository: GRDBWeatherRepository?
    private var pricingCatalog: GRDBPricingCatalog?

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

    func storageSnapshot() async throws -> HistoryStorageSnapshot {
        try await services().historyDataService.storageSnapshot()
    }

    func makeExport(
        format: HistoryExportFormat,
        request: HistoryExportRequest
    ) async throws -> HistoryExportPayload {
        try await services().historyDataService.makeExport(format: format, request: request)
    }

    func clearHistory(scope: HistoryClearScope) async throws -> HistoryClearReport {
        try await services().historyDataService.clearHistory(scope: scope)
    }

    func loadCachedDashboardData() async throws -> DashboardDataSnapshot {
        let services = try services()
        let configurations = try await services.manager.configurations().filter(\.isEnabled)
        let now = Date()
        let interval = DateInterval(start: now.addingTimeInterval(-35 * 86_400), end: now)
        var plans: [PlanWindow] = []
        var usage: [TokenUsageBucket] = []
        var costs: [CostSnapshot] = []
        var balances: [BalanceSnapshot] = []
        for configuration in configurations {
            let account = try configuration.accountReference
            plans += try services.usageRepository.cachedPlans(for: account, now: now)
            balances += try services.usageRepository.cachedBalances(for: account)
            costs += try services.usageRepository.cachedCosts(for: account, in: interval)
            for granularity in [UsageGranularity.minute, .hour, .day] {
                usage += try services.usageRepository.cachedUsage(
                    for: account,
                    in: interval,
                    granularity: granularity
                )
            }
        }
        let weather = try services.weatherRepository.latestCachedWeather(
            now: now,
            staleAfter: WeatherSyncCoordinator.staleAfter
        )
        return DashboardDataSnapshot(
            configurations: configurations,
            plans: plans,
            usage: usage,
            costs: costs,
            balances: balances,
            weather: weather
        )
    }

    func refreshDashboardData(
        location: WeatherLocation?,
        scope: DashboardRefreshScope
    ) async -> DashboardRefreshResult {
        let startedAt = Date()
        do {
            let services = try services()
            let configurations = try await services.manager.configurations().filter(\.isEnabled)
            let grouped = Dictionary(grouping: configurations, by: \.providerID)
            var connectors: [any ProviderConnector] = []
            var accountsByProvider: [ProviderID: [AccountReference]] = [:]
            for providerID in grouped.keys.sorted(by: { $0.rawValue < $1.rawValue }) {
                guard let values = grouped[providerID], let configuration = values.first else {
                    continue
                }
                connectors.append(try makeConnector(for: configuration, services: services))
                accountsByProvider[providerID] = try values.map { try $0.accountReference }
            }
            let registry = try ProviderConnectorRegistry(connectors: connectors)
            let report = await SyncCoordinator(
                registry: registry,
                repository: services.usageRepository
            ).manualSync(
                accountsByProvider: accountsByProvider,
                interval: DateInterval(
                    start: startedAt.addingTimeInterval(-35 * 86_400),
                    end: startedAt
                ),
                capabilities: scope.providerCapabilities
            )
            let weatherResult: WeatherSyncResult?
            if scope.contains(.weather), let location {
                do {
                    weatherResult = try await WeatherSyncCoordinator(
                        service: OpenMeteoConnector(),
                        repository: services.weatherRepository
                    ).sync(location: location)
                } catch is CancellationError {
                    weatherResult = WeatherSyncResult(
                        state: .unavailable,
                        snapshot: nil,
                        failure: .cancelled
                    )
                } catch {
                    weatherResult = WeatherSyncResult(
                        state: .unavailable,
                        snapshot: nil,
                        failure: .server(statusCode: nil)
                    )
                }
            } else {
                weatherResult = nil
            }
            return DashboardRefreshResult(
                providerReport: report,
                weatherResult: weatherResult
            )
        } catch {
            return DashboardRefreshResult(
                providerReport: SyncReport(
                    startedAt: startedAt,
                    completedAt: Date(),
                    providers: []
                ),
                weatherResult: nil
            )
        }
    }

    private func services() throws -> (
        manager: GRDBProviderAccountManager,
        tester: OfficialProviderConnectionTester,
        historyDataService: GRDBHistoryDataService,
        usageRepository: GRDBUsageRepository,
        weatherRepository: GRDBWeatherRepository,
        pricingCatalog: GRDBPricingCatalog
    ) {
        if let manager, let tester, let historyDataService, let usageRepository,
            let weatherRepository, let pricingCatalog
        {
            return (
                manager, tester, historyDataService, usageRepository, weatherRepository,
                pricingCatalog
            )
        }
        let database = try TokenDeskDatabase.openApplicationDatabase()
        let usageRepository = GRDBUsageRepository(writer: database)
        let weatherRepository = GRDBWeatherRepository(writer: database)
        let pricingCatalog = GRDBPricingCatalog(writer: database)
        let manager = GRDBProviderAccountManager(
            writer: database,
            credentialStore: credentialStore
        )
        let tester = OfficialProviderConnectionTester(
            credentialStore: credentialStore,
            localUsageRepository: usageRepository
        )
        let historyDataService = GRDBHistoryDataService(writer: database)
        self.manager = manager
        self.tester = tester
        self.historyDataService = historyDataService
        self.usageRepository = usageRepository
        self.weatherRepository = weatherRepository
        self.pricingCatalog = pricingCatalog
        return (
            manager, tester, historyDataService, usageRepository, weatherRepository,
            pricingCatalog
        )
    }

    private func makeConnector(
        for configuration: ProviderAccountConfiguration,
        services: (
            manager: GRDBProviderAccountManager,
            tester: OfficialProviderConnectionTester,
            historyDataService: GRDBHistoryDataService,
            usageRepository: GRDBUsageRepository,
            weatherRepository: GRDBWeatherRepository,
            pricingCatalog: GRDBPricingCatalog
        )
    ) throws -> any ProviderConnector {
        let type = configuration.providerType.rawValue.lowercased()
        let capabilities: Set<ProviderCapability> =
            switch type {
            case "openai", "anthropic": [.usage, .cost]
            case "deepseek", "kimi": [.usage, .cost, .balance, .localEstimate]
            case "openrouter": [.balance]
            case "glm", "minimax", "gemini": [.usage, .cost, .localEstimate]
            default: []
            }
        let descriptor = try ProviderDescriptor(
            id: configuration.providerID,
            type: configuration.providerType,
            displayName: configuration.providerDisplayName,
            capabilities: ProviderCapabilities(capabilities)
        )
        switch type {
        case "openai":
            return OpenAIConnector(descriptor: descriptor, credentialStore: credentialStore)
        case "anthropic":
            return AnthropicConnector(descriptor: descriptor, credentialStore: credentialStore)
        case "deepseek":
            return DeepSeekConnector(
                descriptor: descriptor,
                credentialStore: credentialStore,
                localUsageRepository: services.usageRepository,
                pricingCatalog: services.pricingCatalog,
                estimatedCostCurrency: try CurrencyCode(rawValue: "CNY")
            )
        case "kimi":
            return KimiConnector(
                descriptor: descriptor,
                credentialStore: credentialStore,
                localUsageRepository: services.usageRepository,
                balanceCurrency: try CurrencyCode(rawValue: "CNY"),
                pricingCatalog: services.pricingCatalog,
                estimatedCostCurrency: try CurrencyCode(rawValue: "CNY")
            )
        case "openrouter":
            return OpenRouterConnector(
                descriptor: descriptor,
                credentialStore: credentialStore,
                creditCurrency: try CurrencyCode(rawValue: "USD")
            )
        case "glm":
            return GLMConnector(
                descriptor: descriptor,
                credentialStore: credentialStore,
                localUsageRepository: services.usageRepository,
                pricingCatalog: services.pricingCatalog,
                estimatedCostCurrency: try CurrencyCode(rawValue: "CNY")
            )
        case "minimax":
            return MiniMaxConnector(
                descriptor: descriptor,
                credentialStore: credentialStore,
                localUsageRepository: services.usageRepository,
                pricingCatalog: services.pricingCatalog,
                estimatedCostCurrency: try CurrencyCode(rawValue: "CNY")
            )
        case "gemini":
            return GeminiConnector(
                descriptor: descriptor,
                credentialStore: credentialStore,
                localUsageRepository: services.usageRepository,
                pricingCatalog: services.pricingCatalog,
                estimatedCostCurrency: try CurrencyCode(rawValue: "USD")
            )
        default:
            return CodexP0Connector(descriptor: descriptor)
        }
    }
}
