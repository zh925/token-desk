import AppKit
import SwiftUI
import TokenDeskCore
import TokenDeskDesign

/// Single settings destination for Provider, weather, display, notifications, and export controls.
public struct SettingsPage: View {
    @Bindable private var store: SettingsStore
    @Bindable private var clock: DashboardClock
    @State private var deletionAccountID: AccountID?
    @State private var pendingHistoryClear: HistoryClearScope?

    /// Creates the page with injected settings and isolated clock state.
    public init(store: SettingsStore, clock: DashboardClock) {
        self.store = store
        self.clock = clock
    }

    /// Fixed-canvas five-section settings layout.
    public var body: some View {
        VStack(spacing: TokenDeskDesign.Spacing.large) {
            PageHeading(
                title: "设置页面",
                subtitle: "所有配置、权限与导出均从此唯一入口管理",
                code: "SETTINGS · SINGLE ENTRY"
            )

            HStack(alignment: .top, spacing: TokenDeskDesign.Spacing.large) {
                sectionNavigation
                sectionContent.frame(width: 1_026, height: 450, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            if let message = store.operationMessage {
                Text(message)
                    .font(TokenDeskTextStyle.auxiliary.font)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("settings-operation-message")
            }
        }
        .padding(TokenDeskDesign.Spacing.extraLarge)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("设置页面")
        .accessibilityIdentifier("page-settings")
        .task {
            await store.refreshSystemState()
            _ = clock.setTimeZoneOverride(
                identifier: store.preferences.timeZoneOverrideIdentifier
            )
        }
        .confirmationDialog(
            "删除 Provider",
            isPresented: Binding(
                get: { deletionAccountID != nil },
                set: { if !$0 { deletionAccountID = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("删除凭据，保留历史") { deleteSelectedProvider(history: .retain) }
            Button("删除凭据和历史", role: .destructive) {
                deleteSelectedProvider(history: .delete)
            }
            Button("取消", role: .cancel) { deletionAccountID = nil }
        } message: {
            Text("凭据只从 Keychain 删除。保留历史时账户会停用，套餐、Token、余额与费用口径保持不变。")
        }
        .confirmationDialog(
            "确认清理历史",
            isPresented: Binding(
                get: { pendingHistoryClear != nil },
                set: { if !$0 { pendingHistoryClear = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("永久清理", role: .destructive) {
                guard let scope = pendingHistoryClear else { return }
                pendingHistoryClear = nil
                Task { await store.clearHistory(scope: scope) }
            }
            Button("取消", role: .cancel) { pendingHistoryClear = nil }
        } message: {
            Text("此操作只清理本地历史，不能撤销；Provider 配置和 Keychain 凭据不会删除。")
        }
    }

    private var sectionNavigation: some View {
        VStack(spacing: TokenDeskDesign.Spacing.small) {
            ForEach(SettingsSection.allCases, id: \.self) { section in
                Button(section.title) { store.selectedSection = section }
                    .buttonStyle(TokenDeskButtonStyle(isSelected: store.selectedSection == section))
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("settings-section-\(section.rawValue)")
            }
            Spacer()
        }
        .frame(width: 190)
    }

    @ViewBuilder
    private var sectionContent: some View {
        switch store.selectedSection {
        case .providers: providerSettings
        case .weather: weatherSettings
        case .display: displaySettings
        case .notifications: notificationSettings
        case .dataExport: dataExportSettings
        }
    }

    private var providerSettings: some View {
        settingsPanel("PROVIDERS") {
            if let draft = store.providerDraft {
                providerEditor(draft)
            } else {
                VStack(alignment: .leading, spacing: TokenDeskDesign.Spacing.medium) {
                    HStack {
                        Text("多账户按个人/组织、项目与工作空间隔离")
                            .font(TokenDeskTextStyle.auxiliary.font)
                        Spacer()
                        Button("添加 Provider") { store.beginAddingProvider() }
                            .buttonStyle(TokenDeskButtonStyle())
                            .accessibilityIdentifier("add-provider-button")
                    }
                    if store.providerConfigurations.isEmpty {
                        Text("尚未配置 Provider。添加后只有启用且已配置凭据的账户参与同步。")
                            .font(TokenDeskTextStyle.body.font)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ScrollView {
                            LazyVStack(spacing: TokenDeskDesign.Spacing.small) {
                                ForEach(store.providerConfigurations) { configuration in
                                    providerRow(configuration)
                                }
                            }
                        }
                        .accessibilityIdentifier("provider-settings-list")
                    }
                }
            }
        }
    }

    private func providerRow(_ configuration: ProviderAccountConfiguration) -> some View {
        VStack(alignment: .leading, spacing: TokenDeskDesign.Spacing.small) {
            HStack(alignment: .firstTextBaseline) {
                Text(configuration.providerDisplayName)
                    .font(TokenDeskTextStyle.cardTitle.font)
                Text("· \(configuration.accountDisplayName)")
                    .font(TokenDeskTextStyle.body.font)
                Text(configuration.scope == .personal ? "个人" : "组织")
                    .font(TokenDeskTextStyle.auxiliary.font)
                Spacer()
                Toggle(
                    "启用",
                    isOn: Binding(
                        get: { configuration.isEnabled },
                        set: { value in
                            Task {
                                await store.setProviderEnabled(
                                    value,
                                    accountID: configuration.accountID
                                )
                            }
                        }
                    )
                )
                .toggleStyle(.switch)
                .labelsHidden()
                Button("编辑") { store.beginEditingProvider(configuration) }
                Button("测试连接") {
                    Task { await store.testConnection(accountID: configuration.accountID) }
                }
                .disabled(configuration.credentialStatus != .configured || store.isWorking)
                Button("删除", role: .destructive) {
                    deletionAccountID = configuration.accountID
                }
            }
            HStack {
                Text("凭据：\(credentialLabel(configuration.credentialStatus))")
                Text("刷新：\(configuration.refreshIntervalMinutes) 分钟")
                Text("能力：\(capabilityLabel(for: configuration.providerType.rawValue))")
                Spacer()
            }
            .font(TokenDeskTextStyle.auxiliary.font)
            .foregroundStyle(TokenDeskDesign.Palette.inkMuted.color)
        }
        .padding(TokenDeskDesign.Spacing.medium)
        .overlay {
            Rectangle().stroke(
                TokenDeskDesign.Palette.ink.color,
                lineWidth: TokenDeskDesign.Border.regular
            )
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            "\(configuration.providerDisplayName)，\(configuration.accountDisplayName)")
    }

    private func providerEditor(_ draft: ProviderAccountDraft) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TokenDeskDesign.Spacing.medium) {
                HStack {
                    Picker(
                        "Provider",
                        selection: Binding(
                            get: { draft.providerType },
                            set: { store.selectProviderType($0) }
                        )
                    ) {
                        ForEach(ProviderSettingsOption.supported) { option in
                            Text(option.title).tag(option.id)
                        }
                    }
                    .disabled(draft.providerID != nil)
                    Text(capabilityLabel(for: draft.providerType))
                        .font(TokenDeskTextStyle.auxiliary.font)
                }
                TextField(
                    "Provider 显示名",
                    text: draftBinding(\.providerDisplayName, default: draft.providerDisplayName)
                )
                .textFieldStyle(.roundedBorder)
                TextField(
                    "账户别名",
                    text: draftBinding(\.accountDisplayName, default: draft.accountDisplayName)
                )
                .textFieldStyle(.roundedBorder)
                Picker("账户范围", selection: draftBinding(\.scope, default: draft.scope)) {
                    Text("个人").tag(AccountScope.personal)
                    Text("组织 / 团队").tag(AccountScope.organization)
                }
                if draft.scope == .organization {
                    HStack {
                        TextField(
                            "组织引用",
                            text: draftBinding(
                                \.organizationReference,
                                default: draft.organizationReference
                            )
                        )
                        TextField(
                            "项目引用",
                            text: draftBinding(\.projectReference, default: draft.projectReference)
                        )
                        TextField(
                            "工作空间引用",
                            text: draftBinding(
                                \.workspaceReference,
                                default: draft.workspaceReference
                            )
                        )
                    }
                    .textFieldStyle(.roundedBorder)
                    Text(providerOption(for: draft.providerType)?.organizationCredentialHint ?? "")
                        .font(TokenDeskTextStyle.auxiliary.font)
                }
                HStack {
                    Picker(
                        "刷新频率",
                        selection: draftBinding(
                            \.refreshIntervalMinutes,
                            default: draft.refreshIntervalMinutes
                        )
                    ) {
                        Text("5 分钟").tag(5)
                        Text("15 分钟").tag(15)
                        Text("30 分钟").tag(30)
                        Text("60 分钟").tag(60)
                    }
                    Toggle(
                        "启用",
                        isOn: draftBinding(\.isEnabled, default: draft.isEnabled)
                    )
                }
                HStack {
                    Text(draft.accountID == nil ? "API / 管理密钥" : "替换密钥（留空则不变）")
                    SecureCredentialField { store.stageReplacementCredential($0) }
                        .frame(height: 28)
                        .accessibilityLabel("Provider 凭据")
                }
                Text("密钥只会写入 Keychain；保存后不回显，也不会写入 SQLite、日志或导出。")
                    .font(TokenDeskTextStyle.auxiliary.font)
                HStack {
                    Spacer()
                    Button("取消") { store.cancelProviderEditing() }
                    Button("保存") { Task { await store.saveProvider() } }
                        .buttonStyle(TokenDeskButtonStyle())
                        .disabled(store.isWorking)
                        .accessibilityIdentifier("save-provider-button")
                }
            }
            .padding(.trailing, TokenDeskDesign.Spacing.small)
        }
    }

    private var weatherSettings: some View {
        settingsPanel("时间与天气") {
            VStack(alignment: .leading, spacing: TokenDeskDesign.Spacing.medium) {
                settingsRow("定位权限", detail: authorizationLabel(store.locationAuthorization))
                HStack {
                    TextField("手工城市", text: $store.preferences.manualCity)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("manual-city-field")
                    Button("验证城市") { Task { await store.resolveManualCity() } }
                    Button("使用当前位置") { Task { await store.requestCurrentLocation() } }
                }
                HStack {
                    Picker("天气源", selection: weatherProviderBinding) {
                        Text("Open-Meteo（公开 API）").tag("open-meteo")
                    }
                    Picker("天气刷新", selection: weatherRefreshBinding) {
                        Text("15 分钟").tag(15)
                        Text("30 分钟").tag(30)
                        Text("60 分钟").tag(60)
                    }
                }
                Picker("时区", selection: timeZoneBinding) {
                    Text("跟随系统").tag("")
                    Text("上海").tag("Asia/Shanghai")
                    Text("东京").tag("Asia/Tokyo")
                    Text("洛杉矶").tag("America/Los_Angeles")
                }
                Toggle("展示逐小时天气", isOn: hourlyWeatherBinding)
                Text("拒绝定位不会阻止手工城市天气；应用不保存位置轨迹。")
                    .font(TokenDeskTextStyle.auxiliary.font)
                platformSaveBar
            }
        }
    }

    private var displaySettings: some View {
        settingsPanel("显示") {
            VStack(alignment: .leading, spacing: TokenDeskDesign.Spacing.large) {
                Picker("目标屏幕", selection: $store.selectedDisplayRuntimeID) {
                    Text("自动识别 Wokyis M5").tag(UInt32?.none)
                    ForEach(store.displayTargets) { display in
                        Text("\(display.name) · \(display.logicalWidth)×\(display.logicalHeight)")
                            .tag(Optional(display.id))
                    }
                }
                .accessibilityIdentifier("target-display-picker")
                settingsRow("逻辑画布", detail: "固定 1280 × 720；其他模式统一等比缩放")
                Toggle("登录后自动启动", isOn: launchAtLoginBinding)
                    .accessibilityIdentifier("launch-at-login-toggle")
                settingsRow("登录项状态", detail: launchStatusLabel)
                Text("登录启动由 macOS 立即管理；目标屏幕在点击保存后切换。")
                    .font(TokenDeskTextStyle.auxiliary.font)
                platformSaveBar
            }
        }
    }

    private var notificationSettings: some View {
        settingsPanel("通知") {
            VStack(alignment: .leading, spacing: TokenDeskDesign.Spacing.large) {
                settingsRow("系统权限", detail: authorizationLabel(store.notificationAuthorization))
                Toggle("启用本地告警", isOn: alertsBinding)
                    .accessibilityIdentifier("alerts-toggle")
                settingsRow("套餐与预算阈值", detail: "80% · 95% · 100%")
                settingsRow("连续同步失败", detail: "30 分钟")
                settingsRow("重复提醒冷却", detail: "60 分钟")
                Button("发送测试通知") { Task { await store.sendTestNotification() } }
                    .disabled(store.notificationAuthorization != .authorized)
                Text("只有主动开启告警时才会请求权限；通知正文不包含凭据。")
                    .font(TokenDeskTextStyle.auxiliary.font)
                platformSaveBar
            }
        }
    }

    private var dataExportSettings: some View {
        settingsPanel("数据与导出") {
            VStack(alignment: .leading, spacing: TokenDeskDesign.Spacing.small) {
                settingsRow("本地占用", detail: historyStorageLabel)
                settingsRow("保留策略", detail: "分钟 7 天 · 小时 90 天 · 每日 2 年")
                HStack {
                    DatePicker("开始", selection: $store.exportStartDate, displayedComponents: .date)
                    DatePicker("结束", selection: $store.exportEndDate, displayedComponents: .date)
                }
                HStack {
                    Picker("Provider", selection: exportProviderBinding) {
                        Text("全部").tag(ProviderID?.none)
                        ForEach(uniqueProviders, id: \.providerID) { configuration in
                            Text(configuration.providerDisplayName).tag(
                                Optional(configuration.providerID))
                        }
                    }
                    Picker("账户", selection: $store.exportAccountID) {
                        Text("全部").tag(AccountID?.none)
                        ForEach(exportAccounts, id: \.accountID) { configuration in
                            Text(configuration.accountDisplayName).tag(
                                Optional(configuration.accountID))
                        }
                    }
                    TextField("项目筛选（可选）", text: $store.exportProjectReference)
                }
                HStack {
                    Text("Token 粒度")
                    ForEach([UsageGranularity.minute, .hour, .day], id: \.self) { granularity in
                        Toggle(granularityLabel(granularity), isOn: granularityBinding(granularity))
                            .toggleStyle(.checkbox)
                    }
                    Spacer()
                    Picker("格式", selection: exportFormatBinding) {
                        Text("CSV · BOM").tag("csv")
                        Text("JSON").tag("json")
                    }
                    .frame(width: 170)
                }
                HStack {
                    Button("选择位置并导出") { Task { await store.exportHistory() } }
                        .buttonStyle(TokenDeskButtonStyle())
                        .disabled(store.exportEndDate <= store.exportStartDate)
                        .accessibilityIdentifier("export-history-button")
                    Button("清理所选 Provider", role: .destructive) {
                        if let providerID = store.exportProviderID {
                            pendingHistoryClear = .provider(providerID)
                        }
                    }
                    .disabled(store.exportProviderID == nil)
                    Button("清空全部历史", role: .destructive) {
                        pendingHistoryClear = .all
                    }
                }
                Text("仅写入系统保存面板中选定的文件；不导出密钥、Prompt 或响应正文。")
                    .font(TokenDeskTextStyle.auxiliary.font)
                platformSaveBar
            }
        }
    }

    private var historyStorageLabel: String {
        guard let snapshot = store.historyStorage else { return "正在读取" }
        let bytes = ByteCountFormatter.string(
            fromByteCount: snapshot.databaseBytes, countStyle: .file)
        return "\(bytes) · \(snapshot.historyRows) 条历史"
    }

    private var uniqueProviders: [ProviderAccountConfiguration] {
        var seen: Set<ProviderID> = []
        return store.providerConfigurations.filter { seen.insert($0.providerID).inserted }
    }

    private var exportAccounts: [ProviderAccountConfiguration] {
        store.providerConfigurations.filter {
            store.exportProviderID == nil || $0.providerID == store.exportProviderID
        }
    }

    private var exportProviderBinding: Binding<ProviderID?> {
        Binding(
            get: { store.exportProviderID },
            set: { store.setExportProvider($0) }
        )
    }

    private func granularityBinding(_ granularity: UsageGranularity) -> Binding<Bool> {
        Binding(
            get: { store.exportGranularities.contains(granularity) },
            set: { _ in store.toggleExportGranularity(granularity) }
        )
    }

    private func granularityLabel(_ granularity: UsageGranularity) -> String {
        switch granularity {
        case .minute: "分钟"
        case .hour: "小时"
        case .day: "每日"
        case .week: "每周"
        case .month: "每月"
        }
    }

    private var platformSaveBar: some View {
        HStack {
            Spacer()
            Button("取消更改") {
                store.cancelPlatformChanges()
                _ = clock.setTimeZoneOverride(
                    identifier: store.preferences.timeZoneOverrideIdentifier
                )
            }
            Button("保存设置") {
                store.savePlatformChanges()
                _ = clock.setTimeZoneOverride(
                    identifier: store.preferences.timeZoneOverrideIdentifier
                )
            }
            .buttonStyle(TokenDeskButtonStyle())
            .disabled(!store.hasUnsavedPlatformChanges)
            .accessibilityIdentifier("save-platform-settings-button")
        }
    }

    private func settingsRow(_ title: String, detail: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(TokenDeskTextStyle.cardTitle.font)
            Spacer()
            Text(detail)
                .font(TokenDeskTextStyle.body.font)
                .foregroundStyle(TokenDeskDesign.Palette.inkMuted.color)
                .multilineTextAlignment(.trailing)
        }
    }

    private func settingsPanel<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(spacing: 0) {
            ZStack {
                TokenDeskPatternFill(.horizontal)
                Text(title)
                    .font(TokenDeskTextStyle.cardTitle.font)
                    .padding(.horizontal, TokenDeskDesign.Spacing.medium)
                    .background(TokenDeskDesign.Palette.paper.color)
            }
            .frame(height: 36)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(TokenDeskDesign.Palette.ink.color)
                    .frame(height: TokenDeskDesign.Border.regular)
            }
            content()
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(TokenDeskDesign.Spacing.large)
            Spacer(minLength: 0)
        }
        .frame(width: 1_026, height: 450, alignment: .topLeading)
        .background(TokenDeskDesign.Palette.paper.color)
        .overlay {
            Rectangle().stroke(
                TokenDeskDesign.Palette.ink.color,
                lineWidth: TokenDeskDesign.Border.regular
            )
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }

    private func draftBinding<Value>(
        _ keyPath: WritableKeyPath<ProviderAccountDraft, Value>,
        default defaultValue: Value
    )
        -> Binding<Value>
    {
        Binding(
            get: { store.providerDraft?[keyPath: keyPath] ?? defaultValue },
            set: { value in store.providerDraft?[keyPath: keyPath] = value }
        )
    }

    private var timeZoneBinding: Binding<String> {
        Binding(
            get: { store.preferences.timeZoneOverrideIdentifier ?? "" },
            set: { value in
                let identifier = value.isEmpty ? nil : value
                store.setTimeZoneOverride(identifier)
                _ = clock.setTimeZoneOverride(identifier: identifier)
            }
        )
    }

    private var weatherProviderBinding: Binding<String> {
        Binding(
            get: { store.preferences.weatherProvider },
            set: { store.setWeatherProvider($0) }
        )
    }

    private var weatherRefreshBinding: Binding<Int> {
        Binding(
            get: { store.preferences.weatherRefreshMinutes },
            set: { store.setWeatherRefreshMinutes($0) }
        )
    }

    private var hourlyWeatherBinding: Binding<Bool> {
        Binding(
            get: { store.preferences.showsHourlyWeather },
            set: { store.setShowsHourlyWeather($0) }
        )
    }

    private var alertsBinding: Binding<Bool> {
        Binding(
            get: { store.preferences.alertsEnabled },
            set: { value in Task { await store.setAlertsEnabled(value) } }
        )
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { store.launchAtLoginStatus == .enabled },
            set: { store.setLaunchAtLogin($0) }
        )
    }

    private var exportFormatBinding: Binding<String> {
        Binding(
            get: { store.preferences.exportFormat.rawValue },
            set: { value in
                guard let format = HistoryExportFormat(rawValue: value) else { return }
                store.setExportFormat(format)
            }
        )
    }

    private var launchStatusLabel: String {
        switch store.launchAtLoginStatus {
        case .disabled: "已关闭"
        case .enabled: "已启用"
        case .requiresApproval: "等待系统设置批准"
        case .unavailable: "当前不可用"
        }
    }

    private func authorizationLabel(_ authorization: PermissionAuthorization) -> String {
        switch authorization {
        case .notDetermined: "尚未请求"
        case .denied: "已拒绝"
        case .authorized: "已允许"
        case .restricted: "受系统限制"
        case .unavailable: "当前不可用"
        }
    }

    private func credentialLabel(_ status: CredentialConfigurationStatus) -> String {
        status == .configured ? "已配置（不回显）" : "未配置"
    }

    private func capabilityLabel(for providerType: String) -> String {
        guard let option = providerOption(for: providerType) else { return "按 Connector 声明" }
        return option.capabilities.map(capabilityTitle).joined(separator: " / ")
    }

    private func capabilityTitle(_ capability: ProviderCapability) -> String {
        switch capability {
        case .plan: "套餐"
        case .usage: "Token"
        case .cost: "费用"
        case .balance: "余额"
        case .localEstimate: "本地估算"
        }
    }

    private func providerOption(for type: String) -> ProviderSettingsOption? {
        ProviderSettingsOption.supported.first { $0.id == type }
    }

    private func deleteSelectedProvider(history: ProviderHistoryDisposition) {
        guard let accountID = deletionAccountID else { return }
        deletionAccountID = nil
        Task { await store.deleteProvider(accountID: accountID, history: history) }
    }
}

/// AppKit secure input keeps credential characters out of observable SwiftUI state.
private struct SecureCredentialField: NSViewRepresentable {
    let onChange: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onChange: onChange) }

    func makeNSView(context: Context) -> NSSecureTextField {
        let field = NSSecureTextField()
        field.placeholderString = "保存后不回显"
        field.delegate = context.coordinator
        return field
    }

    func updateNSView(_ nsView: NSSecureTextField, context: Context) {}

    final class Coordinator: NSObject, NSTextFieldDelegate {
        let onChange: (String) -> Void

        init(onChange: @escaping (String) -> Void) { self.onChange = onChange }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSSecureTextField else { return }
            onChange(field.stringValue)
        }
    }
}
