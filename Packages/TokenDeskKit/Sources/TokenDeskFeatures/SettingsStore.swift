import Foundation
import Observation
import TokenDeskCore

/// Top-level sections in the single settings destination.
public enum SettingsSection: String, CaseIterable, Hashable, Sendable {
    case providers
    case weather
    case display
    case notifications
    case dataExport

    /// User-facing section title.
    public var title: String {
        switch self {
        case .providers: "Providers"
        case .weather: "时间与天气"
        case .display: "显示"
        case .notifications: "通知"
        case .dataExport: "数据与导出"
        }
    }
}

/// Main-actor settings state that isolates SwiftUI from macOS framework types.
@MainActor
@Observable
public final class SettingsStore {
    /// Section currently rendered inside the settings content area.
    public var selectedSection: SettingsSection = .providers
    /// Editable, non-sensitive preference snapshot.
    public var preferences: SettingsPreferences
    /// Current normalized Core Location authorization.
    public private(set) var locationAuthorization: PermissionAuthorization
    /// Current normalized UserNotifications authorization.
    public private(set) var notificationAuthorization: PermissionAuthorization = .notDetermined
    /// Current `SMAppService` registration state.
    public private(set) var launchAtLoginStatus: LaunchAtLoginStatus
    /// Most recent one-shot current location or manual-city resolution.
    public private(set) var resolvedLocation: WeatherLocation?
    /// Privacy-safe result or recovery guidance for the last user action.
    public private(set) var operationMessage: String?
    /// Whether one asynchronous platform operation is in progress.
    public private(set) var isWorking = false

    private let preferencesStore: any SettingsPreferencesStoring
    private let locationService: any LocationServicing
    private let notificationService: any NotificationServicing
    private let launchAtLoginService: any LaunchAtLoginServicing
    private let exportService: any HistoryExportServicing

    /// Creates a settings store with explicit production or test platform boundaries.
    public init(
        preferencesStore: (any SettingsPreferencesStoring)? = nil,
        locationService: (any LocationServicing)? = nil,
        notificationService: (any NotificationServicing)? = nil,
        launchAtLoginService: (any LaunchAtLoginServicing)? = nil,
        exportService: (any HistoryExportServicing)? = nil
    ) {
        let preferencesStore = preferencesStore ?? MemorySettingsPreferencesStore()
        let locationService = locationService ?? UnavailableLocationService()
        let notificationService = notificationService ?? UnavailableNotificationService()
        let launchAtLoginService = launchAtLoginService ?? UnavailableLaunchAtLoginService()
        let exportService = exportService ?? CancelledExportService()
        self.preferencesStore = preferencesStore
        self.locationService = locationService
        self.notificationService = notificationService
        self.launchAtLoginService = launchAtLoginService
        self.exportService = exportService
        preferences = preferencesStore.load()
        locationAuthorization = locationService.authorizationStatus
        launchAtLoginStatus = launchAtLoginService.status
    }

    /// Refreshes permission and registration state without displaying a prompt.
    public func refreshSystemState() async {
        locationAuthorization = locationService.authorizationStatus
        notificationAuthorization = await notificationService.authorizationStatus()
        launchAtLoginStatus = launchAtLoginService.status
        if preferences.alertsEnabled, notificationAuthorization == .denied {
            preferences.alertsEnabled = false
            savePreferences(message: "通知权限已被撤销；其他功能不受影响。")
        }
    }

    /// Persists a manually selected city after it resolves successfully.
    public func resolveManualCity() async {
        await perform {
            let location = try await locationService.resolve(city: preferences.manualCity)
            resolvedLocation = location
            preferences.manualCity = location.cityName
            try persist()
            operationMessage = "已使用手工城市：\(location.cityName)"
        }
    }

    /// Requests location only after the user presses the current-location button.
    public func requestCurrentLocation() async {
        await perform {
            resolvedLocation = try await locationService.requestCurrentLocation()
            locationAuthorization = locationService.authorizationStatus
            operationMessage = "当前位置已用于天气查询；不会保存位置轨迹。"
        }
        locationAuthorization = locationService.authorizationStatus
    }

    /// Applies an alert toggle; enabling is the only path that requests authorization.
    public func setAlertsEnabled(_ isEnabled: Bool) async {
        if !isEnabled {
            preferences.alertsEnabled = false
            savePreferences(message: "本地通知已关闭。")
            return
        }

        await perform {
            let isAuthorized = try await notificationService.requestAuthorization()
            notificationAuthorization = await notificationService.authorizationStatus()
            preferences.alertsEnabled = isAuthorized
            try persist()
            operationMessage =
                isAuthorized
                ? "本地通知已开启。"
                : "通知权限未允许；其他功能仍可正常使用。"
        }
    }

    /// Sends a generic local test notification when authorization is available.
    public func sendTestNotification() async {
        await perform {
            try await notificationService.sendTestNotification()
            operationMessage = "测试通知已发送。"
        }
    }

    /// Registers or unregisters launch-at-login and re-reads the system source of truth.
    public func setLaunchAtLogin(_ isEnabled: Bool) {
        do {
            try launchAtLoginService.setEnabled(isEnabled)
            launchAtLoginStatus = launchAtLoginService.status
            operationMessage =
                launchAtLoginStatus == .requiresApproval
                ? "请在系统设置的“登录项”中批准 Token Desk。"
                : "登录启动设置已更新。"
        } catch {
            launchAtLoginStatus = launchAtLoginService.status
            operationMessage = error.localizedDescription
        }
    }

    /// Updates and persists a time-zone override selected from the settings form.
    public func setTimeZoneOverride(_ identifier: String?) {
        preferences.timeZoneOverrideIdentifier = identifier
        savePreferences(message: "时区设置已保存。")
    }

    /// Updates and persists the weather refresh interval.
    public func setWeatherRefreshMinutes(_ minutes: Int) {
        preferences.weatherRefreshMinutes = minutes
        savePreferences()
    }

    /// Updates and persists hourly-weather visibility.
    public func setShowsHourlyWeather(_ isEnabled: Bool) {
        preferences.showsHourlyWeather = isEnabled
        savePreferences()
    }

    /// Updates and persists the preferred export format.
    public func setExportFormat(_ format: HistoryExportFormat) {
        preferences.exportFormat = format
        savePreferences()
    }

    /// Presents the system panel and exports a safe empty-history foundation payload.
    public func exportHistoryFoundation() async {
        await perform {
            let format = preferences.exportFormat
            let result = try await exportService.export(
                data: HistoryExportFoundation.payload(format: format),
                format: format,
                suggestedFilename: "token-desk-history"
            )
            switch result {
            case .cancelled:
                operationMessage = "已取消导出；未写入任何文件。"
            case .saved(let filename):
                operationMessage = "已导出：\(filename)"
            }
        }
    }

    private func perform(_ operation: () async throws -> Void) async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            try await operation()
        } catch {
            operationMessage = error.localizedDescription
        }
    }

    private func savePreferences(message: String? = nil) {
        do {
            try persist()
            operationMessage = message
        } catch {
            operationMessage = "设置未能保存：\(error.localizedDescription)"
        }
    }

    private func persist() throws {
        try preferencesStore.save(preferences)
    }
}

/// Minimal safe export bytes used until the history-query/export pipeline is connected.
public enum HistoryExportFoundation {
    /// Returns an empty schema-only payload and never includes credentials or content fields.
    public static func payload(format: HistoryExportFormat) -> Data {
        switch format {
        case .csv:
            let header =
                "时间,Provider,账户别名,模型,输入Token,输出Token,缓存读取Token,缓存写入Token,费用,币种,数据来源,是否估算\n"
            return Data([0xEF, 0xBB, 0xBF]) + Data(header.utf8)
        case .json:
            return Data("[]\n".utf8)
        }
    }
}

@MainActor
private final class MemorySettingsPreferencesStore: SettingsPreferencesStoring {
    private var value = SettingsPreferences()
    func load() -> SettingsPreferences { value }
    func save(_ preferences: SettingsPreferences) throws { value = preferences }
}

@MainActor
private final class UnavailableLocationService: LocationServicing {
    var authorizationStatus: PermissionAuthorization { .unavailable }
    func requestCurrentLocation() async throws -> WeatherLocation {
        throw SettingsFallbackError.unavailable
    }
    func resolve(city: String) async throws -> WeatherLocation {
        throw SettingsFallbackError.unavailable
    }
}

@MainActor
private final class UnavailableNotificationService: NotificationServicing {
    func authorizationStatus() async -> PermissionAuthorization { .unavailable }
    func requestAuthorization() async throws -> Bool { false }
    func sendTestNotification() async throws { throw SettingsFallbackError.unavailable }
}

@MainActor
private final class UnavailableLaunchAtLoginService: LaunchAtLoginServicing {
    var status: LaunchAtLoginStatus { .unavailable }
    func setEnabled(_ isEnabled: Bool) throws { throw SettingsFallbackError.unavailable }
}

@MainActor
private final class CancelledExportService: HistoryExportServicing {
    func export(
        data: Data,
        format: HistoryExportFormat,
        suggestedFilename: String
    ) async throws -> HistoryExportResult {
        .cancelled
    }
}

private enum SettingsFallbackError: LocalizedError {
    case unavailable
    var errorDescription: String? { "此平台能力当前不可用。" }
}
