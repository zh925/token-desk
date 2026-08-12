import Foundation
import Observation

/// Pure formatter used by the clock view and deterministic timezone tests.
public struct DashboardClockPresentation: Equatable, Sendable {
    /// Localized 24-hour clock including seconds.
    public let time: String
    /// Localized calendar date and weekday.
    public let date: String
    /// Localized effective timezone name.
    public let timeZone: String

    /// Formats a date in an explicit timezone without relying on process defaults.
    public static func make(date: Date, timeZone: TimeZone) -> Self {
        DashboardClockPresentationFormatter().make(date: date, timeZone: timeZone)
    }
}

private final class DashboardClockPresentationFormatter {
    private let locale = Locale(identifier: "zh_CN")
    private let timeFormatter: DateFormatter
    private let dateFormatter: DateFormatter

    init() {
        let calendar = Calendar(identifier: .gregorian)
        timeFormatter = DateFormatter()
        timeFormatter.calendar = calendar
        timeFormatter.locale = locale
        timeFormatter.dateFormat = "HH:mm:ss"
        dateFormatter = DateFormatter()
        dateFormatter.calendar = calendar
        dateFormatter.locale = locale
        dateFormatter.dateFormat = "yyyy年M月d日 · EEEE"
    }

    func make(date: Date, timeZone: TimeZone) -> DashboardClockPresentation {
        timeFormatter.timeZone = timeZone
        dateFormatter.timeZone = timeZone
        let timeZoneNameStyle: TimeZone.NameStyle =
            timeZone.isDaylightSavingTime(for: date) ? .daylightSaving : .standard
        return DashboardClockPresentation(
            time: timeFormatter.string(from: date),
            date: dateFormatter.string(from: date),
            timeZone: timeZone.localizedName(for: timeZoneNameStyle, locale: locale)
                ?? timeZone.identifier
        )
    }
}

/// A small, injectable second clock. Keeping it separate limits periodic view invalidation.
@MainActor
@Observable
public final class DashboardClock {
    /// Most recently sampled wall-clock date.
    public private(set) var now: Date
    /// IANA identifier selected by the user, or nil when following macOS.
    public private(set) var timeZoneOverrideIdentifier: String?
    /// Number of explicit lifecycle recovery events handled by this instance.
    public private(set) var resumeCount = 0

    @ObservationIgnored private let nowProvider: @Sendable () -> Date
    @ObservationIgnored private let formatter = DashboardClockPresentationFormatter()
    @ObservationIgnored private var tickerTask: Task<Void, Never>?

    /// Creates a clock with injectable wall time and optional timezone override.
    public init(
        now: Date? = nil,
        timeZoneOverrideIdentifier: String? = nil,
        nowProvider: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.nowProvider = nowProvider
        self.now = now ?? nowProvider()
        self.timeZoneOverrideIdentifier = timeZoneOverrideIdentifier
    }

    /// Effective timezone used for presentation.
    public var timeZone: TimeZone {
        guard let timeZoneOverrideIdentifier,
            let override = TimeZone(identifier: timeZoneOverrideIdentifier)
        else {
            return .current
        }
        return override
    }

    /// Current strings rendered by the clock subtree.
    public var presentation: DashboardClockPresentation {
        formatter.make(date: now, timeZone: timeZone)
    }

    /// Starts the one-second ticker if it is not already running.
    public func start() {
        guard tickerTask == nil else { return }
        refresh()
        tickerTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(1), tolerance: .milliseconds(100))
                } catch {
                    return
                }
                self?.refresh()
            }
        }
    }

    /// Cancels the one-second ticker.
    public func stop() {
        tickerTask?.cancel()
        tickerTask = nil
    }

    /// Samples wall time immediately.
    public func refresh() {
        now = nowProvider()
    }

    /// Refreshes immediately after activation/wake and restarts a cancelled ticker.
    public func resume() {
        resumeCount += 1
        refresh()
        if tickerTask == nil {
            start()
        }
    }

    /// Applies an IANA timezone identifier, or nil to follow the system timezone.
    @discardableResult
    public func setTimeZoneOverride(identifier: String?) -> Bool {
        if let identifier, TimeZone(identifier: identifier) == nil {
            return false
        }
        timeZoneOverrideIdentifier = identifier
        return true
    }
}
