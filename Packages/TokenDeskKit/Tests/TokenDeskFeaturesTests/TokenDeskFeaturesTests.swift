import SwiftUI
import Testing
import TokenDeskCore
import TokenDeskFeatures

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

@Test
func planFixturesExerciseZeroOneHundredAndSourceLabels() {
    #expect(DashboardFixtures.plans.contains { $0.usedPercent == 0 })
    #expect(DashboardFixtures.plans.contains { $0.usedPercent == 100 })
    #expect(DashboardFixtures.plans.contains { $0.source == .estimated })
    #expect(DashboardFixtures.plans.allSatisfy { !$0.source.rawValue.isEmpty })
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

@Test
func exportFoundationUsesBOMAndExcludesSensitiveFields() throws {
    let csv = HistoryExportFoundation.payload(format: .csv)
    #expect(Array(csv.prefix(3)) == [0xEF, 0xBB, 0xBF])
    let csvText = try #require(String(data: csv, encoding: .utf8))
    #expect(csvText.contains("Provider"))
    #expect(!csvText.localizedCaseInsensitiveContains("api key"))
    #expect(!csvText.contains("Prompt"))
    #expect(HistoryExportFoundation.payload(format: .json) == Data("[]\n".utf8))
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

private enum TestSettingsError: LocalizedError {
    case permissionDenied
    var errorDescription: String? { "定位权限未开启，可继续使用手工城市。" }
}
