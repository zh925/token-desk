import SwiftUI
import Testing
import TokenDeskCore
@testable import TokenDeskFeatures

@Test
func featuresModuleNameIsStable() {
    #expect(TokenDeskFeaturesModule.name == "TokenDeskFeatures")
}

@Test @MainActor
func routerStartsAtOverviewAndSupportsPrimaryShortcuts() {
    let router = AppRouter()

    #expect(router.route == .overview)
    #expect(router.selectShortcut("2"))
    #expect(router.route == .plans)
    #expect(router.selectShortcut("3"))
    #expect(router.route == .tokens)
    #expect(router.selectShortcut("1"))
    #expect(router.route == .overview)
}

@Test @MainActor
func unknownShortcutDoesNotChangeRoute() {
    let router = AppRouter(route: .settings)

    #expect(!router.selectShortcut("4"))
    #expect(router.route == .settings)
    #expect(AppRoute.settings.keyboardShortcut == nil)
}

@Test @MainActor
func routeSwitchingStaysWithinInteractionBudget() {
    let router = AppRouter()
    let clock = ContinuousClock()

    let elapsed = clock.measure {
        for _ in 0..<100 {
            router.select(.plans)
            router.select(.tokens)
            router.select(.overview)
        }
    }

    #expect(elapsed < .milliseconds(100))
}

@Test
func dashboardStatesKeepEmptyFailureAndStaleSemanticsDistinct() {
    let snapshot = DashboardFixtures.overview
    let states: [DashboardContentState<OverviewSnapshot>] = [
        .loading,
        .empty(title: "尚无数据", detail: "首次同步后显示"),
        .loaded(snapshot),
        .stale(snapshot, lastUpdated: Date(timeIntervalSince1970: 1_700_000_000)),
        .failed(title: "网络不可用", detail: "稍后自动重试", cached: snapshot),
    ]

    #expect(states.count == 5)
    #expect(states[1] != states[4])
    #expect(states[2] != states[3])
}

@Test @MainActor
func productionDashboardCoversLoadingEmptyAndTrueZero() async throws {
    let now = Date(timeIntervalSince1970: 1_786_500_000)
    let emptyProvider = TestDashboardDataProvider(data: emptyDashboardData(), now: now)
    let emptyStore = DashboardStore(dataProvider: emptyProvider, now: { now })
    #expect(emptyStore.overviewState == .loading)

    await emptyStore.start(location: nil)
    #expect(
        emptyStore.overviewState
            == .empty(
                title: "尚无看板数据",
                detail: "本地缓存为空；配置 Provider 或天气位置后即可同步。"
            )
    )

    let zeroData = try dashboardData(now: now, input: 0, output: 0)
    let zeroStore = DashboardStore(
        dataProvider: TestDashboardDataProvider(data: zeroData, now: now),
        now: { now }
    )
    await zeroStore.start(location: nil)
    guard case .loaded(let snapshot) = zeroStore.tokensStore.contentState else {
        Issue.record("A stored zero must render as loaded data, not an empty state")
        return
    }
    #expect(snapshot.inputTokens == 0)
    #expect(snapshot.outputTokens == 0)
}

@Test @MainActor
func productionDashboardKeepsStaleCachedDataVisible() async throws {
    let now = Date(timeIntervalSince1970: 1_786_500_000)
    let data = try dashboardData(now: now, isStale: true)
    let store = DashboardStore(
        dataProvider: TestDashboardDataProvider(data: data, now: now),
        now: { now }
    )

    await store.start(location: nil)

    guard case .stale(let snapshot, _) = store.tokensStore.contentState else {
        Issue.record("Expected stale production data to remain visible")
        return
    }
    #expect(snapshot.inputTokens == 12)
}

@Test @MainActor
func productionDashboardIsolatesAuthenticationAndOfflineAsPartialData() async throws {
    let now = Date(timeIntervalSince1970: 1_786_500_000)
    let data = try dashboardData(now: now)
    for error in [ConnectorError.authentication, .network] {
        let provider = TestDashboardDataProvider(data: data, now: now, failure: error)
        let store = DashboardStore(dataProvider: provider, now: { now })

        await store.start(location: nil)

        guard case .partial(let snapshot, let issues) = store.tokensStore.contentState else {
            Issue.record("Expected cached values plus a typed partial failure")
            continue
        }
        #expect(snapshot.inputTokens == 12)
        #expect(issues.first?.providerName == "OpenAI Production")
        #expect(
            issues.first?.kind
                == (error == .authentication ? .authentication : .offline)
        )
    }
}

@Test @MainActor
func productionDashboardShowsRateLimitWithoutInventingValues() async throws {
    let now = Date(timeIntervalSince1970: 1_786_500_000)
    let data = try dashboardData(now: now, includeUsage: false)
    let provider = TestDashboardDataProvider(
        data: data,
        now: now,
        failure: .rateLimited(retryAfter: .seconds(60))
    )
    let store = DashboardStore(dataProvider: provider, now: { now })

    await store.start(location: nil)

    guard case .failed(let title, let detail, let cached) = store.tokensStore.contentState else {
        Issue.record("Expected a value-free rate-limit state")
        return
    }
    #expect(title == "OpenAI Production")
    #expect(detail.contains("Retry-After"))
    #expect(cached == nil)
}

@Test
func planFixturesExerciseZeroOneHundredAndSourceLabels() {
    #expect(DashboardFixtures.plans.contains { $0.usedPercent == 0 })
    #expect(DashboardFixtures.plans.contains { $0.usedPercent == 100 })
    #expect(DashboardFixtures.plans.contains { $0.source == .estimated })
    #expect(DashboardFixtures.plans.allSatisfy { !$0.source.rawValue.isEmpty })
}

@Test
func providerFallbacksKeepLocalEmptyAndUnsupportedStatesValueFree() {
    let statuses = DashboardFixtures.providerCapabilityStatuses
    let codex = statuses.first { $0.id == "codex-plan-unsupported" }
    let gemini = statuses.first { $0.id == "gemini-usage-local" }

    #expect(codex?.state == .unsupported)
    #expect(codex?.title == "官方生产接口暂不可用")
    #expect(codex?.detail.contains("Cookie") == true)
    #expect(gemini?.state == .notSynchronized)
    #expect(gemini?.detail.contains("本地") == true)
    #expect(statuses.contains { $0.id == "glm-plan-unsupported" })
    #expect(statuses.contains { $0.id == "minimax-plan-unsupported" })
}

@Test @MainActor
func tokenProviderAndRangeSelectionsUpdateTheWholeSnapshot() {
    let store = TokensPageStore()
    let original = loadedSnapshot(from: store.contentState)

    store.selectProvider("deepseek")
    let providerUpdate = loadedSnapshot(from: store.contentState)
    #expect(providerUpdate?.providerName == "DeepSeek API")
    #expect(providerUpdate?.inputTokens != original?.inputTokens)

    store.selectRange(.month)
    let rangeUpdate = loadedSnapshot(from: store.contentState)
    #expect(store.selectedRange == .month)
    #expect(rangeUpdate?.inputTokens != providerUpdate?.inputTokens)
    #expect(rangeUpdate?.cost != providerUpdate?.cost)
    #expect(rangeUpdate?.chartSummary.contains("DeepSeek") == true)
}

@Test @MainActor
func allNineMVPProvidersAreSelectableWithoutInventingCodexValues() {
    let expectedProviderIDs = [
        "openai", "anthropic", "deepseek", "glm", "kimi", "minimax", "openrouter", "gemini",
        "codex",
    ]
    let store = TokensPageStore()

    #expect(store.providers.map(\.id) == expectedProviderIDs)
    for providerID in expectedProviderIDs {
        store.selectProvider(providerID)
        #expect(store.selectedProviderID == providerID)
    }
    #expect(store.providers.last?.status == .unavailable)
    #expect(
        store.contentState
            == .empty(
                title: "官方生产接口暂不可用",
                detail: "GATE-02 关闭期间不读取 Cookie、私有容器或真实额度。"
            )
    )

    store.selectRange(.month)
    #expect(store.selectedProviderID == "codex")
    #expect(
        store.contentState
            == .empty(
                title: "官方生产接口暂不可用",
                detail: "GATE-02 关闭期间不读取 Cookie、私有容器或真实额度。"
            )
    )
}

@Test
func providerSettingsCatalogMatchesCapabilitiesAndExcludesCredentiallessCodex() {
    let capabilitiesByProvider = Dictionary(
        uniqueKeysWithValues: ProviderSettingsOption.supported.map { ($0.id, Set($0.capabilities)) }
    )

    #expect(capabilitiesByProvider.count == 8)
    #expect(capabilitiesByProvider["openai"] == [.usage, .cost])
    #expect(capabilitiesByProvider["anthropic"] == [.usage, .cost])
    #expect(capabilitiesByProvider["deepseek"] == [.usage, .cost, .balance, .localEstimate])
    #expect(capabilitiesByProvider["kimi"] == [.usage, .cost, .balance, .localEstimate])
    #expect(capabilitiesByProvider["openrouter"] == [.balance])
    #expect(capabilitiesByProvider["glm"] == [.usage, .localEstimate])
    #expect(capabilitiesByProvider["minimax"] == [.usage, .localEstimate])
    #expect(capabilitiesByProvider["gemini"] == [.usage, .localEstimate])
    #expect(capabilitiesByProvider["codex"] == nil)
}

@Test
func clockFormattingHonorsExplicitTimezoneAcrossDaylightSavingChange() throws {
    let utc = try #require(TimeZone(identifier: "UTC"))
    let losAngeles = try #require(TimeZone(identifier: "America/Los_Angeles"))
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = utc
    let before = try #require(
        calendar.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 9, minute: 30))
    )
    let after = before.addingTimeInterval(3_600)

    #expect(DashboardClockPresentation.make(date: before, timeZone: losAngeles).time == "01:30:00")
    #expect(DashboardClockPresentation.make(date: after, timeZone: losAngeles).time == "03:30:00")
}

@Test @MainActor
func clockResumeRefreshesImmediatelyAndRestartsTicker() {
    let source = MutableNow(Date(timeIntervalSince1970: 100))
    let clock = DashboardClock(nowProvider: { source.value })
    clock.stop()
    source.value = Date(timeIntervalSince1970: 3_700)

    clock.resume()

    #expect(clock.now == source.value)
    #expect(clock.resumeCount == 1)
    #expect(clock.setTimeZoneOverride(identifier: "Asia/Shanghai"))
    #expect(clock.timeZone.identifier == "Asia/Shanghai")
    #expect(!clock.setTimeZoneOverride(identifier: "Not/A-TimeZone"))
    #expect(clock.timeZone.identifier == "Asia/Shanghai")
    clock.stop()
}

@Test @MainActor
func dashboardPagesRenderAtFixedContentSizeForStableSnapshots() throws {
    let fixedDate = Date(timeIntervalSince1970: 1_786_417_268)
    let clock = DashboardClock(
        now: fixedDate,
        timeZoneOverrideIdentifier: "Asia/Shanghai",
        nowProvider: { fixedDate }
    )
    try assertRendered(OverviewPage(clock: clock), width: 1_280, height: 662)
    try assertRendered(PlansPage(), width: 1_280, height: 662)
    try assertRendered(TokensPage(), width: 1_280, height: 662)
    try assertRendered(
        OverviewPage(
            state: .failed(
                title: "网络不可用",
                detail: "展示最近成功数据",
                cached: DashboardFixtures.overview
            ),
            clock: clock
        ),
        width: 1_280,
        height: 662
    )
}

@Test @MainActor
func deniedLocationKeepsManualCityFallbackAvailableAndPersistent() async {
    let preferences = TestPreferencesStore()
    let location = TestLocationService(status: .denied)
    let store = SettingsStore(preferencesStore: preferences, locationService: location)

    await store.requestCurrentLocation()
    #expect(store.locationAuthorization == .denied)
    #expect(store.operationMessage?.contains("手工城市") == true)

    store.preferences.manualCity = "上海"
    await store.resolveManualCity()
    store.savePlatformChanges()

    #expect(store.resolvedLocation?.cityName == "上海")
    #expect(preferences.value.manualCity == "上海")
    #expect(location.currentLocationRequestCount == 1)
}

@Test @MainActor
func notificationPermissionIsRequestedOnlyWhenAlertsAreEnabled() async {
    let notifications = TestNotificationService(status: .notDetermined, grantsAccess: false)
    let store = SettingsStore(notificationService: notifications)

    await store.refreshSystemState()
    #expect(notifications.requestCount == 0)

    await store.setAlertsEnabled(false)
    #expect(notifications.requestCount == 0)

    await store.setAlertsEnabled(true)
    #expect(notifications.requestCount == 1)
    #expect(!store.preferences.alertsEnabled)
    #expect(store.operationMessage?.contains("其他功能") == true)
}

@Test @MainActor
func allowedNotificationPermissionPersistsAndRevocationRecovers() async {
    let preferences = TestPreferencesStore()
    let notifications = TestNotificationService(status: .notDetermined, grantsAccess: true)
    let store = SettingsStore(
        preferencesStore: preferences,
        notificationService: notifications
    )

    await store.setAlertsEnabled(true)
    store.savePlatformChanges()
    #expect(store.notificationAuthorization == .authorized)
    #expect(preferences.value.alertsEnabled)

    notifications.status = .denied
    await store.refreshSystemState()
    #expect(!store.preferences.alertsEnabled)
    #expect(!preferences.value.alertsEnabled)
    #expect(store.operationMessage?.contains("撤销") == true)
}

@Test @MainActor
func settingsStoreRestoresPreferencesAndTracksSystemLoginState() {
    let saved = SettingsPreferences(
        manualCity: "成都",
        timeZoneOverrideIdentifier: "Asia/Shanghai",
        weatherRefreshMinutes: 30,
        showsHourlyWeather: false,
        alertsEnabled: false,
        exportFormat: .json
    )
    let preferences = TestPreferencesStore(value: saved)
    let login = TestLaunchAtLoginService(status: .disabled)
    let store = SettingsStore(preferencesStore: preferences, launchAtLoginService: login)

    #expect(store.preferences == saved)
    store.setLaunchAtLogin(true)
    #expect(login.setValues == [true])
    #expect(store.launchAtLoginStatus == .enabled)
}

@Test @MainActor
func platformDraftCancelAndSaveAreConsistentAcrossRestartAndDisplay() {
    let saved = SettingsPreferences(manualCity: "北京", weatherRefreshMinutes: 15)
    let preferences = TestPreferencesStore(value: saved)
    let displays = TestDisplaySettingsService(selectedID: 1)
    let store = SettingsStore(preferencesStore: preferences, displayService: displays)

    store.preferences.manualCity = "深圳"
    store.setWeatherRefreshMinutes(60)
    store.selectedDisplayRuntimeID = 2
    #expect(store.hasUnsavedPlatformChanges)

    store.cancelPlatformChanges()
    #expect(store.preferences == saved)
    #expect(store.selectedDisplayRuntimeID == 1)
    #expect(displays.selectedID == 1)

    store.preferences.manualCity = "深圳"
    store.setWeatherRefreshMinutes(60)
    store.selectedDisplayRuntimeID = 2
    store.savePlatformChanges()

    #expect(preferences.value.manualCity == "深圳")
    #expect(preferences.value.weatherRefreshMinutes == 60)
    #expect(displays.selectedID == 2)
    let restored = SettingsStore(preferencesStore: preferences, displayService: displays)
    #expect(restored.preferences.manualCity == "深圳")
    #expect(restored.selectedDisplayRuntimeID == 2)
}

@Test @MainActor
func providerEditorCancelNeverPersistsCredentialAndAuthenticationFailureIsExplained() async throws {
    let configuration = try providerConfiguration()
    let manager = TestProviderManager(configurations: [configuration])
    let tester = TestProviderConnectionTester(error: ConnectorError.authentication)
    let store = SettingsStore(providerManager: manager, connectionTester: tester)
    await store.refreshSystemState()

    store.beginEditingProvider(configuration)
    store.stageReplacementCredential("must-not-escape")
    store.cancelProviderEditing()
    #expect(manager.saveCount == 0)
    #expect(store.providerDraft == nil)

    await store.testConnection(accountID: configuration.accountID)
    #expect(store.operationMessage == "认证失败：请替换凭据后重试。")
}

@Test @MainActor
func providerSavePassesRedactedCredentialBoundaryAndReloadsConfiguration() async {
    let manager = TestProviderManager()
    let store = SettingsStore(providerManager: manager)
    store.beginAddingProvider()
    store.providerDraft?.accountDisplayName = "团队账户"
    store.stageReplacementCredential("ephemeral-secret")

    await store.saveProvider()

    #expect(manager.saveCount == 1)
    #expect(manager.receivedCredentialBytes == Data("ephemeral-secret".utf8))
    #expect(store.providerConfigurations.count == 1)
    #expect(store.providerDraft == nil)
}

@Test @MainActor
func exportUsesFilteredHistoryPayloadAndReportsSaveResult() async throws {
    let history = TestHistoryDataService()
    let exporter = TestHistoryExporter()
    let store = SettingsStore(exportService: exporter, historyDataService: history)
    store.exportStartDate = Date(timeIntervalSince1970: 1_800_000_000)
    store.exportEndDate = store.exportStartDate.addingTimeInterval(3_600)
    store.exportProjectReference = "project-filter"

    await store.exportHistory()

    #expect(exporter.receivedData == Data("whitelisted".utf8))
    #expect(history.lastRequest?.projectReference == "project-filter")
    #expect(store.operationMessage == "已导出 2 条记录：history.csv")
}

@Test @MainActor
func settingsPageRendersAllFiveSectionsInsideFixedCanvas() throws {
    let clock = DashboardClock(nowProvider: { Date(timeIntervalSince1970: 1_700_000_000) })
    let store = SettingsStore()

    for section in SettingsSection.allCases {
        store.selectedSection = section
        try assertRendered(
            SettingsPage(store: store, clock: clock),
            width: 1_280,
            height: 662
        )
    }
    clock.stop()
}

private func loadedSnapshot(
    from state: DashboardContentState<TokenDashboardSnapshot>
) -> TokenDashboardSnapshot? {
    guard case .loaded(let snapshot) = state else { return nil }
    return snapshot
}

private final class TestDashboardDataProvider: DashboardDataProviding, @unchecked Sendable {
    let data: DashboardDataSnapshot
    let now: Date
    let failure: ConnectorError?

    init(data: DashboardDataSnapshot, now: Date, failure: ConnectorError? = nil) {
        self.data = data
        self.now = now
        self.failure = failure
    }

    func loadCachedDashboardData() async throws -> DashboardDataSnapshot { data }

    func refreshDashboardData(location: WeatherLocation?) async -> DashboardRefreshResult {
        let providerID = data.configurations.first?.providerID
        let providers =
            providerID.map {
                [
                    ProviderSyncResult(
                        providerID: $0,
                        status: failure.map(ProviderSyncStatus.failed) ?? .succeeded,
                        attempts: 1
                    )
                ]
            } ?? []
        return DashboardRefreshResult(
            providerReport: SyncReport(startedAt: now, completedAt: now, providers: providers),
            weatherResult: nil
        )
    }
}

private func emptyDashboardData() -> DashboardDataSnapshot {
    DashboardDataSnapshot(
        configurations: [],
        plans: [],
        usage: [],
        costs: [],
        balances: [],
        weather: nil
    )
}

private func dashboardData(
    now: Date,
    input: Int64 = 12,
    output: Int64 = 4,
    isStale: Bool = false,
    includeUsage: Bool = true
) throws -> DashboardDataSnapshot {
    let providerID = try ProviderID(rawValue: "openai-production")
    let accountID = try AccountID(rawValue: "account-production")
    let configuration = ProviderAccountConfiguration(
        providerID: providerID,
        accountID: accountID,
        providerType: try ProviderType(rawValue: "openai"),
        providerDisplayName: "OpenAI Production",
        accountDisplayName: "组织账户",
        scope: .organization,
        hierarchy: AccountHierarchy(organizationReference: "org-redacted"),
        credentialReference: try CredentialReference(rawValue: "account-production"),
        credentialStatus: .configured,
        isEnabled: true,
        refreshIntervalMinutes: 15
    )
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
    let period = try UsagePeriod.containing(
        now,
        granularity: .day,
        calendar: calendar,
        timeZone: calendar.timeZone
    )
    let source = try DataSource(kind: .official, identifier: "official_usage")
    let metadata = ObservationMetadata(
        source: source,
        updatedAt: isStale ? now.addingTimeInterval(-3_600) : now,
        isStale: isStale
    )
    let usage = try TokenUsageBucket(
        providerID: providerID,
        accountID: accountID,
        model: "gpt-production",
        granularity: .day,
        period: period,
        tokens: TokenBreakdown(
            input: try TokenCount(rawValue: input),
            output: try TokenCount(rawValue: output)
        ),
        metadata: metadata
    )
    return DashboardDataSnapshot(
        configurations: [configuration],
        plans: [],
        usage: includeUsage ? [usage] : [],
        costs: [],
        balances: [],
        weather: nil
    )
}

@MainActor
private func assertRendered<V: View>(
    _ view: V,
    width: CGFloat,
    height: CGFloat
) throws {
    let renderer = ImageRenderer(content: view.frame(width: width, height: height))
    renderer.scale = 1
    let image = try #require(renderer.nsImage)
    #expect(image.size.width == width)
    #expect(image.size.height == height)
}

private final class MutableNow: @unchecked Sendable {
    var value: Date

    init(_ value: Date) {
        self.value = value
    }
}

@MainActor
private final class TestPreferencesStore: SettingsPreferencesStoring {
    var value: SettingsPreferences

    init(value: SettingsPreferences = SettingsPreferences()) {
        self.value = value
    }

    func load() -> SettingsPreferences { value }
    func save(_ preferences: SettingsPreferences) throws { value = preferences }
}

@MainActor
private final class TestLocationService: LocationServicing {
    var authorizationStatus: PermissionAuthorization
    var currentLocationRequestCount = 0

    init(status: PermissionAuthorization) {
        authorizationStatus = status
    }

    func requestCurrentLocation() async throws -> WeatherLocation {
        currentLocationRequestCount += 1
        throw TestSettingsError.permissionDenied
    }

    func resolve(city: String) async throws -> WeatherLocation {
        try WeatherLocation(
            key: "manual:test",
            cityName: city,
            latitude: 31.23,
            longitude: 121.47
        )
    }
}

@MainActor
private final class TestNotificationService: NotificationServicing {
    var status: PermissionAuthorization
    let grantsAccess: Bool
    var requestCount = 0

    init(status: PermissionAuthorization, grantsAccess: Bool) {
        self.status = status
        self.grantsAccess = grantsAccess
    }

    func authorizationStatus() async -> PermissionAuthorization { status }

    func requestAuthorization() async throws -> Bool {
        requestCount += 1
        status = grantsAccess ? .authorized : .denied
        return grantsAccess
    }

    func sendTestNotification() async throws {}
}

@MainActor
private final class TestLaunchAtLoginService: LaunchAtLoginServicing {
    var status: LaunchAtLoginStatus
    var setValues: [Bool] = []

    init(status: LaunchAtLoginStatus) {
        self.status = status
    }

    func setEnabled(_ isEnabled: Bool) throws {
        setValues.append(isEnabled)
        status = isEnabled ? .enabled : .disabled
    }
}

@MainActor
private final class TestDisplaySettingsService: DisplaySettingsServicing {
    var selectedID: UInt32?

    init(selectedID: UInt32?) { self.selectedID = selectedID }

    func availableTargets() -> [SettingsDisplayTarget] {
        [
            SettingsDisplayTarget(
                id: 1,
                name: "Main",
                logicalWidth: 1_280,
                logicalHeight: 720,
                isSelected: selectedID == 1
            ),
            SettingsDisplayTarget(
                id: 2,
                name: "Wokyis M5",
                logicalWidth: 1_280,
                logicalHeight: 720,
                isSelected: selectedID == 2
            ),
        ]
    }

    func selectDisplay(runtimeID: UInt32?) throws { selectedID = runtimeID }
}

private final class TestProviderManager: ProviderAccountManaging, @unchecked Sendable {
    var values: [ProviderAccountConfiguration]
    var saveCount = 0
    var receivedCredentialBytes: Data?

    init(configurations: [ProviderAccountConfiguration] = []) { values = configurations }

    func configurations() async throws -> [ProviderAccountConfiguration] { values }

    func save(_ draft: ProviderAccountDraft, replacingCredential: Credential?) async throws
        -> ProviderAccountConfiguration
    {
        saveCount += 1
        receivedCredentialBytes = replacingCredential?.withData { $0 }
        let configuration = try providerConfiguration(
            providerID: draft.providerID,
            accountID: draft.accountID,
            accountName: draft.accountDisplayName
        )
        values = [configuration]
        return configuration
    }

    func setEnabled(_ isEnabled: Bool, accountID: AccountID) async throws {}
    func delete(accountID: AccountID, history: ProviderHistoryDisposition) async throws {}
}

private struct TestProviderConnectionTester: ProviderConnectionTesting {
    let error: ConnectorError?

    func testConnection(for configuration: ProviderAccountConfiguration) async throws
        -> ProviderConnectionTestResult
    {
        if let error { throw error }
        return .connected
    }
}

private final class TestHistoryDataService: HistoryDataServicing, @unchecked Sendable {
    var lastRequest: HistoryExportRequest?

    func storageSnapshot() async throws -> HistoryStorageSnapshot {
        HistoryStorageSnapshot(
            databaseBytes: 4_096,
            usageRows: 1,
            costRows: 1,
            planRows: 0,
            balanceRows: 0
        )
    }

    func makeExport(
        format: HistoryExportFormat,
        request: HistoryExportRequest
    ) async throws -> HistoryExportPayload {
        lastRequest = request
        return HistoryExportPayload(data: Data("whitelisted".utf8), recordCount: 2)
    }

    func clearHistory(scope: HistoryClearScope) async throws -> HistoryClearReport {
        HistoryClearReport(
            deletedUsageRows: 1,
            deletedCostRows: 1,
            deletedPlanRows: 0,
            deletedBalanceRows: 0,
            deletedAlertEventRows: 0
        )
    }
}

@MainActor
private final class TestHistoryExporter: HistoryExportServicing {
    var receivedData: Data?

    func export(
        data: Data,
        format: HistoryExportFormat,
        suggestedFilename: String
    ) async throws -> HistoryExportResult {
        receivedData = data
        return .saved(filename: "history.csv")
    }
}

private func providerConfiguration(
    providerID: ProviderID? = nil,
    accountID: AccountID? = nil,
    accountName: String = "组织账户"
) throws -> ProviderAccountConfiguration {
    ProviderAccountConfiguration(
        providerID: try providerID ?? ProviderID(rawValue: "provider-test"),
        accountID: try accountID ?? AccountID(rawValue: "account-test"),
        providerType: try ProviderType(rawValue: "openai"),
        providerDisplayName: "OpenAI",
        accountDisplayName: accountName,
        scope: .organization,
        hierarchy: AccountHierarchy(organizationReference: "org-redacted"),
        credentialReference: try CredentialReference(rawValue: "account-test"),
        credentialStatus: .configured,
        isEnabled: true,
        refreshIntervalMinutes: 15
    )
}

private enum TestSettingsError: LocalizedError {
    case permissionDenied
    var errorDescription: String? { "定位权限未开启，可继续使用手工城市。" }
}
