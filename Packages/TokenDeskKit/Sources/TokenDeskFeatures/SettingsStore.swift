import Foundation
import Observation
import TokenDeskCore

/// Top-level sections in the product's single settings destination.
public enum SettingsSection: String, CaseIterable, Hashable, Sendable {
    case providers
    case weather
    case display
    case notifications
    case dataExport

    /// User-facing navigation title.
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

/// Product-owned capability metadata shown before a credential is configured.
struct ProviderSettingsOption: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let capabilities: [ProviderCapability]
    let organizationCredentialHint: String

    static let supported: [ProviderSettingsOption] = [
        .init(
            id: "openai", title: "OpenAI", capabilities: [.usage, .cost],
            organizationCredentialHint: "组织用量需只读 Admin Key"
        ),
        .init(
            id: "anthropic", title: "Anthropic", capabilities: [.usage, .cost],
            organizationCredentialHint: "仅组织范围，需 Admin API Key"
        ),
        .init(
            id: "deepseek", title: "DeepSeek",
            capabilities: [.usage, .cost, .balance, .localEstimate],
            organizationCredentialHint: "余额为官方数据；Token 可本地聚合"
        ),
        .init(
            id: "kimi", title: "Kimi", capabilities: [.usage, .cost, .balance, .localEstimate],
            organizationCredentialHint: "余额为官方数据；Token 可本地聚合"
        ),
        .init(
            id: "openrouter", title: "OpenRouter", capabilities: [.balance],
            organizationCredentialHint: "Credits 需只读管理密钥"
        ),
        .init(
            id: "codex", title: "Codex", capabilities: [.plan, .usage],
            organizationCredentialHint: "仅展示当前沙箱可获得能力"
        ),
        .init(
            id: "glm", title: "智谱 GLM", capabilities: [.usage, .localEstimate],
            organizationCredentialHint: "无公开历史接口时使用明确标识的本地聚合"
        ),
        .init(
            id: "minimax", title: "MiniMax", capabilities: [.usage, .localEstimate],
            organizationCredentialHint: "无公开历史接口时使用明确标识的本地聚合"
        ),
        .init(
            id: "gemini", title: "Gemini", capabilities: [.usage, .localEstimate],
            organizationCredentialHint: "依官方公开能力降级展示"
        ),
    ]
}

/// Coordinates non-secret settings drafts and injected platform or persistence boundaries.
@MainActor
@Observable
public final class SettingsStore {
    /// Section currently rendered in the settings content area.
    public var selectedSection: SettingsSection = .providers
    var preferences: SettingsPreferences
    private(set) var providerConfigurations: [ProviderAccountConfiguration] = []
    var providerDraft: ProviderAccountDraft?
    private(set) var displayTargets: [SettingsDisplayTarget] = []
    var selectedDisplayRuntimeID: UInt32?
    private(set) var locationAuthorization: PermissionAuthorization
    private(set) var notificationAuthorization: PermissionAuthorization = .notDetermined
    private(set) var launchAtLoginStatus: LaunchAtLoginStatus
    private(set) var resolvedLocation: WeatherLocation?
    private(set) var operationMessage: String?
    private(set) var isWorking = false

    var hasUnsavedPlatformChanges: Bool {
        preferences != persistedPreferences
            || selectedDisplayRuntimeID != persistedDisplayRuntimeID
    }

    private let preferencesStore: any SettingsPreferencesStoring
    private let locationService: any LocationServicing
    private let notificationService: any NotificationServicing
    private let launchAtLoginService: any LaunchAtLoginServicing
    private let displayService: any DisplaySettingsServicing
    private let exportService: any HistoryExportServicing
    private let providerManager: any ProviderAccountManaging
    private let connectionTester: any ProviderConnectionTesting
    private var persistedPreferences: SettingsPreferences
    private var persistedDisplayRuntimeID: UInt32?
    private var replacementCredential: Credential?

    /// Creates the store with production services or safe unavailable defaults.
    public init(
        preferencesStore: (any SettingsPreferencesStoring)? = nil,
        locationService: (any LocationServicing)? = nil,
        notificationService: (any NotificationServicing)? = nil,
        launchAtLoginService: (any LaunchAtLoginServicing)? = nil,
        displayService: (any DisplaySettingsServicing)? = nil,
        exportService: (any HistoryExportServicing)? = nil,
        providerManager: (any ProviderAccountManaging)? = nil,
        connectionTester: (any ProviderConnectionTesting)? = nil
    ) {
        let preferencesStore = preferencesStore ?? MemorySettingsPreferencesStore()
        let locationService = locationService ?? UnavailableLocationService()
        let notificationService = notificationService ?? UnavailableNotificationService()
        let launchAtLoginService = launchAtLoginService ?? UnavailableLaunchAtLoginService()
        let displayService = displayService ?? UnavailableDisplaySettingsService()
        self.preferencesStore = preferencesStore
        self.locationService = locationService
        self.notificationService = notificationService
        self.launchAtLoginService = launchAtLoginService
        self.displayService = displayService
        self.exportService = exportService ?? CancelledExportService()
        self.providerManager = providerManager ?? UnavailableProviderAccountManager()
        self.connectionTester = connectionTester ?? UnavailableConnectionTester()
        let loadedPreferences = preferencesStore.load()
        preferences = loadedPreferences
        persistedPreferences = loadedPreferences
        locationAuthorization = locationService.authorizationStatus
        launchAtLoginStatus = launchAtLoginService.status
        let targets = displayService.availableTargets()
        displayTargets = targets
        let selectedID = targets.first(where: \.isSelected)?.id
        selectedDisplayRuntimeID = selectedID
        persistedDisplayRuntimeID = selectedID
    }

    func refreshSystemState() async {
        locationAuthorization = locationService.authorizationStatus
        notificationAuthorization = await notificationService.authorizationStatus()
        launchAtLoginStatus = launchAtLoginService.status
        displayTargets = displayService.availableTargets()
        if !hasUnsavedPlatformChanges {
            let selectedID = displayTargets.first(where: \.isSelected)?.id
            selectedDisplayRuntimeID = selectedID
            persistedDisplayRuntimeID = selectedID
        }
        if preferences.alertsEnabled, notificationAuthorization == .denied {
            preferences.alertsEnabled = false
            persistedPreferences.alertsEnabled = false
            do {
                try preferencesStore.save(persistedPreferences)
                operationMessage = "通知权限已被撤销；告警已安全关闭，其他功能不受影响。"
            } catch {
                operationMessage = "通知权限已撤销，设置保存失败：\(error.localizedDescription)"
            }
        }
        await reloadProviders()
    }

    func savePlatformChanges() {
        do {
            let previousDisplayID = persistedDisplayRuntimeID
            try displayService.selectDisplay(runtimeID: selectedDisplayRuntimeID)
            do {
                try preferencesStore.save(preferences)
            } catch {
                try? displayService.selectDisplay(runtimeID: previousDisplayID)
                throw error
            }
            persistedPreferences = preferences
            persistedDisplayRuntimeID = selectedDisplayRuntimeID
            displayTargets = displayService.availableTargets()
            operationMessage = "设置已保存；重启后将恢复这些选择。"
        } catch {
            operationMessage = "设置未能保存：\(error.localizedDescription)"
        }
    }

    func cancelPlatformChanges() {
        preferences = persistedPreferences
        selectedDisplayRuntimeID = persistedDisplayRuntimeID
        operationMessage = "未保存的更改已取消。"
    }

    func resolveManualCity() async {
        await perform {
            let location = try await locationService.resolve(city: preferences.manualCity)
            resolvedLocation = location
            preferences.manualCity = location.cityName
            operationMessage = "已验证手工城市：\(location.cityName)。请保存以在重启后恢复。"
        }
    }

    func requestCurrentLocation() async {
        await perform {
            resolvedLocation = try await locationService.requestCurrentLocation()
            locationAuthorization = locationService.authorizationStatus
            operationMessage = "当前位置已用于天气查询；不会保存位置轨迹。"
        }
        locationAuthorization = locationService.authorizationStatus
    }

    func setAlertsEnabled(_ isEnabled: Bool) async {
        if !isEnabled {
            preferences.alertsEnabled = false
            operationMessage = "本地通知将在保存后关闭。"
            return
        }
        await perform {
            let isAuthorized = try await notificationService.requestAuthorization()
            notificationAuthorization = await notificationService.authorizationStatus()
            preferences.alertsEnabled = isAuthorized
            operationMessage =
                isAuthorized
                ? "通知权限已允许；请保存以启用本地告警。"
                : "通知权限未允许；其他功能仍可正常使用。"
        }
    }

    func sendTestNotification() async {
        await perform {
            try await notificationService.sendTestNotification()
            operationMessage = "测试通知已发送。"
        }
    }

    func setLaunchAtLogin(_ isEnabled: Bool) {
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

    func setTimeZoneOverride(_ identifier: String?) {
        preferences.timeZoneOverrideIdentifier = identifier
    }

    func setWeatherRefreshMinutes(_ minutes: Int) {
        preferences.weatherRefreshMinutes = minutes
    }

    func setWeatherProvider(_ provider: String) {
        preferences.weatherProvider = provider
    }

    func setShowsHourlyWeather(_ isEnabled: Bool) {
        preferences.showsHourlyWeather = isEnabled
    }

    func setExportFormat(_ format: HistoryExportFormat) {
        preferences.exportFormat = format
    }

    func beginAddingProvider(option: ProviderSettingsOption = .supported[0]) {
        providerDraft = ProviderAccountDraft(
            providerType: option.id,
            providerDisplayName: option.title
        )
        replacementCredential = nil
        operationMessage = nil
    }

    func beginEditingProvider(_ configuration: ProviderAccountConfiguration) {
        providerDraft = ProviderAccountDraft(configuration: configuration)
        replacementCredential = nil
        operationMessage = nil
    }

    func selectProviderType(_ rawValue: String) {
        guard var draft = providerDraft,
            let option = ProviderSettingsOption.supported.first(where: { $0.id == rawValue })
        else { return }
        draft.providerType = option.id
        draft.providerDisplayName = option.title
        providerDraft = draft
    }

    /// Receives ephemeral secure-field content without exposing it back through observable state.
    func stageReplacementCredential(_ value: String) {
        replacementCredential = value.isEmpty ? nil : try? Credential(utf8Value: value)
    }

    func cancelProviderEditing() {
        replacementCredential = nil
        providerDraft = nil
        operationMessage = "Provider 更改已取消；凭据未写入 Keychain。"
    }

    func saveProvider() async {
        guard let draft = providerDraft else { return }
        await perform {
            _ = try await providerManager.save(
                draft,
                replacingCredential: replacementCredential
            )
            replacementCredential = nil
            providerDraft = nil
            providerConfigurations = try await providerManager.configurations()
            operationMessage = "Provider 与账户设置已保存；密钥不会回显。"
        }
    }

    func setProviderEnabled(_ isEnabled: Bool, accountID: AccountID) async {
        await perform {
            try await providerManager.setEnabled(isEnabled, accountID: accountID)
            providerConfigurations = try await providerManager.configurations()
            operationMessage = isEnabled ? "Provider 已启用。" : "Provider 已停用，历史数据仍保留。"
        }
    }

    func testConnection(accountID: AccountID) async {
        guard
            let configuration = providerConfigurations.first(where: {
                $0.accountID == accountID
            })
        else { return }
        await perform {
            let result = try await connectionTester.testConnection(for: configuration)
            operationMessage =
                switch result {
                case .connected: "连接成功；官方端点已返回可解释结果。"
                case .credentialConfigured: "凭据可读取；该 Provider 将在首次同步时验证远端能力。"
                case .unsupported(let reason): reason
                }
        }
    }

    func deleteProvider(
        accountID: AccountID,
        history: ProviderHistoryDisposition
    ) async {
        await perform {
            try await providerManager.delete(accountID: accountID, history: history)
            providerConfigurations = try await providerManager.configurations()
            operationMessage =
                history == .retain
                ? "Provider 凭据已删除；账户已停用并保留历史。"
                : "Provider、凭据与所选历史已删除。"
        }
    }

    func exportHistoryFoundation() async {
        await perform {
            let format = preferences.exportFormat
            let result = try await exportService.export(
                data: HistoryExportFoundation.payload(format: format),
                format: format,
                suggestedFilename: "token-desk-history"
            )
            operationMessage =
                switch result {
                case .cancelled: "已取消导出；未写入任何文件。"
                case .saved(let filename): "已导出：\(filename)"
                }
        }
    }

    private func reloadProviders() async {
        do {
            providerConfigurations = try await providerManager.configurations()
        } catch {
            operationMessage = "Provider 设置无法读取：\(stableMessage(for: error))"
        }
    }

    private func perform(_ operation: () async throws -> Void) async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            try await operation()
        } catch {
            operationMessage = stableMessage(for: error)
        }
    }

    private func stableMessage(for error: Error) -> String {
        guard let connectorError = error as? ConnectorError else {
            return error.localizedDescription
        }
        return switch connectorError {
        case .authentication: "认证失败：请替换凭据后重试。"
        case .permissionDenied: "权限不足：请确认账户范围与只读管理权限。"
        case .rateLimited(let retryAfter):
            retryAfter == nil ? "Provider 限流，请稍后重试。" : "Provider 限流，请按服务端时间稍后重试。"
        case .network: "网络不可用；已保存设置不会丢失。"
        case .server(let statusCode):
            statusCode.map { "Provider 服务异常（HTTP \($0)）。" } ?? "Provider 服务异常。"
        case .decoding: "Provider 返回了无法识别的数据；未改动现有设置。"
        case .unsupported: "该 Provider 不支持此连接测试能力。"
        case .cancelled: "连接测试已取消。"
        }
    }
}

enum HistoryExportFoundation {
    static func payload(format: HistoryExportFormat) -> Data {
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
private final class UnavailableDisplaySettingsService: DisplaySettingsServicing {
    func availableTargets() -> [SettingsDisplayTarget] { [] }
    func selectDisplay(runtimeID: UInt32?) throws {
        guard runtimeID == nil else { throw SettingsFallbackError.unavailable }
    }
}

@MainActor
private final class CancelledExportService: HistoryExportServicing {
    func export(
        data: Data,
        format: HistoryExportFormat,
        suggestedFilename: String
    ) async throws -> HistoryExportResult { .cancelled }
}

private struct UnavailableProviderAccountManager: ProviderAccountManaging {
    func configurations() async throws -> [ProviderAccountConfiguration] { [] }
    func save(_ draft: ProviderAccountDraft, replacingCredential: Credential?) async throws
        -> ProviderAccountConfiguration
    { throw SettingsFallbackError.unavailable }
    func setEnabled(_ isEnabled: Bool, accountID: AccountID) async throws {
        throw SettingsFallbackError.unavailable
    }
    func delete(accountID: AccountID, history: ProviderHistoryDisposition) async throws {
        throw SettingsFallbackError.unavailable
    }
}

private struct UnavailableConnectionTester: ProviderConnectionTesting {
    func testConnection(for configuration: ProviderAccountConfiguration) async throws
        -> ProviderConnectionTestResult
    { throw SettingsFallbackError.unavailable }
}

private enum SettingsFallbackError: LocalizedError {
    case unavailable
    var errorDescription: String? { "此平台能力当前不可用。" }
}
