# Token Desk 编码规范

> 版本：1.0  
> 适用范围：App、Local Swift Package、测试、迁移、Fixture 与构建脚本  
> 相关文档：[技术栈](./TECH_STACK.md)、[开发计划](./DEVELOPMENT_PLAN.md)

## 1. 基本原则

1. **正确口径优先**：套餐窗口、Token、余额和费用是不同概念，禁止为 UI 方便而混算。
2. **本地与隐私优先**：最小化权限、存储和日志；密钥只进 Keychain。
3. **可失败设计**：任何 Provider、网络或权限失败都必须能降级，不得拖垮整个看板。
4. **协议隔离外部系统**：View 和领域层不接触 Provider DTO、HTTP 状态码或 SQL 行。
5. **可验证**：业务规则、迁移、Connector 映射和 UI 状态都要有自动化测试。

## 2. 格式化与文件

- 使用工具链自带 `swift format`；仓库根目录提交 `.swift-format`。
- CI 执行：`swift format lint --strict --recursive Packages TokenDesk TokenDeskTests TokenDeskUITests`。
- 缩进 4 空格，Unix 换行，文件末尾保留一个换行，不使用 Tab 对齐。
- 每行建议不超过 100 字符；URL、生成代码和不可合理拆分的类型签名除外。
- 一个文件以一个主要公开类型为主；小型私有辅助类型可同文件放置。
- 文件名与主要类型一致；扩展按职责命名，如 `UsageBucket+Aggregation.swift`。
- 单文件建议 ≤400 行、函数建议 ≤40 行；超过时按职责拆分，不用空行掩盖复杂度。
- `// MARK: -` 只用于清晰分区；注释解释“为何”，代码表达“做什么”。
- 禁止提交被注释掉的代码、调试打印、真实凭据、真实账户 ID 或未脱敏响应。

## 3. 命名

遵循 Swift API Design Guidelines，并使用领域词汇：

- 类型/协议：`UpperCamelCase`；变量/函数/枚举 case：`lowerCamelCase`。
- 布尔值使用可读谓词：`isEnabled`、`hasCredentials`、`shouldShowHourlyWeather`。
- 协议表达角色：`UsageRepository`、`ProviderConnector`；不统一添加 `Protocol` 后缀。
- 实现表达技术：`GRDBUsageRepository`、`KeychainCredentialStore`。
- DTO 必须带边界：`OpenAIUsageResponseDTO`；领域对象不带厂商前缀。
- 时间区间使用 `DateInterval`；金额使用 `Money`；百分比使用 `UsagePercent`。
- 缩写按单词处理：`providerId`、`apiKey`、`urlRequest`，不用 `providerID`/`APIKey` 混写。
- 禁止 `Manager`、`Helper`、`Utils` 等无职责命名；改为 `SyncCoordinator`、`CostCalculator`。

## 4. 访问控制与 API

- 默认 `internal`；仅跨模块契约声明 `public`，实现细节用 `private`/`fileprivate`。
- `public` API 必须有 `///` 文档，说明单位、线程/actor、错误和隐私约束。
- 优先值类型与不可变 `let`；引用语义必须有明确身份或生命周期理由。
- 构造器注入依赖，不使用可变全局单例；系统对象在 App 组合根创建。
- 禁止 Service Locator。Preview 和测试使用显式 mock/stub。
- 协议保持小而面向调用方；不要建立包含所有 Provider 能力的“万能接口”。
- 枚举 `switch` 在领域层必须穷尽；不使用 `default` 吞掉未来状态。
- 不为一次调用过度抽象；出现第二个真实用例或明确边界时再提取通用层。

## 5. Swift 并发

- 开启 Swift 6 strict concurrency；不得用 `@unchecked Sendable` 静音问题，确需使用必须附 ADR 和并发测试。
- UI Store 与界面状态标记 `@MainActor`。
- 数据库写协调、同步调度和每个有可变状态的 Connector 使用 actor 或不可变值。
- 跨 actor 类型必须 `Sendable`；领域模型优先 `struct: Sendable, Codable, Equatable`。
- 不使用 `Task.detached` 逃逸继承关系；仅在已证明需要独立优先级和生命周期时使用。
- 长任务检查取消；捕获 `CancellationError` 后清理并继续抛出，不转换为普通失败。
- 并行 Provider 使用 `withTaskGroup`；单个子任务错误转换为对应 Provider 结果，不取消整组。
- 禁止在 `@MainActor` 做同步 I/O、JSON 大对象解析、数据库聚合或价格计算。
- 计时使用 `Clock` 注入，测试不依赖真实 `sleep` 和墙上时钟。

## 6. 状态与 SwiftUI

- View 只包含布局、格式化后的展示和意图回调；不访问 URLSession、Keychain 或 GRDB。
- Feature Store 暴露一个不可变/只读 `ViewState`，并提供动词意图：`refresh()`、`selectProvider(_:)`。
- 路由用 `AppRoute`，设置是唯一显式入口；不得在套餐/Token 页添加配置按钮。
- 设计值来自 `TokenDeskDesign`：颜色、字号、间距、边框、Pattern、最小控件尺寸。
- 1280×720 页面不出现滚动条；设置内容需要扩展时只允许设置面板内部滚动。
- 使用 `Text` 的格式化 API；金额、日期、单位不得字符串拼接散落在 View。
- `ForEach` 使用稳定领域 ID，不以数组下标作为身份。
- 高频时钟更新隔离在时钟子树，禁止驱动整个 Dashboard 重算。
- 避免无限动画；遵从 Reduce Motion。同步状态动画不能改变主内容布局。
- 每个交互元素具有 label、键盘焦点和 ≥40×40 的有效命中区域。
- 图表必须同时提供文字摘要，状态不能仅靠颜色表达。

## 7. 领域与数值

- Token 使用 `Int64`；求和使用溢出可控逻辑和边界测试。
- 金额使用 `Decimal` 封装为 `Money`，包含币种；禁止 `Double`、禁止跨币种相加。
- 费用精度在领域层保留，UI 才按币种格式化；禁止过早四舍五入。
- 时间落库为 UTC；分桶由显式 `Calendar` + `TimeZone` 计算，不依赖隐式系统时区。
- 价格规则必须含生效区间；历史费用用当时有效规则，不用最新价重算全部历史。
- 官方费用优先；估算结果必须保留 `isEstimated` 与 `source`。
- 百分比领域允许原始异常值被识别，展示层再夹取；日志记录脱敏诊断，不能静默伪造正常值。
- 账户去重键至少包含 Provider、scope、组织/项目引用；个人套餐与组织 API 用量不合并。

## 8. 网络与 Connector

- 端点集中在各 Connector 的配置中；View、Store 和领域层禁止出现 URL 字符串。
- 仅 HTTPS；自定义 Base URL 由设置页显式确认并校验 scheme/host。
- Request/Response DTO 使用 `Codable`，映射到领域模型后立即离开传输层。
- 解码日期、缺失字段、未知枚举和数值范围必须有 fixture 测试。
- 错误统一映射为：认证、权限、限流、网络、服务端、解码、不支持、取消。
- 只自动重试幂等读取；401/403 与解码错误不重试；429 尊重 `Retry-After`。
- 所有请求有超时和可取消 Task；日志只记 Provider 类型、状态类别、耗时与脱敏 request ID。
- Capability 不支持要明确返回 `.unsupported`；空数据、无权限、尚未同步是不同状态。
- Fixture 必须人工脱敏，替换密钥、邮箱、组织/项目 ID、请求正文。

## 9. 数据库与迁移

- 所有 schema 变更通过顺序编号迁移，如 `v001_initialSchema`，禁止运行时自动推测迁移。
- 迁移只前进且可重复验证；每个迁移测试“空库到最新”和“上一版到最新”。
- 多表写入必须在一个事务；禁止 UI 层拼 SQL。
- 查询方法返回领域对象或 Data record，不把 GRDB Row 暴露到上层。
- 所有外键、唯一键和高频筛选字段需在 migration 中显式定义并测试。
- 数据清理先聚合后删除；清理、导出与同步不可产生重复/缺口。
- 数据库错误不可导致页面清空：保留内存/最近成功 ViewState，并展示可恢复错误。
- 测试使用临时数据库；不依赖开发者真实 Application Support 数据。

## 10. 凭据、隐私与日志

- 密钥仅由 `CredentialStore` 读写 Keychain；调用方按账户 ID 请求，禁止传到 ViewState。
- 密码输入框不回显旧密钥；“已配置”与“替换密钥”是两个状态。
- 使用 `Logger` 隐私标注；账户别名之外的标识默认 `.private`。
- 禁止 `print`、请求/响应 body 日志、Authorization header、URL query 密钥。
- 导出字段使用白名单，永不导出凭据、Prompt、响应正文或完整远端账户标识。
- Crash/诊断附件必须经过相同脱敏规则；MVP 不自动上传日志。
- 测试 secret scanner 覆盖常见 API Key 模式；发现凭据按安全事件处理，不能只删除当前行。

## 11. 错误处理

- 使用有领域语义的错误枚举，底层错误保留为诊断上下文但不直接展示。
- `catch {}` 空捕获、强制 `try!`、生产路径 `fatalError` 均禁止。
- 只在确有不变量且测试覆盖时使用 `precondition`；用户/网络数据永远不能触发崩溃。
- 用户文案回答“发生什么、哪些数据受影响、可采取什么动作”；不展示原始 JSON/SQL/堆栈。
- 页面区分：首次空、同步中、有缓存但过期、部分失败、认证失败、完全离线。
- 恢复成功要清除对应错误状态，但保留诊断事件和告警恢复记录。

## 12. 测试规范

每个任务至少覆盖正常、边界、失败和取消路径：

- Core：价格、分桶、币种、去重、告警冷却，目标行覆盖率 ≥90%。
- Data/Connectors：迁移与映射，目标行覆盖率 ≥80%。
- Features：每个 ViewState 分支和用户意图；不以快照替代业务断言。
- UI：关键主流程，包括四页导航、Provider 切换、日/周/月、设置唯一入口、权限拒绝回退、导出。
- Bug 修复必须先增加失败用例或可复现测试，再提交修复。
- 单元测试不联网、不读真实 Keychain、不依赖当前时间/时区/Locale。
- 测试命名描述行为，例如 `monthlyCost_doesNotCombineDifferentCurrencies()`。

## 13. Git 与评审

- 分支：`feature/TD-123-short-name`、`fix/TD-456-short-name`、`chore/...`。
- Commit 使用 Conventional Commits：`feat(connectors): add OpenAI costs mapping`。
- 每个 PR 聚焦一个可回滚改动；建议净变更 ≤500 行，生成文件与 fixture 单独说明。
- PR 描述必须包含：任务/PRD ID、方案、风险、测试证据、UI 截图（如有）、隐私/迁移影响。
- 至少一名 reviewer；数据库迁移、Keychain、权限、价格规则与 App Store entitlement 需模块 owner 复核。
- 未通过格式、构建、单测、UI smoke、secret scan 的 PR 不得合并。
- 禁止直接提交主分支；紧急修复也必须留任务、测试与复盘记录。

## 14. Definition of Done

一个开发任务只有同时满足以下条件才可完成：

- 对应 PRD/任务验收条件全部满足，没有以 Mock 冒充真实能力。
- 代码已格式化、无编译警告、Swift 6 并发检查通过。
- 自动化测试覆盖正常/失败/边界；必要的 1280×720 截图已更新并评审。
- 日志、数据库、导出和 fixture 不含敏感信息。
- 权限拒绝、离线、过期缓存与单 Provider 失败可恢复。
- 文档、迁移说明和 App Store/隐私影响同步更新。
- Reviewer 已批准，CI 全绿，变更可回滚或有明确迁移恢复方案。

