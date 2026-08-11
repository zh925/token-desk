# Token Desk 产品需求文档（PRD）

## 1. 文档信息

| 项目 | 内容 |
|---|---|
| 产品名称 | Token Desk |
| 产品形态 | 面向 Wokyis M5 的 macOS 5 寸副屏常驻看板 |
| PRD 版本 | 1.1 |
| 产品版本 | MVP / 0.1.0 |
| 文档日期 | 2026-08-11 |
| 目标分辨率 | 1280×720，横屏 |
| 目标设备 | Wokyis M5，5 英寸，非触控 |
| 目标平台 | macOS |
| 分发方式 | Mac App Store |
| 账户范围 | 个人账户与组织/团队账户 |
| 当前状态 | 需求确认完成，进入技术验证阶段 |

### 1.1 修订记录

| 版本 | 日期 | 说明 |
|---|---|---|
| 1.0 | 2026-08-11 | 建立完整 PRD；移除 Agent 状态；统一为单一设置入口；固定适配 1280×720 |
| 1.1 | 2026-08-11 | 明确 Wokyis M5、非触控、国产 Provider、个人/组织账户、Mac App Store、定位、导出和告警需求 |

## 2. 产品概述

Token Desk 是一款运行在 macOS 上、专门面向 5 寸副屏的常驻信息看板。它将高频但分散的信息集中在一个始终可见的 1280×720 界面中，核心展示：

1. 当前时间、日期与天气。
2. AI 订阅套餐的额度使用情况及重置时间。
3. 按 Token 计费的输入、输出、缓存、费用和余额数据。
4. 多家 AI Provider 的连接、聚合和切换。

产品采用老款 Macintosh 的黑白、高对比度、像素化视觉风格，但不复刻 macOS 系统桌面、系统菜单或窗口管理。界面本质上是一个完整软件页面，所有数据卡片位置固定。

### 2.1 目标硬件

- 目标设备：Wokyis M5 Retro Dock。
- 显示区域：5 英寸、1280×720、横屏。
- 输入方式：设备本身不支持触摸；产品以环境式查看为主，交互通过 Mac 的鼠标、触控板或键盘完成。
- 接入假设：将 M5 作为 macOS 标准外接显示器处理，通过 `NSScreen`/Core Graphics 识别、定位和恢复窗口。
- 设备识别：优先保存显示器的稳定标识；若系统未暴露稳定标识，则使用分辨率、显示器名称及用户选择组合匹配。
- 兼容策略：不同 M5 接口版本不改变应用数据层；硬件验证阶段分别验证直连、扩展坞路径及睡眠重连。

## 3. 背景与问题

AI 重度用户通常同时使用多种消费方式：

- ChatGPT/Codex、Claude 等订阅套餐，按照动态额度窗口限制使用。
- OpenAI API、Anthropic API、Gemini、DeepSeek 等按 Token 或调用项目计费。
- OpenRouter 等预充值 Credits 模式。
- 部分 Provider 只在每次请求中返回 Token 数，没有可查询的历史用量接口。

这些数据分散在不同控制台，展示口径也不一致。用户需要频繁切换网页才能回答以下问题：

- 当前套餐用了多少，什么时候重置？
- 今天和本月花了多少钱？
- 哪家 Provider 消耗最多？
- 当前余额是否足够？
- 是否即将超过自己设定的月度预算？

Token Desk 利用用户已有的副屏，把这些信息转化为无需主动打开的环境式状态展示。

## 4. 产品目标

### 4.1 核心目标

- 用户在 3 秒内读懂当前时间、天气和主要 AI 用量状态。
- 同时支持套餐额度与按 Token 计费，但保持两种数据口径清晰分离。
- 支持多个 Provider，通过统一配置方式接入。
- 首批支持 OpenAI、Anthropic、Google、DeepSeek、智谱 GLM、Kimi、MiniMax 等国内外 Provider。
- 同时支持个人账户和组织/团队账户的用量聚合。
- 在 1280×720 的 5 寸屏上保持足够大的字号和高可读性。
- 在副屏断开、休眠、网络异常或 Provider 不可用时稳定恢复。
- 凭据和历史数据默认仅保存在用户本机。
- 支持历史用量导出和可配置的本地告警通知。
- 满足 Mac App Store 的 App Sandbox、隐私披露和用户授权要求。

### 4.2 成功指标

MVP 发布后建议跟踪以下指标：

| 指标 | 目标 |
|---|---|
| 冷启动到可见首屏 | ≤ 2 秒，不含首次授权 |
| 常驻内存 | 原生实现目标 ≤ 150 MB |
| 空闲 CPU 占用 | 平均 ≤ 2% |
| 副屏重连恢复时间 | ≤ 5 秒 |
| 数据同步成功率 | 支持的官方接口 ≥ 98% |
| 用户识别核心信息的时间 | 可用性测试中 ≤ 3 秒 |
| 本地崩溃率 | 每 100 小时运行 < 1 次 |

## 5. 非目标

以下内容不属于当前版本范围：

- Agent 当前状态、任务进度、工具调用或审批状态。
- 对 AI Agent 发出指令或批准高风险操作。
- 模拟 Macintosh 桌面、系统菜单或可拖拽窗口。
- 多窗口管理、自由布局或小组件编辑器。
- 隐私模式或对费用数字进行临时遮挡。
- Provider 网页抓取、浏览器 Cookie 读取或非公开接口逆向。
- 将套餐百分比强行换算成“剩余 Token”。
- 团队级账单审批和企业财务结算；组织账户只做只读用量聚合与展示。
- iOS、Windows 和 Android 客户端。

## 6. 目标用户

### 6.1 核心用户

- 同时使用多个 AI Provider 的开发者、研究人员和内容创作者。
- 使用 Codex、ChatGPT、Claude 等订阅套餐的高频用户。
- 希望控制 API 成本、余额和预算的个人开发者、团队负责人及组织管理员。
- 已拥有 Wokyis M5 的 macOS 用户。

### 6.2 用户特征

- 每天长时间使用 Mac。
- 对 Token、API Key、模型和订阅额度有基本认知。
- 希望减少网页控制台切换。
- 关注成本异常、限额和重置时间。

## 7. 核心用户场景

### 场景 A：全天环境式查看

用户开始工作后，Token Desk 随系统启动并自动出现在副屏。用户无需交互即可看到时间、天气、Codex 套餐使用比例、OpenAI 本月费用和 DeepSeek 余额。

### 场景 B：确认套餐重置时间

用户发现 Codex 额度接近上限，切换到“套餐”页面，查看主额度窗口和周额度的使用比例、窗口长度及准确重置时间。

### 场景 C：分析 Token 成本

用户切换到“Token”页面，选择 OpenAI、DeepSeek、OpenRouter 或 Gemini，比较今日、本周、本月的输入 Token、输出 Token、费用、缓存命中率和预算使用情况。

### 场景 D：配置 Provider

用户点击界面右上角唯一的“设置”按钮，添加或编辑 Provider、API Key、计费形式和月度预算。完成后返回总览。

### 场景 E：副屏重连

Mac 从睡眠中恢复或副屏重新插入后，应用重新识别目标屏幕、恢复页面并同步最新数据，不需要用户重新配置。

### 场景 F：国产 Provider 聚合

用户同时配置智谱 GLM、Kimi、MiniMax、DeepSeek 等国产 Provider。Token Desk 在统一页面中展示各平台可获得的套餐、Token、余额或本地估算数据，并明确标注数据来源。

### 场景 G：组织账户查看

团队负责人添加组织级凭据，选择组织、项目或工作空间，查看组织总费用及各项目用量；个人账号数据与组织数据保持独立，不重复汇总。

### 场景 H：导出历史与接收告警

用户将指定时间范围的用量导出为 CSV 或 JSON。当套餐接近上限、余额不足、费用超过预算或数据长时间同步失败时，系统按照用户配置发送 macOS 本地通知。

## 8. 产品范围与优先级

### 8.1 MVP / P0

- 固定适配 1280×720 横屏。
- 自动识别并选择 Wokyis M5 副屏。
- 非触控交互；支持鼠标、触控板和键盘。
- 时间、日期、时区展示。
- 当前天气、体感温度、降雨概率、湿度和未来小时天气。
- 使用 Core Location 获取当前位置；拒绝授权时允许手工选择城市。
- 套餐额度：名称、已用百分比、窗口长度、重置时间、数据来源。
- Token 计费：输入、输出、缓存、费用、余额和预算。
- OpenAI API Connector。
- Codex 套餐明确降级状态；P0 不接入真实额度，Fixture 仅用于演示且永久标识为演示数据。
- Anthropic API 组织 Connector。
- DeepSeek Connector。
- OpenRouter Connector。
- Gemini 本地聚合 Connector。
- 智谱 GLM Connector。
- Kimi/Moonshot Connector。
- MiniMax Connector，兼容 Token Plan 与按量付费。
- 支持个人账户和组织/团队账户配置。
- 总览、套餐、Token、设置四个页面状态。
- 顶部唯一设置入口。
- macOS Keychain 凭据存储。
- 本地历史数据与缓存。
- CSV 与 JSON 历史用量导出。
- 套餐、预算、余额和同步失败告警。
- 网络和认证错误状态。
- 登录启动与副屏重连。
- App Sandbox、隐私政策、App Privacy 信息与 Mac App Store 发布材料。

### 8.2 P1

- Codex 套餐 Connector（仅在 GATE-02 重开条件全部通过后恢复）。
- Claude 个人套餐本地估算。
- 自定义 OpenAI-compatible Provider。
- 通义千问/阿里云百炼 Connector。
- 豆包/火山方舟 Connector。
- 百川等其他国产 Provider Connector。
- 成本异常检测和自适应预警。
- WeatherKit 数据源。
- 夜间亮度、像素漂移和防烧屏策略。
- Provider 排序与总览卡片显隐。
- 每日、每周、每月历史趋势。

### 8.3 P2

- 价格规则远程更新。
- 多币种与汇率换算。
- 多项目、API Key 和模型维度筛选。
- 自定义主题与高对比度主题。
- 多台副屏配置。

## 9. 信息架构

```text
Token Desk
├── 总览
│   ├── 时间与日期
│   ├── 天气
│   ├── 主套餐额度
│   └── 主要 Provider 摘要
├── 套餐
│   ├── 主额度窗口
│   ├── 次级/周额度窗口
│   ├── 本地估算套餐
│   └── 数据口径说明
├── Token
│   ├── Provider 列表
│   ├── 时间范围
│   ├── Token 与费用指标
│   ├── 趋势图表
│   └── 模型、缓存、预算摘要
└── 设置（唯一入口）
    ├── Providers
    ├── 时间与天气
    └── 显示
```

## 10. 全局界面与导航需求

### 10.1 应用头部

| 编号 | 需求 |
|---|---|
| NAV-001 | 左侧显示产品标识和 Token Desk 名称。 |
| NAV-002 | 中部提供“总览”“套餐”“Token”三个一级导航按钮。 |
| NAV-003 | 当前页面按钮以黑底白字表示。 |
| NAV-004 | 右侧展示 Provider 同步状态和最后更新时间。 |
| NAV-005 | 提供“同步”按钮，手动刷新全部 Provider。 |
| NAV-006 | 整个产品只能有一个进入设置页的显式入口，位于右上角。 |
| NAV-007 | 套餐页和 Token 页不得额外提供配置、添加或跳转设置按钮。 |

### 10.2 页面行为

- 所有页面在同一 1280×720 画布中切换，不打开新窗口。
- 数据面板位置固定，不允许拖拽、关闭、缩放或自由排列。
- 页面切换应在 100 毫秒内完成，不使用影响阅读的过场动画。
- 弹窗仅用于设置中的 Provider 编辑、确认或错误提示。
- 键盘 `1`、`2`、`3` 可分别切换总览、套餐、Token；设置只通过顶部设置按钮进入。

## 11. 功能需求

### 11.1 时间与日期

| 编号 | 优先级 | 需求 |
|---|---|---|
| TIME-001 | P0 | 显示 24 小时制时、分、秒。 |
| TIME-002 | P0 | 显示年、月、日、星期。 |
| TIME-003 | P0 | 默认读取 macOS 当前时区。 |
| TIME-004 | P0 | 用户可在设置中覆盖时区。 |
| TIME-005 | P0 | 每秒更新显示，不触发整页重绘。 |
| TIME-006 | P1 | 系统时区变化后自动更新。 |

### 11.2 天气

| 编号 | 优先级 | 需求 |
|---|---|---|
| WEA-001 | P0 | 显示城市、当前温度和天气状况。 |
| WEA-002 | P0 | 显示体感温度、降雨概率和湿度。 |
| WEA-003 | P0 | 显示至少未来 4 个小时的天气和温度。 |
| WEA-004 | P0 | 默认每 15 分钟同步一次。 |
| WEA-005 | P0 | 首选 Open-Meteo；用户可在设置中更换数据源。 |
| WEA-006 | P0 | 获取失败时保留最近一次成功数据，并显示数据更新时间。 |
| WEA-007 | P1 | 支持 WeatherKit，并满足归属标识要求。 |
| WEA-008 | P0 | 使用 Core Location 请求“使用 App 期间”定位权限，并通过定位获得天气坐标。 |
| WEA-009 | P0 | 用户拒绝定位、定位不可用或希望覆盖位置时，允许手工输入城市。 |
| WEA-010 | P0 | 定位数据只用于天气查询；不建立位置历史，不用于分析或广告。 |

### 11.3 套餐额度

套餐型数据表示某一时间窗口内的使用比例，不能与按 Token 计费直接混合。

| 编号 | 优先级 | 需求 |
|---|---|---|
| PLAN-001 | P0 | 显示套餐名称、套餐类型和 Provider。 |
| PLAN-002 | P0 | 显示当前已使用百分比。 |
| PLAN-003 | P0 | 显示额度窗口长度和准确重置时间。 |
| PLAN-004 | P0 | 支持同一 Provider 的多个额度窗口。 |
| PLAN-005 | P0 | 标识数据来源为“官方数据”或“本地估算”。 |
| PLAN-006 | P0 | 本地估算必须显示置信度，不得伪装成官方数据。 |
| PLAN-007 | P0 | 总览只显示用户选定的主套餐。 |
| PLAN-008 | P0 | 套餐页面不得提供设置入口。 |
| PLAN-009 | P0 | 额度达到用户配置的阈值时产生本地提醒；默认阈值为 80%、95%、100%。 |
| PLAN-010 | P1 | 支持 Provider 返回多种限额桶时分别展示。 |

### 11.4 Token 计费与费用

| 编号 | 优先级 | 需求 |
|---|---|---|
| TOK-001 | P0 | 支持输入 Token 和输出 Token 分开统计。 |
| TOK-002 | P0 | 支持缓存读取、缓存写入及缓存命中率。 |
| TOK-003 | P0 | 在 Provider 支持时优先显示官方 Costs 数据。 |
| TOK-004 | P0 | 无 Costs API 时，按版本化价格规则进行本地估算。 |
| TOK-005 | P0 | 支持今日、本周、本月三个时间范围。 |
| TOK-006 | P0 | 显示最常用模型、费用、预算占比及余额。 |
| TOK-007 | P0 | 显示按时间分桶的输入/输出趋势图。 |
| TOK-008 | P0 | Token 页面不得提供添加或配置 Provider 的入口。 |
| TOK-009 | P0 | 官方费用和本地估算费用必须具有不同来源标记。 |
| TOK-010 | P1 | 支持图像、音频、Web Search、工具调用等非 Token 费用项目。 |
| TOK-011 | P1 | 支持按模型、项目和 API Key 聚合。 |
| TOK-012 | P0 | 支持用户自定义月度预算及预警阈值。 |

### 11.5 Provider 切换

| 编号 | 优先级 | 需求 |
|---|---|---|
| PRO-001 | P0 | Token 页面左侧显示已启用的 Provider。 |
| PRO-002 | P0 | 点击 Provider 后更新右侧所有指标和趋势图。 |
| PRO-003 | P0 | 当前 Provider 使用反色高亮。 |
| PRO-004 | P0 | 列表只承担查看和切换功能，不出现添加 Provider 按钮。 |
| PRO-005 | P0 | Provider 断开时展示离线标记，但保留历史数据。 |

### 11.6 设置

设置页是所有配置行为的唯一入口。

#### Provider 设置

- 添加、编辑、启用和停用 Provider。
- 为每个 Provider 选择账户范围：个人或组织/团队。
- 组织账户支持配置组织 ID、项目/工作空间 ID 及只读管理凭据；个人和组织数据分开聚合。
- 选择计费形式：套餐窗口、按 Token 计费、余额/Credits、本地估算。
- 输入 API Key、Admin Key 或管理密钥。
- 配置月度预算、币种和数据刷新周期。
- 执行连接测试并显示明确结果。
- 删除 Provider 前二次确认；删除凭据但允许用户选择是否保留历史数据。

#### 时间与天气设置

- 城市或坐标。
- 定位授权状态、申请授权和“使用当前位置”按钮。
- 时区。
- 天气数据源。
- 刷新间隔。
- 是否展示逐小时天气。

#### 显示设置

- 目标屏幕选择。
- 逻辑分辨率固定为 1280×720。
- 副屏连接后自动打开。
- 登录后自动启动。
- 夜间亮度。
- 像素风格开关。
- 防烧屏像素漂移。

#### 通知设置

- 通知总开关；只有用户主动启用时才请求系统通知权限。
- 套餐额度阈值，默认 80%、95%、100%。
- 月度预算阈值，默认 80%、95%、100%。
- 余额下限，支持按 Provider 和币种设置。
- 连续同步失败阈值，默认 30 分钟。
- 通知静默时间段、重复提醒冷却时间和测试通知。

#### 数据与导出设置

- 显示本地数据库占用空间及各粒度历史数据保留周期。
- 保留策略固定采用：分钟 7 天、小时 90 天、日数据默认 2 年。
- 支持按时间范围、账户、Provider、项目和数据粒度导出。
- 支持 CSV 与 JSON 两种格式；CSV 使用 UTF-8 BOM，保证中文表头可在常见表格软件中打开。
- 通过系统保存面板选择导出位置；应用不默认获得用户文件系统的广泛访问权限。
- 支持清除某个 Provider 历史或全部历史，执行前二次确认。

### 11.7 个人与组织账户

| 编号 | 优先级 | 需求 |
|---|---|---|
| ACC-001 | P0 | 同一 Provider 可添加多个账户配置。 |
| ACC-002 | P0 | 账户范围支持 `personal` 与 `organization`。 |
| ACC-003 | P0 | 组织账户可包含组织、项目、工作空间等层级。 |
| ACC-004 | P0 | 总览可选择合并展示或按账户查看，默认不跨币种直接相加。 |
| ACC-005 | P0 | 账户显示名由用户设置；默认不在日志中记录邮箱或完整组织标识。 |
| ACC-006 | P0 | 个人套餐与组织 API 用量不得重复计算。 |

### 11.8 历史导出

| 编号 | 优先级 | 需求 |
|---|---|---|
| EXP-001 | P0 | 支持 CSV 和 JSON 导出。 |
| EXP-002 | P0 | 支持指定开始与结束日期。 |
| EXP-003 | P0 | 支持选择 Provider、账户、项目和数据类型。 |
| EXP-004 | P0 | 导出字段包含时间、Provider、账户别名、模型、输入/输出/缓存 Token、费用、币种、数据来源及是否估算。 |
| EXP-005 | P0 | 导出文件不得包含 API Key、Prompt、响应正文或完整账户凭据。 |
| EXP-006 | P0 | Mac App Store 沙箱环境下通过 `NSSavePanel` 获取用户选定文件的写权限。 |
| EXP-007 | P1 | 支持按月自动导出到用户授权并持久化书签的目录。 |

### 11.9 告警通知

| 编号 | 优先级 | 需求 |
|---|---|---|
| ALT-001 | P0 | 使用 macOS UserNotifications 发送本地通知。 |
| ALT-002 | P0 | 用户首次开启告警时才请求通知授权。 |
| ALT-003 | P0 | 支持套餐额度、预算、余额和同步失败四类告警。 |
| ALT-004 | P0 | 阈值可按 Provider/账户配置。 |
| ALT-005 | P0 | 相同告警在冷却时间内只发送一次，状态恢复后才允许再次触发。 |
| ALT-006 | P0 | 点击通知打开 Token Desk 并定位到相关 Provider。 |
| ALT-007 | P0 | 通知正文不包含 API Key、完整组织标识或其他敏感凭据。 |
| ALT-008 | P1 | 支持每日用量摘要通知。 |

## 12. Provider 数据类型与适配策略

### 12.1 统一计费类型

```text
quota_window    套餐额度窗口
metered_token   按 Token 计费
credit_balance  预付费余额或 Credits
local_estimate  本地采集和估算
```

一个 Provider 可以同时支持多个类型。例如 DeepSeek 可以同时提供余额与单次请求 Token；Codex 可以提供套餐窗口与账户 Token 活动摘要。

### 12.2 MVP Provider 矩阵

| Provider | 账户范围 | 数据类型 | 推荐数据源 | MVP 展示 |
|---|---|---|---|---|
| Codex / ChatGPT | 个人 + 组织 | quota_window | Codex App Server（GATE-02 重开后） | P0 显示明确不支持状态；Fixture 仅演示，不作为真实数据 |
| OpenAI API | 个人 + 组织 | metered_token | Organization Usage / Costs API；单次响应 usage | 输入、输出、缓存、项目费用 |
| Anthropic API | 组织 | metered_token | Usage & Cost Admin API | 组织 Token、工作空间和费用 |
| DeepSeek | 个人 + 组织 | credit_balance + metered_token | Balance API + 单次响应 usage | 余额、Token、本地聚合费用 |
| 智谱 GLM | 个人 + 组织 | quota_window + metered_token + local_estimate | 标准 API 响应 usage；Coding Plan/控制台能力可用时接入 | GLM Token、模型费用、余额或套餐窗口 |
| Kimi / Moonshot | 个人 + 组织 | credit_balance + metered_token | Balance API + 响应 usage + Token 估算接口 | 可用余额、Token、本地历史和费用估算 |
| MiniMax | 个人 + 组织 | quota_window + credit_balance + metered_token | Token Plan 能力 + 响应 usage；官方账户能力可用时接入 | Token Plan、按量 Token、余额/资源包 |
| OpenRouter | 个人 + 组织 | credit_balance | Credits API | 总充值、总消耗、可用 Credits |
| Gemini | 个人 + 组织 | local_estimate | 响应 usage metadata | Token 本地聚合和费用估算 |

国产 Provider 的 P1 扩展清单包括通义千问/阿里云百炼、豆包/火山方舟、百川等。Connector 架构不得依赖英文厂商字段或固定美元币种，应原生支持人民币、资源包、Token Plan 和 OpenAI-compatible 接口。

### 12.3 Connector 接口

每个 Connector 至少实现以下接口：

```text
identify()                返回 Provider 与能力信息
validateCredentials()     检查凭据是否有效
fetchAccounts()           获取或校验个人、组织、项目/工作空间范围
fetchPlan()               获取套餐及额度窗口
fetchBalance()            获取余额或 Credits
fetchUsage(start, end)    获取 Token 与费用聚合
fetchHealth()             获取认证、连接和限流状态
```

可选能力：

```text
subscribeUsage()          订阅实时用量事件
fetchModels()             获取模型列表
fetchProjects()           获取项目列表
```

### 12.4 统一数据对象

```json
{
  "providerId": "openai-primary",
  "providerType": "openai",
  "accountScope": "organization",
  "accountId": "local-account-alias-id",
  "organizationId": "org-reference",
  "projectId": "project-reference",
  "source": "official_cost_api",
  "period": {
    "start": "2026-08-01T00:00:00+08:00",
    "end": "2026-09-01T00:00:00+08:00"
  },
  "usage": {
    "inputTokens": 8240000,
    "outputTokens": 1820000,
    "cachedInputTokens": 5170000
  },
  "cost": {
    "value": 28.46,
    "currency": "USD",
    "estimated": false
  },
  "updatedAt": "2026-08-11T09:40:00+08:00"
}
```

### 12.5 套餐窗口对象

```json
{
  "providerId": "codex-primary",
  "planName": "Codex Pro",
  "limitId": "codex",
  "usedPercent": 42,
  "windowDurationMinutes": 300,
  "resetsAt": "2026-08-11T12:59:00+08:00",
  "source": "official",
  "confidence": null
}
```

## 13. 价格规则

本地费用估算不得在代码中只保存一个不可追踪的固定价格。价格规则至少包含：

```yaml
provider: example
model_match: example-*
currency: USD
region: global
effective_from: 2026-01-01
effective_to: null
pricing:
  input_per_million: 0
  output_per_million: 0
  cache_read_per_million: 0
  cache_write_per_million: 0
```

规则要求：

- 支持生效日期和历史版本。
- 支持模型通配和精确匹配。
- 支持输入、输出、缓存读取和缓存写入不同价格。
- Provider 官方返回费用时，以官方费用为准。
- 所有估算费用在 UI 中显示“估算”标签。
- 价格规则更新失败时继续使用最近有效版本。

## 14. 刷新与缓存策略

| 数据 | 默认刷新方式 | 默认频率 |
|---|---|---|
| 时间 | 本地时钟 | 每秒 |
| 天气 | 定时拉取 | 15 分钟 |
| 套餐窗口 | 定时拉取 + 可用时事件更新 | 60 秒 |
| Token Usage | 定时拉取或本地事件聚合 | 60 秒 |
| 费用/Costs | 定时拉取 | 5 分钟 |
| 余额/Credits | 定时拉取 | 5 分钟 |
| 连接健康状态 | 定时检查 | 5 分钟或失败后退避 |

缓存要求：

- 首屏优先读取本地缓存，随后异步刷新。
- 每条数据包含 `updatedAt`、`source` 和 `stale` 状态。
- 官方接口连续失败时采用指数退避，最长不超过 30 分钟。
- 数据过期后不清空卡片，而是显示“数据已过期”和最后成功时间。
- 不应因单个 Provider 失败阻塞其他数据或整个页面。

## 15. 错误、空状态与边界状态

### 15.1 Provider 状态

- 已连接：数据正常，显示实心状态点。
- 同步中：状态点闪烁，保留旧数据。
- 凭据失效：显示“需要重新认证”，只在设置中提供处理入口。
- 限流：显示预计恢复时间。
- 接口不可用：显示最近数据和最后更新时间。
- 未配置：该 Provider 不应出现在 Token 页面列表或总览中。

### 15.2 数据状态

- `0` 是有效值，不能当作空数据。
- 未知余额显示 `—`，不能显示 `0`。
- 无费用接口时显示估算值及来源。
- 套餐没有固定 Token 上限时只显示百分比和窗口。
- 跨月、跨时区和夏令时变化不得造成重复或丢失分桶。

### 15.3 屏幕状态

- 目标副屏不存在：应用保留在菜单栏或主屏设置窗口中，不强行全屏覆盖主屏。
- 副屏接入：5 秒内创建或移动展示窗口。
- 分辨率不是 1280×720：优先等比缩放并居中，不拉伸。
- 睡眠恢复：恢复画面后触发一次增量同步。

## 16. 视觉与交互规范

### 16.1 视觉方向

- 老款 Macintosh 黑白、高对比度视觉语言。
- 使用像素化线条、1-bit 网点和斜线填充。
- 不复刻系统菜单、桌面图标或 Finder。
- 使用应用顶部导航和固定数据卡片。
- 视觉装饰不能降低关键数字可读性。

### 16.2 字体层级

针对 5 寸屏的建议字号：

| 层级 | 建议字号 |
|---|---|
| 主时钟 | 64–76 px |
| 核心百分比/金额 | 40–52 px |
| 页面标题 | 24–28 px |
| 卡片标题 | 18–24 px |
| 正文 | 14–17 px |
| 辅助信息 | 不低于 11 px |

### 16.3 颜色与对比度

- 主文字：接近纯黑。
- 背景：白色或浅灰。
- 当前选中项：黑底白字。
- 避免只依赖颜色表达状态，应同时使用文字、图形或填充纹理。
- 正文对比度目标不低于 WCAG AA。

### 16.4 交互目标

- Wokyis M5 不支持触摸；所有功能必须支持鼠标、触控板和键盘操作。
- 鼠标点击目标建议不小于 40×40 px，便于在高像素密度小屏上操作。
- 所有按钮具有悬停、按下和键盘焦点状态。
- 高频展示不需要持续动画。
- 同步动画仅影响状态点，不让主内容跳动。

## 17. 安全与隐私

### 17.1 凭据安全

- API Key、Admin Key、管理密钥只存入 macOS Keychain。
- SQLite、日志、配置文件和崩溃报告不得包含明文密钥。
- UI 只显示凭据是否存在，不回显完整内容。
- 使用最小权限凭据；需要高权限 Admin Key 时明确说明原因。
- 复制、导出和日志功能默认排除凭据。

### 17.2 本地数据

- 历史用量默认仅保存在本机。
- 不采集用户的 Prompt、响应内容或请求正文。
- 本地聚合只记录 Provider、模型、Token、费用、时间和可选项目 ID。
- 用户删除 Provider 时可选择一并删除历史数据。
- 定位数据只用于请求当前地点天气，应用不保存位置轨迹；缓存最多保留当前粗略坐标和城市名称。
- 导出由用户主动发起，导出文件离开应用容器后的安全由用户负责；应用内应对此给出说明。

### 17.3 网络安全

- 仅允许 HTTPS Provider 接口。
- 禁止忽略 TLS 证书错误。
- 自定义 Base URL 需要用户主动确认。
- 不使用浏览器 Cookie、网页抓取或非公开接口。

### 17.4 Mac App Store 隐私要求

- 在 App Store Connect 和应用设置中提供可访问的隐私政策链接。
- App Privacy 信息准确披露位置、诊断和其他可能收集的数据；若数据只保存在本机，应按 Apple 当前口径判断是否构成收集。
- 使用定位前展示明确目的说明，并在 `Info.plist` 中提供相应 Usage Description。
- 定位和通知均为可选权限；拒绝权限不能阻止查看手工城市天气和应用核心用量功能。
- 不使用临时沙箱例外读取其他应用容器或 AI 工具的私有文件。

## 18. 非功能需求

### 18.1 性能

- 固定页面切换 ≤ 100 毫秒。
- 图表更新不阻塞主线程超过 16 毫秒。
- 空闲状态不以 60 FPS 持续重绘。
- 时间每秒只更新对应文本节点。
- Provider 拉取、数据库和价格计算不得在主 UI 线程执行。

### 18.2 稳定性

- 单个 Connector 崩溃或失败不影响其他 Connector。
- 网络断开后自动恢复。
- 应用异常退出后可恢复最后页面和显示配置。
- 数据库写入需要事务和迁移版本。
- 连续运行 72 小时不应出现持续内存增长。

### 18.3 可维护性

- Provider Connector 与 UI 解耦。
- 套餐和 Token 数据模型独立。
- 价格规则版本化。
- 所有外部接口均有 Mock 数据与契约测试。
- 不将 Provider 私有字段直接绑定到页面组件。

### 18.4 可访问性

- 所有交互元素提供可读标签。
- 支持键盘焦点和 Tab 导航。
- 数据图表提供文本摘要。
- 支持系统减少动态效果设置。

### 18.5 Mac App Store 与沙箱

- 应用必须启用 App Sandbox。
- 启用出站网络客户端权限，用于天气和 Provider HTTPS 请求。
- 启用定位权限，仅在用户使用天气定位功能时调用 Core Location。
- 导出通过 `NSSavePanel` 获取用户选定文件写权限；不申请整个 Documents/Downloads 目录访问。
- 登录启动使用 Apple 当前推荐的 ServiceManagement API，并在用户主动开启后生效。
- 应用为自包含安装包，不安装驱动、内核扩展、外部守护进程或下载可执行代码。
- 提交前完成签名、App Sandbox 真机验证、App Privacy、隐私政策、截图、描述、支持页面和审核说明。
- 审核说明应提供可用的演示/测试方式，避免要求审核人员提供真实高权限 Provider 凭据。

## 19. 推荐技术方案

### 19.1 客户端

推荐使用 SwiftUI + AppKit：

- SwiftUI 构建固定看板和设置页面。
- AppKit 管理 `NSScreen`、无边框展示窗口和屏幕重连。
- ServiceManagement 实现登录启动。
- Keychain Services 存储凭据。
- Core Location 获取天气坐标，并支持手工城市回退。
- UserNotifications 提供套餐、预算、余额和同步失败告警。
- NSSavePanel 和安全作用域书签处理用户主动导出。
- URLSession 调用 Provider 和天气 API。
- SQLite 保存缓存、历史用量和价格规则。

HTML 原型是视觉和交互参考，不要求生产版本继续使用 Web 技术。若团队更熟悉前端，也可评估 Tauri；不建议为单一常驻副屏优先采用 Electron。

### 19.2 模块划分

```text
App
├── DisplayController
├── DashboardStore
├── WeatherService
├── UsageEngine
│   ├── PlanAggregator
│   ├── TokenAggregator
│   ├── CostCalculator
│   ├── PricingCatalog
│   ├── ExportService
│   └── AlertEvaluator
├── ConnectorRegistry
│   ├── CodexConnector
│   ├── OpenAIConnector
│   ├── DeepSeekConnector
│   ├── OpenRouterConnector
│   ├── GeminiConnector
│   ├── GLMConnector
│   ├── KimiConnector
│   └── MiniMaxConnector
├── CredentialStore
├── NotificationService
├── LocationService
├── LocalDatabase
└── Views
    ├── Overview
    ├── Plans
    ├── Tokens
    └── Settings
```

## 20. 数据存储建议

建议包含以下表或等价对象：

| 表 | 用途 |
|---|---|
| `providers` | Provider 类型、名称、启用状态、刷新配置；不保存明文密钥 |
| `accounts` | 个人/组织账户别名、范围及项目/工作空间引用；不保存明文凭据 |
| `plan_snapshots` | 套餐窗口快照 |
| `usage_buckets` | 分钟/小时/日 Token 聚合 |
| `cost_buckets` | 费用和币种聚合 |
| `balances` | 余额历史 |
| `pricing_rules` | 版本化价格规则 |
| `weather_cache` | 最近天气数据 |
| `alert_rules` | 套餐、预算、余额和同步失败告警规则 |
| `alert_events` | 告警触发、恢复、冷却和通知记录 |
| `export_jobs` | 导出范围、格式、结果和错误；不长期保存导出文件内容 |
| `app_preferences` | 页面、目标屏幕、时区、亮度等设置 |

历史数据保留策略（已确认）：

- 分钟数据：7 天。
- 小时数据：90 天。
- 日数据：长期保留，默认 2 年。
- 用户可在设置中清空全部本地历史。
- 导出不改变本地保留策略；过期数据聚合或删除前不要求自动备份。

## 21. 埋点与诊断

产品默认不需要远程用户行为分析。为本地诊断建议记录：

- 应用启动、退出和异常恢复。
- 副屏连接、断开和分辨率变化。
- Connector 同步成功、失败类型和耗时。
- 数据库迁移结果。
- 不包含密钥、Prompt、响应正文和完整账户标识。

如未来启用远程遥测，必须获得用户明确同意并提供关闭选项。

## 22. 验收标准

### 22.1 总览

- 在 1280×720 下所有内容完整显示，无滚动条和遮挡。
- 时间每秒更新，日期、星期和时区正确。
- 天气包含温度、体感、降雨、湿度及小时预报。
- 主套餐显示使用比例和重置时间。
- 至少两个按 Token/余额 Provider 摘要可同时显示。
- 在 Wokyis M5 真机正常观看距离下，核心信息无需系统缩放即可辨认。

### 22.2 套餐页

- 支持显示多个额度窗口。
- 官方数据与本地估算有明确区别。
- 页面中没有配置或添加入口。
- 用量为 0%、100% 时均能正确显示。

### 22.3 Token 页

- 可在国内外 Provider 间切换，MVP 至少覆盖 OpenAI、Anthropic、DeepSeek、GLM、Kimi、MiniMax、OpenRouter 和 Gemini 的 Mock/真实 Connector 状态。
- 日、周、月切换会更新图表时间粒度。
- 输入、输出、费用、模型、缓存和预算同时更新。
- 页面中没有添加 Provider 或配置入口。

### 22.4 设置页

- 顶部右侧是唯一设置入口。
- 可以添加和编辑 Provider。
- 可以配置天气、时区和刷新间隔。
- 可以选择目标屏幕和登录启动。
- 可以配置个人与组织账户，并选择组织、项目或工作空间。
- 可以查看和管理定位、通知授权状态。
- 可以配置套餐、预算、余额和同步失败告警。
- 可以按指定范围导出 CSV 或 JSON。
- 凭据不会显示或写入普通配置文件。

### 22.5 稳定性

- 网络断开不造成应用退出或空白页面。
- Provider 认证失败时其他数据仍正常显示。
- 副屏断开和重连后画面自动恢复。
- 睡眠恢复后时间立即正确，数据完成一次同步。

### 22.6 Mac App Store

- App Sandbox 开启，应用在沙箱环境下全部核心功能可用。
- 拒绝定位后可手工选择城市；拒绝通知后其他功能不受影响。
- 导出通过系统保存面板成功写入用户选择的位置。
- 登录启动仅在用户主动开启后生效。
- 隐私政策、App Privacy 信息、审核说明和截图齐备。

## 23. 测试清单

### 功能测试

- 时间跨分钟、跨日、跨月。
- 时区修改和系统时区变化。
- 天气正常、超时、无网络、无数据。
- 套餐 0%、79%、80%、95%、100%。
- Provider 返回多额度窗口。
- Token 为 0、超大数、缺少缓存字段。
- 正负费用调整项和不同币种。
- 余额为 0、未知、负数或过期。
- 日/周/月切换。
- Provider 添加、编辑、停用、删除。
- 同一 Provider 添加个人和组织账户，验证数据隔离与合并规则。
- GLM、Kimi、MiniMax 的正常响应、余额/套餐缺失和 usage 字段差异。
- CSV/JSON 导出全部字段、中文、超大数据量和取消保存。
- 套餐、预算、余额、同步失败告警的触发、去重、恢复和冷却。
- 拒绝、允许、撤销定位权限；手工城市回退。
- 拒绝、允许、撤销通知权限。
- Keychain 授权失败。

### 显示测试

- Wokyis M5 1280×720 真机显示。
- 非 1280×720 屏幕等比缩放。
- 不同 macOS 字体渲染差异。
- 5 寸屏实际观看距离下的字号可读性。
- 高对比度、减少动态效果。
- 长 Provider 名称、长模型名称和大金额。

### 稳定性测试

- 连续运行 72 小时。
- 每分钟同步运行 24 小时。
- 频繁插拔副屏 50 次。
- 睡眠/唤醒循环 20 次。
- 断网后恢复。
- Provider 429、401、403、500 和超时。
- Mac App Store 沙箱下出站网络、Keychain、定位、通知和导出。

## 24. 里程碑建议

### M0：硬件验证（2–3 天）

- 使用 Wokyis M5 真机确认可被 macOS 识别为 `NSScreen`。
- 验证 1280×720、显示器稳定标识、刷新率、字体可读性、休眠与重连。
- 验证实际使用的 M5 接入版本和链路，不在应用内依赖额外驱动。

### M1：应用骨架（1 周）

- macOS 原生应用壳。
- 副屏控制、开机启动和设置页。
- 时间、日期、Core Location、Mock/真实天气。
- 四个页面与视觉系统。
- App Sandbox、Keychain、通知权限和导出基础能力。

### M2：用量 MVP（2–3 周）

- Codex 套餐明确降级状态；真实 Connector 后置到 GATE-02 重开后。
- OpenAI Usage/Costs。
- Anthropic、DeepSeek 与 OpenRouter。
- GLM、Kimi 与 MiniMax。
- 个人/组织账户模型。
- SQLite、本地缓存和 Keychain。
- CSV/JSON 导出与告警规则。

### M3：稳定与 App Store 发布（1–2 周）

- 错误状态、离线恢复、睡眠重连。
- 真实性能测试和 72 小时稳定性测试。
- App Sandbox 全功能回归。
- 隐私政策、App Privacy、产品页文案、截图、审核说明和支持页面。
- Archive、签名、TestFlight/内部测试、App Store Connect 提交与审核修正。

整体 MVP 预计 4–7 周，取决于国产 Provider 数据接口完整度、组织凭据可用性和 App Store 审核反馈。

## 25. 风险与应对

| 风险 | 影响 | 应对方式 |
|---|---|---|
| Wokyis M5 在不同接入版本下显示标识不一致 | 自动选择错误屏幕或重连失败 | 使用系统显示器标识组合并保留手工选择；对实际设备版本做真机回归 |
| 个人订阅没有公开用量 API | 无法显示可靠套餐数据 | 只使用官方能力或明确标注本地估算，禁止网页抓取 |
| GLM、Kimi、MiniMax 等国产 Provider 的账户/套餐接口能力不同 | 无法统一获得完整历史或套餐余额 | Connector 能力声明、响应 usage 本地聚合、数据来源标记和降级展示 |
| Provider 价格频繁变化 | 本地费用不准确 | 版本化价格目录；官方 Costs 优先 |
| Admin Key 权限过高 | 凭据泄漏风险较大 | Keychain、最小权限、明确授权提示 |
| 个人与组织数据重复 | 总费用被重复计算 | 账户范围、组织/项目键和去重规则；默认分开展示 |
| 不同 Provider 计费口径不一致 | 用户误解数据 | 套餐、Token、余额分离展示，标记数据来源 |
| 高频轮询触发限流 | 数据中断 | 缓存、事件驱动、指数退避和可配置频率 |
| 5 寸屏字号过小 | 实际不可读 | 真机验证；正文不低于 14 px，辅助信息不低于 11 px |
| OLED 长期固定画面 | 烧屏风险 | 夜间降亮度、像素漂移、可配置休眠 |
| 定位或通知权限被拒绝 | 天气自动定位或告警不可用 | 手工城市回退、设置内权限状态说明；核心用量功能不依赖权限 |
| Mac App Store 沙箱限制 | 导出、登录启动或外部协作能力受限 | 从 M1 起在沙箱中开发；导出使用 NSSavePanel；避免私有文件和临时例外 |
| App Store 审核无法使用真实 Provider 凭据 | 审核人员无法验证核心功能 | 提供内置演示数据、审核模式和完整审核说明，不内置生产密钥 |

## 26. 已确认产品决策

| 编号 | 决策 | 对产品与技术的影响 |
|---|---|---|
| DEC-001 | 目标副屏为 Wokyis M5 | 以 5 英寸、1280×720 标准外接屏为基准，必须真机验证显示标识、睡眠和重连 |
| DEC-002 | 不支持触摸 | 不设计触控手势；所有交互支持鼠标、触控板和键盘，产品以被动查看为主 |
| DEC-003 | 支持国产大模型厂商 | GLM、Kimi、MiniMax、DeepSeek 进入 MVP；千问、豆包、百川列入 P1 扩展 |
| DEC-004 | 支持个人及组织/团队账户 | 建立账户范围和组织/项目层级，提供多账户配置、隔离和去重规则 |
| DEC-005 | 上架 Mac App Store | 从第一版启用 App Sandbox，并准备隐私政策、App Privacy、审核数据和上架材料 |
| DEC-006 | 允许使用定位权限 | 使用 Core Location 获取天气位置，拒绝授权时回退到手工城市；不保存位置轨迹 |
| DEC-007 | 采用既定历史保留周期并支持导出 | 分钟 7 天、小时 90 天、日数据默认 2 年；P0 支持 CSV/JSON 导出 |
| DEC-008 | 支持可配置告警通知 | P0 支持套餐、预算、余额、同步失败告警，包含阈值、静默期、冷却和通知跳转 |

## 27. 原型说明

交互原型位于：

```text
prototype/index.html
```

原型特性：

- 单文件 HTML，无外部依赖。
- 逻辑画布固定为 1280×720。
- 浏览器尺寸变化时自动等比缩放。
- 包含总览、套餐、Token、设置四个页面。
- 套餐和 Token 页面没有配置入口。
- 右上角提供唯一设置入口。
- 所有数据窗口固定，不支持拖拽、关闭或缩放。
- 不包含 Agent 状态、系统菜单复刻或隐私模式。

原型中的数据均为演示数据，不发起真实 Provider 或天气请求。

## 28. 参考接口

- OpenAI Usage / Costs API：`https://developers.openai.com/api/reference/resources/admin/subresources/organization/subresources/usage`
- Codex App Server：`https://developers.openai.com/codex/app-server`
- Anthropic Usage & Cost API：`https://platform.claude.com/docs/en/manage-claude/usage-cost-api`
- Gemini Token 文档：`https://ai.google.dev/gemini-api/docs/tokens`
- OpenRouter Credits API：`https://openrouter.ai/docs/api/api-reference/credits/get-credits`
- DeepSeek Balance API：`https://api-docs.deepseek.com/zh-cn/api/get-user-balance`
- 智谱 GLM HTTP API：`https://docs.bigmodel.cn/cn/guide/develop/http/introduction`
- 智谱费用说明：`https://docs.bigmodel.cn/cn/faq/fee-issues`
- Kimi API Overview：`https://platform.kimi.ai/docs/api/overview`
- Kimi Balance API：`https://platform.kimi.ai/docs/api/balance`
- MiniMax Token Plan：`https://platform.minimax.io/docs/token-plan/intro`
- MiniMax 账户说明：`https://platform.minimaxi.com/docs/faq/about-account`
- Open-Meteo：`https://open-meteo.com/en/docs`
- Apple NSScreen：`https://developer.apple.com/documentation/AppKit/NSScreen/screens`
- Apple Core Location：`https://developer.apple.com/documentation/corelocation`
- Apple App Sandbox：`https://developer.apple.com/documentation/xcode/configuring-the-macos-app-sandbox`
- Apple App Review Guidelines：`https://developer.apple.com/app-store/review/guidelines/`
- Apple App Privacy Details：`https://developer.apple.com/app-store/app-privacy-details/`
