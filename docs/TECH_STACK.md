# Token Desk 技术栈与架构决策

> 版本：1.0  
> 日期：2026-08-11  
> 输入：[PRD](./PRD.md)、[交互原型](../prototype/index.html)  
> 状态：MVP 实施基线；带“验证门”的项目需在 M0 完成后锁定

## 1. 结论

MVP 采用 **macOS 原生技术栈：Swift 6 + SwiftUI + AppKit**。HTML 原型只作为布局、视觉和交互基准，不进入生产包。数据层使用 **SQLite + GRDB**，系统能力优先使用 Apple 原生框架，不引入 Electron、Tauri、跨平台 UI 框架或远程后端。

选择原生方案的主要原因：

- 产品只面向 macOS，需要可靠处理 `NSScreen`、无边框窗口、休眠/重连、Keychain、App Sandbox 和 Mac App Store。
- 常驻应用对启动时间、内存和空闲 CPU 有明确要求。
- SwiftUI 适合固定看板和设置表单，AppKit 补足窗口与显示器控制。
- 数据默认仅保存在本机，不需要为 MVP 建设服务端。

## 2. 平台与构建基线

| 项目 | 决策 |
|---|---|
| 目标平台 | macOS 14 Sonoma 及以上，Apple Silicon 与 Intel 通用构建 |
| 语言模式 | Swift 6，开启严格并发检查；编译器补丁版本由 CI 使用的稳定 Xcode 锁定 |
| IDE / SDK | 当前可提交 Mac App Store 的稳定 Xcode；M0 结束时写入 `.xcode-version` 并记录 build number |
| UI | SwiftUI；仅显示器、窗口和保存面板等系统边界使用 AppKit |
| 包管理 | Swift Package Manager；提交 `Package.resolved`，禁止 branch 依赖 |
| 分发 | Mac App Store，Release 从第一天启用 App Sandbox 与 Hardened Runtime |
| 最低系统版本依据 | `Observation`、现代 SwiftUI、ServiceManagement API 可直接使用，降低兼容分支与长期运行风险 |

若产品必须覆盖 macOS 13，需要单独 ADR 评审，并将 `@Observable` 状态层改为兼容实现；不得在开发中临时下调版本。

## 3. 技术栈清单

### 3.1 Apple 框架

| 领域 | 技术 | 用途 |
|---|---|---|
| 应用 UI | SwiftUI | 总览、套餐、Token、设置、错误/空状态 |
| 窗口与副屏 | AppKit (`NSWindow`, `NSScreen`) | 目标屏识别、窗口定位、断连与恢复 |
| 状态观察 | Observation (`@Observable`) | 页面状态与可测试 Store |
| 图表 | Swift Charts | 输入/输出 Token 分桶图与可访问性摘要 |
| 网络 | Foundation `URLSession` | Provider、Open-Meteo 与连接测试 |
| 并发 | Swift Concurrency | `async/await`、TaskGroup、actor 隔离与取消 |
| 凭据 | Security / Keychain Services | API Key、Admin Key、管理密钥 |
| 定位 | Core Location | 一次性获取天气坐标；手工城市回退 |
| 通知 | UserNotifications | 套餐、预算、余额、同步失败告警 |
| 登录启动 | ServiceManagement (`SMAppService`) | 用户主动开启登录启动 |
| 文件导出 | `NSSavePanel` | 在沙箱中获取单次导出位置写权限 |
| 诊断 | Unified Logging (`Logger`) | 本地、隐私安全的结构化诊断 |

### 3.2 第三方依赖

MVP 只引入一个运行时依赖：

| 依赖 | 版本策略 | 用途 | 采用理由 |
|---|---|---|---|
| [GRDB.swift](https://github.com/groue/GRDB.swift) | SPM `upToNextMajor(from: "7.11.1")`，由 `Package.resolved` 锁定 | SQLite 迁移、事务、查询、并发读写 | 避免自行维护 SQLite C API 封装，同时保留明确 schema 与 SQL 控制 |

开发工具使用 Swift 6 工具链自带的 [`swift format`](https://github.com/swiftlang/swift-format)，不作为 App 运行时依赖。新增依赖必须提交 ADR，说明许可证、二进制体积、维护状态、沙箱与隐私影响。

明确不采用：

- Electron：常驻资源开销与原生系统集成成本不符合目标。
- Tauri/WebView：本项目没有跨平台目标，显示器和沙箱能力仍需大量原生桥接。
- SwiftData/Core Data：历史分桶、保留策略、批量聚合和导出更适合显式 SQLite schema；GRDB 更便于迁移与查询验证。
- Combine 作为业务主干：新代码统一使用 Observation 与 Swift Concurrency；只在系统 API 强制要求时局部适配。
- 自建后端或远程遥测：不属于 MVP，且违背本地优先原则。

## 4. 工程结构

使用一个 Xcode App 工程加一个仓库内 Local Swift Package。模块依赖保持单向：

```text
TokenDeskApp                 组合根、生命周期、Entitlements
├── TokenDeskFeatures       页面 Store、ViewState、SwiftUI 页面
│   ├── TokenDeskCore       领域模型、协议、纯业务规则
│   └── TokenDeskDesign     1-bit 视觉组件、字体与布局 Token
├── TokenDeskData           GRDB、Keychain、Preferences、导出
│   └── TokenDeskCore
├── TokenDeskConnectors     Provider、天气 HTTP 实现
│   └── TokenDeskCore
└── TokenDeskPlatform       NSScreen、通知、定位、登录启动
    └── TokenDeskCore
```

每个模块有独立测试 Target。`TokenDeskFeatures` 不导入具体 Connector 或 GRDB；App 组合根通过协议注入实现。Provider 私有 DTO 只存在于 `TokenDeskConnectors` 内。

建议目录：

```text
TokenDesk/
├── App/
├── Packages/TokenDeskKit/
│   ├── Sources/
│   │   ├── TokenDeskCore/
│   │   ├── TokenDeskData/
│   │   ├── TokenDeskConnectors/
│   │   ├── TokenDeskPlatform/
│   │   ├── TokenDeskDesign/
│   │   └── TokenDeskFeatures/
│   └── Tests/
├── TokenDeskUITests/
├── Config/
└── Fixtures/
```

## 5. 运行时架构

### 5.1 状态与数据流

```text
SwiftUI View
  -> Feature Store (@MainActor, @Observable)
  -> Use Case / Repository protocol
  -> SyncCoordinator actor
  -> Connector actor / Database repository
  -> Domain model
  -> ViewState
```

- View 只发送用户意图并渲染 `ViewState`，不直接请求网络或访问数据库。
- `DashboardStore` 运行在 `@MainActor`，长任务通过注入服务异步执行。
- `SyncCoordinator` 使用 actor 隔离；各 Provider 并行同步，单个失败不取消其他任务。
- 页面切换使用 `AppRoute` 枚举：`.overview`、`.plans`、`.tokens`、`.settings`。
- 首屏先读数据库缓存，再发起异步刷新；所有展示值都携带来源、更新时间和过期状态。

### 5.2 Connector 契约

```swift
protocol ProviderConnector: Sendable {
    var descriptor: ProviderDescriptor { get }
    func validateCredentials(for account: AccountReference) async throws
    func fetchAccounts() async throws -> [RemoteAccount]
    func fetchPlan() async throws -> [PlanWindow]
    func fetchBalance() async throws -> [BalanceSnapshot]
    func fetchUsage(in interval: DateInterval) async throws -> [UsageBucket]
    func fetchHealth() async -> ConnectorHealth
}
```

具体 Connector 通过能力集合声明支持项，例如 `plan`、`usage`、`cost`、`balance`。不支持某能力时返回 `.unsupported`，不能用空数组伪装成功。Connector 输出统一领域对象，UI 不读取厂商 JSON 字段。

MVP Connector 分三类：

1. 官方聚合 API：OpenAI、Anthropic、OpenRouter、DeepSeek Balance。
2. 响应 usage 本地聚合：Gemini、GLM、Kimi、MiniMax 等官方历史能力不足的场景。
3. 套餐窗口：Codex App Server 或 Provider 官方能力；无法在沙箱内合规获得时，只能降级为明确标注的本地估算/演示数据，不允许抓网页、读 Cookie 或读取其他 App 私有容器。

### 5.3 同步策略

- 时间：本地每秒更新，只修改时钟 ViewState。
- 天气：15 分钟；套餐/Token：60 秒；费用/余额：5 分钟。
- 请求通过 `TaskGroup` 按 Provider 并行，账户内按 API 限流要求串行或限并发。
- 失败重试只适用于幂等读取；指数退避加随机抖动，上限 30 分钟。
- 支持 Task 取消，应用休眠、账户停用或 Provider 删除后不得继续写入。
- HTTP 429 尊重 `Retry-After`；认证失败不自动重试并立即更新健康状态。

## 6. 数据设计

### 6.1 类型约束

- Token 数量：`Int64`，禁止 `Double`。
- 金额：`Decimal` + ISO 4217 币种；不同币种默认不相加。
- 时间：数据库统一存 UTC，UI 与分桶边界使用账户/用户选择时区计算。
- 百分比：领域层保存 `Decimal` 或受约束值对象，渲染时再格式化。
- ID：本地 UUID/强类型 ID；完整远端组织标识不得进入普通日志。
- 套餐窗口与 Token 用量为不同聚合根，不提供二者相加的 API。

### 6.2 SQLite

采用 PRD 第 20 节表设计，并增加：

- `schema_migrations`：显式、只前进迁移。
- 所有快照表具有 `provider_id`、`account_id`、`source`、`updated_at`。
- `usage_buckets` 唯一键至少包含账户、Provider、项目、模型、粒度和起始时间。
- 金额以规范化十进制字符串或缩放整数存储，禁止 SQLite `REAL`。
- 启用 foreign keys 与 WAL；写入使用事务，UI 查询使用只读快照。
- 保留任务每日运行：分钟 7 天、小时 90 天、日数据 2 年；先聚合再删除。

### 6.3 Keychain 与设置

- SQLite 只保存凭据引用，不保存密钥本体。
- Keychain item 以本地账户 UUID 为 key，启用设备解锁后可用的适当访问级别，不同步到 iCloud。
- 非敏感偏好放 `UserDefaults`；复杂且需查询的数据放 SQLite。
- 删除 Provider 时先删除/保留历史数据，再独立删除 Keychain item；任一步失败都要给出可恢复状态。

## 7. UI 实现基线

原型坐标系固定为 1280×720，生产实现保留相同信息密度和四页面结构：

| 页面 | 原型基线 | 实现要求 |
|---|---|---|
| 全局头部 | 高 58；总览/套餐/Token；同步；唯一设置入口 | `AppHeader` 固定，设置入口不得复制到内容区 |
| 总览 | 左侧时钟/天气，右侧主套餐与 2 个 Provider 摘要 | `OverviewGrid` 固定布局，无滚动、拖拽、缩放 |
| 套餐 | 多额度卡 + 口径说明 | 官方/估算同时用文字、图形区分 |
| Token | 246 宽 Provider 列表 + 指标/图表/页脚 | Provider 和日/周/月切换必须整体更新 ViewState |
| 设置 | Providers、时间与天气、显示 | PRD 还要求通知、数据与导出，生产版补齐为五个页签或分组 |

`DisplayController` 用 AppKit 将 1280×720 设计画布放置到目标屏幕。M0 必须验证 `NSScreen.frame`、`backingScaleFactor` 和实际像素的映射；如果系统暴露的是非 1280×720 逻辑尺寸，只做统一等比缩放，不做逐组件响应式重排。

视觉由 `TokenDeskDesign` 提供语义 Token：`ink`、`paper`、`surfaceMuted`、边框 2/3 px、斜线/网点 Pattern、字体层级和 40×40 最小交互尺寸。业务页面不得散落硬编码颜色和字体。

## 8. 沙箱与权限

| 能力 | 策略 |
|---|---|
| 网络 | 仅启用 outgoing client；Provider Base URL 必须为 HTTPS |
| 定位 | 用户点击“使用当前位置”时请求；拒绝后保留手工城市 |
| 通知 | 用户主动开启告警时请求；拒绝不影响其余功能 |
| 文件 | CSV/JSON 使用 `NSSavePanel` 单次授权；MVP 不需要广泛目录权限 |
| 登录启动 | 用户开关触发 `SMAppService`；默认关闭 |
| 其他 App 数据 | 不申请临时例外，不读取 Cookie、私有容器或浏览器数据 |

## 9. 测试与质量工具

- 领域、价格、聚合、告警和迁移：Swift Testing。
- AppKit 生命周期、通知与兼容测试：XCTest。
- 四页面、键盘 `1/2/3`、唯一设置入口、导出面板：XCUITest。
- Connector：URLProtocol Stub + 脱敏 JSON fixture + 契约测试；CI 不访问真实 Provider。
- UI：1280×720 截图基线、VoiceOver 标签、Reduce Motion 与 0/100/超长文本边界。
- 性能：`XCTMetric`/Instruments，覆盖冷启动、页面切换、同步、72 小时 soak。
- 格式：`swift format lint --strict --recursive`；构建阶段不自动改写代码。

## 10. 必须先完成的验证门

以下事项不能靠文档假定为可用：

| 编号 | 验证 | 通过条件 | 失败处理 |
|---|---|---|---|
| GATE-01 | Wokyis M5 真机识别与重连 | 直连/扩展坞、睡眠、拔插均在 5 秒内恢复到正确屏 | 保留手选屏并调整匹配策略 |
| GATE-02 | Codex App Server + App Sandbox | **未通过（2026-08-11）**：只读字段可用，但 app-server 仍为实验性且不支持生产，Release 沙箱、凭据存储和审核包未验证；见 `docs/spikes/GATE-02_CODEX_APP_SERVER_SANDBOX.md` | 将真实接入移出 P0；仅保留 `.unsupported` 与明确 Fixture 演示，不以估算冒充官方额度 |
| GATE-03 | 九个 Provider 能力矩阵 | 每项确认凭据、账户层级、历史/余额/费用接口与限流 | 按 capability 降级，不伪造统一能力 |
| GATE-04 | GRDB + 沙箱数据库 | 迁移、WAL、并发读写、容器路径和导出均通过 | 在 M1 前调整封装，不在业务层散写 SQL |
| GATE-05 | 1280×720 真机可读性 | 正文 ≥14、辅助 ≥11、核心数字 3 秒可读，无裁切 | 调整 Design Token 和原型差异清单 |

## 11. 架构决策记录

| ADR | 决策 | 状态 |
|---|---|---|
| ADR-001 | 原生 SwiftUI + AppKit，HTML 仅作原型 | Accepted |
| ADR-002 | macOS 14+，Swift 6 严格并发 | Accepted |
| ADR-003 | SQLite + GRDB 7.x，不使用 SwiftData | Accepted |
| ADR-004 | 本地优先，无后端、无默认远程遥测 | Accepted |
| ADR-005 | Connector capability + 统一领域对象 | Accepted |
| ADR-006 | Provider 同步 actor 隔离，失败互不影响 | Accepted |
| ADR-007 | 固定 1280×720 设计画布，仅整体缩放 | Accepted，待 GATE-01/05 验证 |
| ADR-008 | Codex 数据只走官方且沙箱合规的能力 | Accepted；GATE-02 未通过，真实 Connector 移出 P0，满足 spike 重开条件后再评估 |

## 12. 参考

- [Apple NSScreen](https://developer.apple.com/documentation/AppKit/NSScreen/screens)
- [Apple App Sandbox](https://developer.apple.com/documentation/xcode/configuring-the-macos-app-sandbox)
- [Apple SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice)
- [Swift Charts](https://developer.apple.com/documentation/charts)
- [GRDB.swift](https://github.com/groue/GRDB.swift)
- [swift-format](https://github.com/swiftlang/swift-format)
