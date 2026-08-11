import SwiftUI
import Testing
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
