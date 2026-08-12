import Foundation

/// Normalized optional-permission states rendered by the settings feature.
public enum PermissionAuthorization: String, Codable, Equatable, Sendable {
    case notDetermined
    case denied
    case authorized
    case restricted
    case unavailable
}

/// User-visible launch-at-login state, including macOS approval requirements.
public enum LaunchAtLoginStatus: String, Equatable, Sendable {
    case disabled
    case enabled
    case requiresApproval
    case unavailable
}

/// Privacy-minimized display information rendered by settings.
public struct SettingsDisplayTarget: Equatable, Identifiable, Sendable {
    /// Transient runtime display identifier.
    public let id: UInt32
    /// Privacy-minimized display name.
    public let name: String
    /// Current logical width in points.
    public let logicalWidth: Int
    /// Current logical height in points.
    public let logicalHeight: Int
    /// Whether the controller currently targets this display.
    public let isSelected: Bool

    /// Creates a display snapshot for the settings picker.
    public init(
        id: UInt32,
        name: String,
        logicalWidth: Int,
        logicalHeight: Int,
        isSelected: Bool
    ) {
        self.id = id
        self.name = name
        self.logicalWidth = logicalWidth
        self.logicalHeight = logicalHeight
        self.isSelected = isSelected
    }
}

/// Supported single-file history export formats.
public enum HistoryExportFormat: String, CaseIterable, Codable, Equatable, Hashable, Sendable {
    case csv
    case json

    /// Filename extension accepted by the system save panel.
    public var filenameExtension: String { rawValue }
}

/// Result of a user-initiated save-panel export.
public enum HistoryExportResult: Equatable, Sendable {
    case cancelled
    case saved(filename: String)
}

/// Non-sensitive preferences restored when the app restarts.
public struct SettingsPreferences: Codable, Equatable, Sendable {
    /// User-entered weather city; never inferred from permission-gated history.
    public var manualCity: String
    /// Optional IANA time-zone override, or nil to follow macOS.
    public var timeZoneOverrideIdentifier: String?
    /// Weather refresh cadence in whole minutes.
    public var weatherRefreshMinutes: Int
    /// Public, sandbox-compatible weather connector identifier.
    public var weatherProvider: String
    /// Whether the dashboard should display hourly conditions.
    public var showsHourlyWeather: Bool
    /// User preference for local alerts; false unless authorization was granted.
    public var alertsEnabled: Bool
    /// Last export format selected by the user.
    public var exportFormat: HistoryExportFormat

    /// Creates settings with privacy-preserving defaults and all optional capabilities off.
    public init(
        manualCity: String = "",
        timeZoneOverrideIdentifier: String? = nil,
        weatherRefreshMinutes: Int = 15,
        weatherProvider: String = "open-meteo",
        showsHourlyWeather: Bool = true,
        alertsEnabled: Bool = false,
        exportFormat: HistoryExportFormat = .csv
    ) {
        self.manualCity = manualCity
        self.timeZoneOverrideIdentifier = timeZoneOverrideIdentifier
        self.weatherRefreshMinutes = weatherRefreshMinutes
        self.weatherProvider = weatherProvider
        self.showsHourlyWeather = showsHourlyWeather
        self.alertsEnabled = alertsEnabled
        self.exportFormat = exportFormat
    }

    private enum CodingKeys: String, CodingKey {
        case manualCity
        case timeZoneOverrideIdentifier
        case weatherRefreshMinutes
        case weatherProvider
        case showsHourlyWeather
        case alertsEnabled
        case exportFormat
    }

    /// Decodes preferences while supplying defaults for values added in later app versions.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        manualCity = try container.decodeIfPresent(String.self, forKey: .manualCity) ?? ""
        timeZoneOverrideIdentifier = try container.decodeIfPresent(
            String.self,
            forKey: .timeZoneOverrideIdentifier
        )
        weatherRefreshMinutes =
            try container.decodeIfPresent(
                Int.self,
                forKey: .weatherRefreshMinutes
            ) ?? 15
        weatherProvider =
            try container.decodeIfPresent(
                String.self,
                forKey: .weatherProvider
            ) ?? "open-meteo"
        showsHourlyWeather =
            try container.decodeIfPresent(
                Bool.self,
                forKey: .showsHourlyWeather
            ) ?? true
        alertsEnabled = try container.decodeIfPresent(Bool.self, forKey: .alertsEnabled) ?? false
        exportFormat =
            try container.decodeIfPresent(
                HistoryExportFormat.self,
                forKey: .exportFormat
            ) ?? .csv
    }
}

/// Persistence boundary for non-sensitive settings. Credentials must never use this store.
@MainActor
public protocol SettingsPreferencesStoring: AnyObject {
    /// Loads the last valid preferences, or defaults when no value exists.
    func load() -> SettingsPreferences

    /// Replaces the persisted non-sensitive preference snapshot.
    func save(_ preferences: SettingsPreferences) throws
}

/// Core Location boundary used by settings without importing platform frameworks.
@MainActor
public protocol LocationServicing: AnyObject {
    /// Current authorization state reported by macOS.
    var authorizationStatus: PermissionAuthorization { get }

    /// Requests authorization if needed, then obtains one current position.
    func requestCurrentLocation() async throws -> WeatherLocation

    /// Resolves a user-entered city without requesting location permission.
    func resolve(city: String) async throws -> WeatherLocation
}

/// UserNotifications boundary. Authorization is requested only by an explicit enable action.
@MainActor
public protocol NotificationServicing: AnyObject {
    /// Reads current notification authorization without prompting.
    func authorizationStatus() async -> PermissionAuthorization

    /// Prompts for notification authorization.
    func requestAuthorization() async throws -> Bool

    /// Schedules a privacy-safe local test notification.
    func sendTestNotification() async throws
}

/// ServiceManagement boundary for the main app login item.
@MainActor
public protocol LaunchAtLoginServicing: AnyObject {
    /// Current registration state from `SMAppService`.
    var status: LaunchAtLoginStatus { get }

    /// Registers or unregisters the app after a user toggle.
    func setEnabled(_ isEnabled: Bool) throws
}

/// Target-display boundary that keeps SwiftUI independent from AppKit screen types.
@MainActor
public protocol DisplaySettingsServicing: AnyObject {
    func availableTargets() -> [SettingsDisplayTarget]
    func selectDisplay(runtimeID: UInt32?) throws
}

/// Sandboxed, user-selected single-file export boundary.
@MainActor
public protocol HistoryExportServicing: AnyObject {
    /// Presents a save panel and writes only after the user selects a destination.
    func export(
        data: Data,
        format: HistoryExportFormat,
        suggestedFilename: String
    ) async throws -> HistoryExportResult
}
