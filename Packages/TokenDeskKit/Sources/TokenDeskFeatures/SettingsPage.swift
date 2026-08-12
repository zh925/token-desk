import SwiftUI
import TokenDeskCore
import TokenDeskDesign

/// The product's single settings destination, grouped into five platform-aware sections.
public struct SettingsPage: View {
    @Bindable private var store: SettingsStore
    @Bindable private var clock: DashboardClock

    /// Creates the settings page with injected feature state and dashboard clock.
    public init(store: SettingsStore, clock: DashboardClock) {
        self.store = store
        self.clock = clock
    }

    /// Five-section settings layout constrained to the app's fixed content canvas.
    public var body: some View {
        VStack(spacing: TokenDeskDesign.Spacing.large) {
            PageHeading(
                title: "设置页面",
                subtitle: "所有配置、权限与导出均从此唯一入口管理",
                code: "SETTINGS · SINGLE ENTRY"
            )

            HStack(alignment: .top, spacing: TokenDeskDesign.Spacing.large) {
                sectionNavigation
                sectionContent
                    .frame(width: 1_026, height: 450, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            if let message = store.operationMessage {
                Text(message)
                    .font(TokenDeskTextStyle.auxiliary.font)
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
    }

    private var sectionNavigation: some View {
        VStack(spacing: TokenDeskDesign.Spacing.small) {
            ForEach(SettingsSection.allCases, id: \.self) { section in
                Button(section.title) {
                    store.selectedSection = section
                }
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
        case .providers:
            providerSettings
        case .weather:
            weatherSettings
        case .display:
            displaySettings
        case .notifications:
            notificationSettings
        case .dataExport:
            dataExportSettings
        }
    }

    private var providerSettings: some View {
        settingsPanel("PROVIDERS") {
            VStack(alignment: .leading, spacing: TokenDeskDesign.Spacing.large) {
                settingsRow("账户范围", detail: "个人与组织账户保持独立口径")
                settingsRow("凭据", detail: "仅存 Keychain，页面不回显完整密钥")
                settingsRow("计费形式", detail: "套餐、Token、余额与费用不混算")
                Divider()
                Text("Provider 编辑、连接测试与删除确认将在账户接线批次启用。")
                    .font(TokenDeskTextStyle.body.font)
                Button("添加 Provider") {}
                    .buttonStyle(TokenDeskButtonStyle())
                    .disabled(true)
                    .accessibilityHint("账户接线批次启用")
            }
        }
    }

    private var weatherSettings: some View {
        settingsPanel("时间与天气") {
            VStack(alignment: .leading, spacing: TokenDeskDesign.Spacing.large) {
                settingsRow("定位权限", detail: authorizationLabel(store.locationAuthorization))
                HStack {
                    TextField("手工城市", text: $store.preferences.manualCity)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("manual-city-field")
                    Button("使用手工城市") {
                        Task { await store.resolveManualCity() }
                    }
                    .buttonStyle(TokenDeskButtonStyle())
                    Button("使用当前位置") {
                        Task { await store.requestCurrentLocation() }
                    }
                    .buttonStyle(TokenDeskButtonStyle())
                }
                Picker("时区", selection: timeZoneBinding) {
                    Text("跟随系统").tag("")
                    Text("上海").tag("Asia/Shanghai")
                    Text("东京").tag("Asia/Tokyo")
                    Text("洛杉矶").tag("America/Los_Angeles")
                }
                Picker("天气刷新", selection: weatherRefreshBinding) {
                    Text("15 分钟").tag(15)
                    Text("30 分钟").tag(30)
                    Text("60 分钟").tag(60)
                }
                Toggle("展示逐小时天气", isOn: hourlyWeatherBinding)
                Text("拒绝定位不会阻止手工城市天气；应用不保存位置轨迹。")
                    .font(TokenDeskTextStyle.auxiliary.font)
            }
        }
    }

    private var displaySettings: some View {
        settingsPanel("显示") {
            VStack(alignment: .leading, spacing: TokenDeskDesign.Spacing.large) {
                settingsRow("目标屏幕", detail: "Wokyis M5 · 自动识别 / 可手选")
                settingsRow("逻辑画布", detail: "固定 1280 × 720")
                Toggle("副屏连接后自动打开", isOn: .constant(true))
                    .disabled(true)
                Toggle("登录后自动启动", isOn: launchAtLoginBinding)
                    .accessibilityIdentifier("launch-at-login-toggle")
                settingsRow("登录项状态", detail: launchStatusLabel)
                settingsRow("夜间亮度与防烧屏", detail: "后续显示设置接线批次启用")
            }
        }
    }

    private var notificationSettings: some View {
        settingsPanel("通知") {
            VStack(alignment: .leading, spacing: TokenDeskDesign.Spacing.large) {
                settingsRow(
                    "系统权限",
                    detail: authorizationLabel(store.notificationAuthorization)
                )
                Toggle("启用本地告警", isOn: alertsBinding)
                    .accessibilityIdentifier("alerts-toggle")
                settingsRow("套餐与预算阈值", detail: "80% · 95% · 100%")
                settingsRow("连续同步失败", detail: "30 分钟")
                settingsRow("重复提醒冷却", detail: "60 分钟")
                Button("发送测试通知") {
                    Task { await store.sendTestNotification() }
                }
                .buttonStyle(TokenDeskButtonStyle())
                .disabled(store.notificationAuthorization != .authorized)
                Text("只有主动开启告警时才会请求权限；通知正文不包含凭据。")
                    .font(TokenDeskTextStyle.auxiliary.font)
            }
        }
    }

    private var dataExportSettings: some View {
        settingsPanel("数据与导出") {
            VStack(alignment: .leading, spacing: TokenDeskDesign.Spacing.large) {
                settingsRow("分钟历史", detail: "保留 7 天")
                settingsRow("小时历史", detail: "保留 90 天")
                settingsRow("每日历史", detail: "默认保留 2 年")
                Picker("导出格式", selection: exportFormatBinding) {
                    Text("CSV · UTF-8 BOM").tag("csv")
                    Text("JSON").tag("json")
                }
                Button("选择位置并导出") {
                    Task { await store.exportHistoryFoundation() }
                }
                .buttonStyle(TokenDeskButtonStyle())
                .accessibilityIdentifier("export-history-button")
                Text("仅写入系统保存面板中选定的文件；不导出密钥、Prompt 或响应正文。")
                    .font(TokenDeskTextStyle.auxiliary.font)
            }
        }
    }

    private func settingsRow(_ title: String, detail: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(TokenDeskTextStyle.cardTitle.font)
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
            Rectangle()
                .stroke(
                    TokenDeskDesign.Palette.ink.color,
                    lineWidth: TokenDeskDesign.Border.regular
                )
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
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

    private var weatherRefreshBinding: Binding<Int> {
        Binding(
            get: { store.preferences.weatherRefreshMinutes },
            set: { minutes in store.setWeatherRefreshMinutes(minutes) }
        )
    }

    private var hourlyWeatherBinding: Binding<Bool> {
        Binding(
            get: { store.preferences.showsHourlyWeather },
            set: { isEnabled in store.setShowsHourlyWeather(isEnabled) }
        )
    }

    private var alertsBinding: Binding<Bool> {
        Binding(
            get: { store.preferences.alertsEnabled },
            set: { isEnabled in Task { await store.setAlertsEnabled(isEnabled) } }
        )
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { store.launchAtLoginStatus == .enabled },
            set: { isEnabled in store.setLaunchAtLogin(isEnabled) }
        )
    }

    private var exportFormatBinding: Binding<String> {
        Binding(
            get: { store.preferences.exportFormat.rawValue },
            set: { rawValue in
                guard let format = HistoryExportFormat(rawValue: rawValue) else { return }
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
}
