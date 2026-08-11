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
