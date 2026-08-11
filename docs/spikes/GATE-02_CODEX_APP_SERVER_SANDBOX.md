# GATE-02：Codex App Server + App Sandbox

- 结论日期：2026-08-11
- 结论：**未通过（P0 NO-GO）**
- 影响：`TD-048` 不得在 P0 交付真实 Codex 套餐 Connector；保留 capability 和明确的“不支持”状态，可使用脱敏 Fixture 演示 UI，但不得标记为官方实时数据或用本地估算冒充额度。

## 结论摘要

OpenAI 已正式文档化 Codex App Server 协议，并提供满足 Token Desk 套餐卡片字段的只读方法。`account/rateLimits/read` 可返回额度百分比、窗口长度、重置时间、多额度桶和可选套餐类型；`account/usage/read` 可返回账户 Token 活动摘要及可选日桶。该路径不需要网页抓取、浏览器 Cookie、读取 Codex/ChatGPT 私有容器或调用非公开接口。

但是，OpenAI 同一份官方文档明确说明 app-server 命令和 WebSocket transport 仍属实验性且不支持生产工作负载。当前仓库也没有可供签名、Release App Sandbox 和 Mac App Store 审核验证的内嵌 helper，执行环境中没有 `codex` 可执行文件，因而没有完成真实账户、凭据落盘方式、沙箱继承或审核包验证。实验性宿主不能满足 P0 生产发布的可支持性要求，故 GATE-02 整体未通过。

## 官方能力映射

| Token Desk 需求 | App Server 能力 | 结论 |
|---|---|---|
| 套餐类型 | `account/read.account.planType` 或额度桶中的 `planType`（服务返回时） | 可选；缺失时不得猜测 |
| 已用百分比 | `account/rateLimits/read` → `primary/secondary.usedPercent` | 可用 |
| 窗口长度 | `windowDurationMins` | 可用 |
| 准确重置时间 | `resetsAt`，Unix 秒 | 可用；入库前转换 UTC |
| 多额度窗口 | `rateLimitsByLimitId`，以及每桶的 `primary` / `secondary` | 可用；旧 `rateLimits` 仅作兼容视图 |
| 套餐 Token 摘要 | `account/usage/read.summary`、`dailyUsageBuckets` | 部分可用 |
| 输入/输出/缓存 Token | 无对应账户聚合字段 | 不支持；不得从总 Token 拆分 |
| 费用/余额 | 无对应账户费用接口；额度响应可能包含 workspace credits | 不得混入 metered cost 或现金余额 |
| 实时更新 | `account/rateLimits/updated` notification | 可用，但定时 read 仍需处理休眠恢复和断线 |

`account/usage/read` 的汇总值和日桶都可能为 `null`，且只支持由 Codex 服务支持的认证；API key-only 与 Bedrock 认证不支持该方法。因此 Connector 必须逐项声明 capability，不能用空数组或零值表示成功。

## 只读边界

若以后重新启用，P0 读取路径仅允许：

1. 完成 `initialize` / `initialized` 握手。
2. 使用官方 ChatGPT managed browser flow 或 device-code flow登录独立的 Token Desk 集成。
3. 调用 `account/read`（仅认证状态）、`account/rateLimits/read` 和 `account/usage/read`。
4. 订阅 `account/updated` 与 `account/rateLimits/updated`，不启动 thread/turn，也不采集 Prompt、响应或会话历史。
5. 明确禁用 `account/rateLimitResetCredit/consume`、`account/sendAddCreditsNudgeEmail`、配置写入、logout 之外的账户变更及所有 agent 执行能力。

Token Desk 不得连接用户已安装的 Codex 进程、读取 `~/.codex`、复制现有登录态、访问其他 App 容器，或要求用户选择外部 `codex` 可执行文件来绕过沙箱。外部托管 token 模式本身也被官方标为实验性，不作为 Keychain 绕行方案。

## App Sandbox 与审核路径

未来候选实现必须是自包含方案：将固定版本的 app-server 作为 app bundle 内签名的 command-line helper，通过 `stdio` JSONL 通信；不得下载可执行代码，不得依赖用户另外安装 CLI，不得使用实验性 WebSocket listener。

Apple 要求内嵌 command-line tool 继承宿主 App Sandbox；helper 需以 `com.apple.security.app-sandbox` 和 `com.apple.security.inherit` 签名。主 App 仅授予必要的 outbound network 权限。凭据仍必须满足本项目“只存 Keychain”的政策；若 app-server managed login 的实际版本不能证明这一点，则继续阻断真实 Connector。

Mac App Store 审核提交应提供：

- 内置脱敏演示账户/Fixture，不要求审核员提供真实 ChatGPT 凭据。
- Review Notes 说明内嵌 helper、只读方法白名单、无外部代码下载、无网页抓取/Cookie/其他容器访问。
- 主 App 与 helper 的 `codesign` entitlement 输出、Activity Monitor Sandbox 状态、干净 macOS 14+ 账户的登录/登出证据。
- helper 随 App 退出终止、离线/401/429/空字段/多额度桶/睡眠恢复测试。
- SQLite、日志、崩溃报告和导出中无 email、access/refresh token、授权 URL query、Prompt 或响应内容的检查结果。

## 重新开启 GATE-02 的通过条件

以下条件必须全部满足后，才能将真实 Codex Connector 重新纳入发布范围：

1. OpenAI 将所采用的 app-server 命令和 transport 标为可用于生产，或提供等价的稳定公开 API/SDK。
2. 固定并审查可再分发版本、许可证、SBOM、签名和 universal binary 构建；整个 app bundle 自包含。
3. 确认 managed ChatGPT 登录的持久化凭据只进入 Keychain，或由产品与安全评审显式批准并更新项目政策。
4. 在 Mac App Store Release 配置中完成 helper sandbox inheritance、outbound network、生命周期和无 sandbox violation 验证。
5. 使用开发/测试账户验证 `account/rateLimits/read` 与 `account/usage/read` 的真实响应；Fixture 只能做契约回归，不能充当真实能力证据。
6. 审核模式和 Review Notes 经签名包复核，无需真实高权限凭据即可验证产品行为。

## 当前范围建议

- P0：Codex capability 返回 `.unsupported`，UI 显示“官方生产接口暂不可用”；允许 Fixture-only demo，并永久标识为演示数据。
- P0：OpenAI API 的 Organization Usage / Costs API 继续作为独立的 `metered_token` Connector，不与 ChatGPT/Codex 套餐额度混用。
- P1/后续：满足上述重开条件后，另建小型 spike 验证 pinned helper、managed login、Keychain 和 Release 沙箱，再恢复 `TD-048`。
- 禁止：网页抓取、Cookie、读取私有容器、调用用户现有 Codex CLI、将账户总 Token 拆成输入/输出/缓存、把额度百分比换算为 Token。

## 证据与未验证项

官方资料：

- [OpenAI Codex App Server](https://developers.openai.com/codex/app-server/)：协议定位、transport、初始化、认证、额度和 Token 活动字段，以及实验性/生产支持状态。
- [Apple：Protecting user data with App Sandbox](https://developer.apple.com/documentation/security/protecting-user-data-with-app-sandbox)：App Sandbox 和内嵌 command-line tool 要求。
- [Apple：Embedding a command-line tool in a sandboxed app](https://developer.apple.com/documentation/xcode/embedding-a-helper-tool-in-a-sandboxed-app)：helper 的嵌入、签名及 sandbox inheritance 路径。
- [Apple App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)：Mac App Store 自包含、沙箱和禁止下载/安装额外代码的要求。

本次已验证：官方字段与只读调用边界、官方实验性声明、Apple 公开的 helper 沙箱与审核要求。

本次未验证：真实 ChatGPT 账户响应、真实限流/错误行为、managed login 的 Keychain 落盘、Codex helper 的可再分发构建与许可证清单、universal binary、签名/公证、Release App Sandbox、Mac App Store 审核。当前执行环境没有 `codex` 命令，仓库的应用基线也尚未包含 app-server helper 或 Connector；这些缺口是 NO-GO 结论的一部分，不能用 Mock 代替。
