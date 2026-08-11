import AppKit
import Testing
@testable import TokenDeskPlatform

@Test
func platformModuleNameIsStable() {
    #expect(TokenDeskPlatformModule.name == "TokenDeskPlatform")
}

@Test
func automaticSelectionRequiresUniqueWokyisNameAndMode() {
    let main = display(runtimeId: 1, name: "Built-in Display", isMain: true)
    let target = display(runtimeId: 2, name: "Wokyis", isMain: false)

    let state = DisplayMatcher().resolve(displays: [main, target], preferred: nil)

    #expect(state == .target(target, selection: .automatic))
}

@Test
func automaticSelectionFallsBackWhenCandidatesAreAmbiguous() {
    let main = display(runtimeId: 1, name: "Built-in Display", isMain: true)
    let first = display(runtimeId: 2, name: "Wokyis", isMain: false)
    let second = display(runtimeId: 3, name: "Wokyis M5", isMain: false)

    let state = DisplayMatcher().resolve(displays: [main, first, second], preferred: nil)

    #expect(state == .fallback(main, reason: .ambiguousMatch))
}

@Test
func rememberedSelectionSurvivesRuntimeIdentifierChange() {
    let original = display(runtimeId: 3, name: "Wokyis", isMain: false)
    let reconnected = display(runtimeId: 47, name: "Wokyis", isMain: false)

    let state = DisplayMatcher().resolve(
        displays: [reconnected],
        preferred: original.fingerprint
    )

    #expect(state == .target(reconnected, selection: .rememberedManualSelection))
}

@Test
func transientRuntimeIdentifierAndModeAloneDoNotMatch() {
    let original = display(runtimeId: 3, name: "Wokyis", isMain: false)
    let unrelated = display(
        runtimeId: 3,
        name: "Conference Projector",
        vendorNumber: 99,
        modelNumber: 88,
        isMain: true
    )

    let state = DisplayMatcher().resolve(
        displays: [unrelated],
        preferred: original.fingerprint
    )

    #expect(state == .fallback(unrelated, reason: .preferredDisplayMissing))
}

@Test
func rememberedSelectionCanMatchNameAndModeWhenDockChangesHardwareFields() {
    let original = display(runtimeId: 3, name: "Wokyis", isMain: false)
    let throughDock = display(
        runtimeId: 10,
        name: "Wokyis",
        vendorNumber: 0,
        modelNumber: 0,
        isMain: false
    )

    let state = DisplayMatcher().resolve(
        displays: [throughDock],
        preferred: original.fingerprint
    )

    #expect(state == .target(throughDock, selection: .rememberedManualSelection))
}

@Test
func absentModeDataDoesNotCountAsACompositeMatch() {
    let preferred = DisplayFingerprint(
        normalizedName: "Wokyis",
        vendorNumber: 0x1253,
        modelNumber: 0x2555,
        logicalSize: nil,
        pixelSize: nil
    )
    let unrelated = DisplayDescriptor(
        runtimeId: 3,
        name: "Other Display",
        vendorNumber: 0x1253,
        modelNumber: 0x2555,
        logicalSize: nil,
        pixelSize: nil,
        backingScaleFactor: 1,
        frame: DisplayFrame(originX: 0, originY: 0, width: 800, height: 600),
        visibleFrame: DisplayFrame(originX: 0, originY: 0, width: 800, height: 600),
        isMain: true
    )

    let state = DisplayMatcher().resolve(displays: [unrelated], preferred: preferred)

    #expect(state == .fallback(unrelated, reason: .preferredDisplayMissing))
}

@Test
func fallbackWindowLayoutUniformlyFitsInsideVisibleFrame() {
    let constrainedDisplay = display(
        runtimeId: 1,
        name: "Small Display",
        isMain: true,
        frame: DisplayFrame(originX: -800, originY: 0, width: 800, height: 600),
        visibleFrame: DisplayFrame(originX: -800, originY: 20, width: 800, height: 580)
    )

    let frame = DisplayWindowLayout.fallbackFrame(for: constrainedDisplay)

    #expect(frame.width == 800)
    #expect(frame.height == 450)
    #expect(frame.originX == -800)
    #expect(frame.originY == 85)
}

@MainActor
@Test
func manualSelectionPersistsFingerprintAndReconnectsToNewRuntimeIdentifier() {
    let main = display(runtimeId: 1, name: "Built-in Display", isMain: true)
    let target = display(runtimeId: 3, name: "Wokyis", isMain: false)
    let catalog = StubDisplayCatalog(displays: [main, target])
    let store = StubDisplaySelectionStore()
    let positioner = RecordingDisplayWindowPositioner()
    let controller = makeController(catalog: catalog, store: store, positioner: positioner)

    controller.start()
    #expect(controller.selectDisplay(runtimeId: 3))
    #expect(store.fingerprint == target.fingerprint)

    let reconnected = display(runtimeId: 92, name: "Wokyis", isMain: false)
    catalog.displays = [main, reconnected]
    controller.retryRecovery()

    #expect(controller.state == .target(reconnected, selection: .rememberedManualSelection))
    #expect(positioner.lastRuntimeId == 92)
    #expect(positioner.lastPlacementWasFallback == false)
    controller.stop()
}

@MainActor
@Test
func displayChangeNotificationRecoversFromSafeFallback() {
    let main = display(
        runtimeId: 1,
        name: "Built-in Display",
        vendorNumber: 1,
        modelNumber: 2,
        isMain: true
    )
    let catalog = StubDisplayCatalog(displays: [main])
    let store = StubDisplaySelectionStore(
        fingerprint: display(runtimeId: 3, name: "Wokyis", isMain: false).fingerprint
    )
    let positioner = RecordingDisplayWindowPositioner()
    let applicationCenter = NotificationCenter()
    let workspaceCenter = NotificationCenter()
    let controller = makeController(
        catalog: catalog,
        store: store,
        positioner: positioner,
        applicationCenter: applicationCenter,
        workspaceCenter: workspaceCenter
    )

    controller.start()
    #expect(controller.state == .fallback(main, reason: .preferredDisplayMissing))
    #expect(positioner.lastPlacementWasFallback == true)

    let reconnected = display(runtimeId: 80, name: "Wokyis", isMain: false)
    catalog.displays = [main, reconnected]
    applicationCenter.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)

    #expect(controller.state == .target(reconnected, selection: .rememberedManualSelection))
    #expect(controller.hasPendingRecovery == false)
    controller.stop()
}

@MainActor
@Test
func stopCancelsRecoveryAndRemovesLifecycleObservers() {
    let main = display(
        runtimeId: 1,
        name: "Built-in Display",
        vendorNumber: 1,
        modelNumber: 2,
        isMain: true
    )
    let catalog = StubDisplayCatalog(displays: [main])
    let store = StubDisplaySelectionStore(
        fingerprint: display(runtimeId: 3, name: "Wokyis", isMain: false).fingerprint
    )
    let positioner = RecordingDisplayWindowPositioner()
    let applicationCenter = NotificationCenter()
    let controller = makeController(
        catalog: catalog,
        store: store,
        positioner: positioner,
        applicationCenter: applicationCenter
    )

    controller.start()
    #expect(controller.hasPendingRecovery)
    controller.stop()
    #expect(controller.state == .stopped)
    #expect(controller.hasPendingRecovery == false)

    catalog.displays = [display(runtimeId: 44, name: "Wokyis", isMain: false)]
    applicationCenter.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
    #expect(controller.state == .stopped)
}

@MainActor
@Test
func wakeNotificationRestartsRecoveryAfterSleepCancelledIt() {
    let main = display(
        runtimeId: 1,
        name: "Built-in Display",
        vendorNumber: 1,
        modelNumber: 2,
        isMain: true
    )
    let targetTemplate = display(runtimeId: 3, name: "Wokyis", isMain: false)
    let catalog = StubDisplayCatalog(displays: [main])
    let store = StubDisplaySelectionStore(fingerprint: targetTemplate.fingerprint)
    let positioner = RecordingDisplayWindowPositioner()
    let workspaceCenter = NotificationCenter()
    let controller = makeController(
        catalog: catalog,
        store: store,
        positioner: positioner,
        workspaceCenter: workspaceCenter
    )

    controller.start()
    workspaceCenter.post(name: NSWorkspace.willSleepNotification, object: nil)
    #expect(controller.hasPendingRecovery == false)

    let reconnected = display(runtimeId: 88, name: "Wokyis", isMain: false)
    catalog.displays = [main, reconnected]
    workspaceCenter.post(name: NSWorkspace.didWakeNotification, object: nil)

    #expect(controller.state == .target(reconnected, selection: .rememberedManualSelection))
    #expect(positioner.lastRuntimeId == 88)
    controller.stop()
}

@MainActor
@Test
func recoveryStopsAtFiveSecondDeadlineUntilAnotherExplicitEvent() {
    let main = display(
        runtimeId: 1,
        name: "Built-in Display",
        vendorNumber: 1,
        modelNumber: 2,
        isMain: true
    )
    let targetTemplate = display(runtimeId: 3, name: "Wokyis", isMain: false)
    let catalog = StubDisplayCatalog(displays: [main])
    let store = StubDisplaySelectionStore(fingerprint: targetTemplate.fingerprint)
    let positioner = RecordingDisplayWindowPositioner()
    var uptime: TimeInterval = 100
    let controller = DisplayController(
        catalog: catalog,
        selectionStore: store,
        windowPositioner: positioner,
        applicationNotificationCenter: NotificationCenter(),
        workspaceNotificationCenter: NotificationCenter(),
        uptime: { uptime }
    )

    controller.start()
    #expect(controller.hasPendingRecovery)
    uptime = 105.01
    controller.retryPendingRecovery()

    #expect(controller.hasPendingRecovery == false)
    #expect(controller.state == .fallback(main, reason: .preferredDisplayMissing))
    controller.stop()
}

@MainActor
@Test
func corruptPersistedFingerprintFailsClosed() {
    let suiteName = "TokenDeskPlatformTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    defaults.set(Data("not-json".utf8), forKey: "display.selectedFingerprint.v1")
    let store = UserDefaultsDisplaySelectionStore(defaults: defaults)

    #expect(store.load() == nil)
}

private func display(
    runtimeId: UInt32,
    name: String,
    vendorNumber: UInt32 = 0x1253,
    modelNumber: UInt32 = 0x2555,
    isMain: Bool,
    frame: DisplayFrame = DisplayFrame(originX: 0, originY: 0, width: 1_280, height: 720),
    visibleFrame: DisplayFrame = DisplayFrame(
        originX: 0,
        originY: 0,
        width: 1_280,
        height: 720
    )
) -> DisplayDescriptor {
    DisplayDescriptor(
        runtimeId: runtimeId,
        name: name,
        vendorNumber: vendorNumber,
        modelNumber: modelNumber,
        logicalSize: DisplaySize(width: 1_280, height: 720),
        pixelSize: DisplaySize(width: 1_280, height: 720),
        backingScaleFactor: 1,
        frame: frame,
        visibleFrame: visibleFrame,
        isMain: isMain
    )
}

@MainActor
private final class StubDisplayCatalog: DisplayCatalog {
    var displays: [DisplayDescriptor]

    init(displays: [DisplayDescriptor]) {
        self.displays = displays
    }

    func currentDisplays() -> [DisplayDescriptor] {
        displays
    }
}

@MainActor
private final class StubDisplaySelectionStore: DisplaySelectionStoring {
    var fingerprint: DisplayFingerprint?

    init(fingerprint: DisplayFingerprint? = nil) {
        self.fingerprint = fingerprint
    }

    func load() -> DisplayFingerprint? {
        fingerprint
    }

    func save(_ fingerprint: DisplayFingerprint?) {
        self.fingerprint = fingerprint
    }
}

@MainActor
private final class RecordingDisplayWindowPositioner: DisplayWindowPositioning {
    private(set) var lastRuntimeId: UInt32?
    private(set) var lastPlacementWasFallback: Bool?

    func attach(window: NSWindow) {}

    func position(on display: DisplayDescriptor, isFallback: Bool) {
        lastRuntimeId = display.runtimeId
        lastPlacementWasFallback = isFallback
    }
}

@MainActor
private func makeController(
    catalog: StubDisplayCatalog,
    store: StubDisplaySelectionStore,
    positioner: RecordingDisplayWindowPositioner,
    applicationCenter: NotificationCenter = NotificationCenter(),
    workspaceCenter: NotificationCenter = NotificationCenter()
) -> DisplayController {
    DisplayController(
        catalog: catalog,
        selectionStore: store,
        windowPositioner: positioner,
        applicationNotificationCenter: applicationCenter,
        workspaceNotificationCenter: workspaceCenter
    )
}
