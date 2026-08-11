import AppKit
import Combine
import Foundation

/// Resolves the target display, persists manual selection, and restores window placement.
///
/// All methods and published state are isolated to the main actor because `NSScreen`, `NSWindow`,
/// and workspace lifecycle notifications are AppKit boundaries. Recovery retries are bounded to
/// five seconds; callers can invoke ``retryRecovery()`` after that window without reconfiguration.
@MainActor
public final class DisplayController: NSObject, ObservableObject {
    /// The latest privacy-minimized list of currently connected displays.
    @Published public private(set) var availableDisplays: [DisplayDescriptor] = []
    /// The current target or safe-fallback resolution outcome.
    @Published public private(set) var state: DisplayControllerState = .stopped

    private let catalog: any DisplayCatalog
    private let selectionStore: any DisplaySelectionStoring
    private let windowPositioner: any DisplayWindowPositioning
    private let matcher: DisplayMatcher
    private let applicationNotificationCenter: NotificationCenter
    private let workspaceNotificationCenter: NotificationCenter
    private let uptime: () -> TimeInterval
    private let retryInterval: TimeInterval
    private let recoveryTimeout: TimeInterval

    private var preferredFingerprint: DisplayFingerprint?
    private var recoveryDeadline: TimeInterval?
    private var recoveryTimer: Timer?
    private var isRunning = false

    /// Creates the production controller backed by `NSScreen` and `UserDefaults`.
    public override convenience init() {
        self.init(
            catalog: NSScreenDisplayCatalog(),
            selectionStore: UserDefaultsDisplaySelectionStore(),
            windowPositioner: AppKitDisplayWindowPositioner()
        )
    }

    init(
        catalog: any DisplayCatalog,
        selectionStore: any DisplaySelectionStoring,
        windowPositioner: any DisplayWindowPositioning,
        matcher: DisplayMatcher = DisplayMatcher(),
        applicationNotificationCenter: NotificationCenter = .default,
        workspaceNotificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
        uptime: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
        retryInterval: TimeInterval = 0.25,
        recoveryTimeout: TimeInterval = 5
    ) {
        self.catalog = catalog
        self.selectionStore = selectionStore
        self.windowPositioner = windowPositioner
        self.matcher = matcher
        self.applicationNotificationCenter = applicationNotificationCenter
        self.workspaceNotificationCenter = workspaceNotificationCenter
        self.uptime = uptime
        self.retryInterval = retryInterval
        self.recoveryTimeout = recoveryTimeout
        super.init()
    }

    /// Starts lifecycle observation and immediately resolves the best available display.
    public func start() {
        guard isRunning == false else {
            return
        }

        isRunning = true
        preferredFingerprint = selectionStore.load()
        applicationNotificationCenter.addObserver(
            self,
            selector: #selector(screenParametersDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        workspaceNotificationCenter.addObserver(
            self,
            selector: #selector(workspaceWillSleep),
            name: NSWorkspace.willSleepNotification,
            object: nil
        )
        workspaceNotificationCenter.addObserver(
            self,
            selector: #selector(workspaceDidWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
        beginRecovery()
    }

    /// Stops observation and cancels any pending recovery without clearing the saved selection.
    public func stop() {
        guard isRunning else {
            return
        }

        isRunning = false
        applicationNotificationCenter.removeObserver(self)
        workspaceNotificationCenter.removeObserver(self)
        cancelRecovery()
        state = .stopped
    }

    /// Attaches the SwiftUI-hosting window that should follow the resolved display.
    public func attach(window: NSWindow) {
        windowPositioner.attach(window: window)
        applyWindowPlacement(for: state)
    }

    /// Persists a user-selected connected display using its composite fingerprint.
    ///
    /// Returns `false` when the runtime identifier is no longer present, allowing settings UI to
    /// keep the previous selection and ask the user to retry.
    @discardableResult
    public func selectDisplay(runtimeId: UInt32) -> Bool {
        guard let display = availableDisplays.first(where: { $0.runtimeId == runtimeId }) else {
            return false
        }

        preferredFingerprint = display.fingerprint
        selectionStore.save(display.fingerprint)
        beginRecovery()
        return true
    }

    /// Clears the remembered manual selection and returns to conservative Wokyis auto-detection.
    public func useAutomaticSelection() {
        preferredFingerprint = nil
        selectionStore.save(nil)
        beginRecovery()
    }

    /// Starts another bounded five-second resolution attempt after a fallback.
    public func retryRecovery() {
        guard isRunning else {
            return
        }
        beginRecovery()
    }

    var hasPendingRecovery: Bool {
        recoveryTimer != nil
    }

    @objc private func screenParametersDidChange() {
        beginRecovery()
    }

    @objc private func workspaceWillSleep() {
        cancelRecovery()
    }

    @objc private func workspaceDidWake() {
        beginRecovery()
    }

    @objc private func recoveryTimerFired() {
        retryPendingRecovery()
    }

    func retryPendingRecovery() {
        guard isRunning, let recoveryDeadline else {
            cancelRecovery()
            return
        }
        guard uptime() <= recoveryDeadline else {
            cancelRecovery()
            return
        }
        resolveCurrentDisplays()
    }

    private func beginRecovery() {
        guard isRunning else {
            return
        }

        cancelRecovery()
        recoveryDeadline = uptime() + recoveryTimeout
        resolveCurrentDisplays()

        guard case .fallback = state else {
            recoveryDeadline = nil
            return
        }

        let timer = Timer(
            timeInterval: retryInterval,
            target: self,
            selector: #selector(recoveryTimerFired),
            userInfo: nil,
            repeats: true
        )
        recoveryTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func resolveCurrentDisplays() {
        let displays = catalog.currentDisplays()
        availableDisplays = displays
        let resolvedState = matcher.resolve(displays: displays, preferred: preferredFingerprint)
        state = resolvedState
        applyWindowPlacement(for: resolvedState)

        if case .target = resolvedState {
            cancelRecovery()
        }
    }

    private func applyWindowPlacement(for state: DisplayControllerState) {
        switch state {
        case .stopped:
            break
        case .target(let display, _):
            windowPositioner.position(on: display, isFallback: false)
        case .fallback(let display, _):
            if let display {
                windowPositioner.position(on: display, isFallback: true)
            }
        }
    }

    private func cancelRecovery() {
        recoveryTimer?.invalidate()
        recoveryTimer = nil
        recoveryDeadline = nil
    }
}
