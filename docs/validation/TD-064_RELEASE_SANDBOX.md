# TD-064 Release Sandbox、签名与 Archive 回归

> 记录日期：2026-08-12。自动化结论只覆盖本页列出的可复核证据。Apple 签名身份、
> 干净 macOS 账户的交互权限矩阵和 Wokyis M5 真机必须由持有证书与设备的验收人员补齐；
> 在证据补齐前不得将这些项目标记为通过。

## 发布边界

- Release 与 Debug 都启用 App Sandbox 和 Hardened Runtime。
- 最终签名 entitlement 的允许集合是 App Sandbox、出站网络、定位、用户选择的单文件读写，
  以及签名过程注入的 application/team/keychain 标识。禁止临时例外、目录级访问、入站网络、
  Apple Events、Mach lookup 和其他应用容器访问。
- 导出只使用 `NSSavePanel` 取得单个目标文件权限。`com.apple.security.files.user-selected.read-write`
  是这条沙箱路径所需的最小文件 entitlement；不得改为 Documents/Downloads 广泛访问。
- 定位、UserNotifications、`SMAppService.mainApp`、Keychain 和出站 HTTPS 都使用公开系统 API。
  Codex 真实连接仍按 GATE-02 维持 P0 不支持，不读取 `~/.codex`、Cookie 或其他应用容器。

## 可复核自动化

在仓库根目录执行完整测试后，生成 Release Archive。没有 Apple 签名身份的开发机只允许生成
明确标注的 ad-hoc 证据，不能替代发布验收：

```sh
xcodebuild -project TokenDesk.xcodeproj -scheme TokenDesk \
  -configuration Release -destination 'generic/platform=macOS' \
  -archivePath DerivedData/TokenDesk.xcarchive \
  -disableAutomaticPackageResolution \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= \
  AD_HOC_CODE_SIGNING_ALLOWED=YES archive
ALLOW_ADHOC=1 ./scripts/verify-release-archive.sh DerivedData/TokenDesk.xcarchive
```

发布验收必须由 Xcode 的 Token Desk scheme 执行 Archive，使用团队的 Apple Development 或
Apple Distribution 身份，然后在不设置 `ALLOW_ADHOC` 的情况下运行：

```sh
./scripts/verify-release-archive.sh /path/to/TokenDesk.xcarchive
```

脚本会拒绝无效或 ad-hoc 发布签名、缺少 Hardened Runtime、缺少所需 entitlement、临时例外、
广泛文件访问、私有 framework、错误 bundle ID、低于 macOS 14 的部署目标和不完整 Archive。
自动化还应运行 `docs/BUILDING.md` 中的格式、Swift package、app unit、Debug/Release build、
fixture 与 secret 检查。

## 干净账户真机矩阵

所有行必须针对同一个最终 Apple 签名 Archive 导出的 Release App 执行，并保存 macOS 版本、
App 版本/构建号、commit、签名 Authority/TeamIdentifier、操作步骤、实际结果和截图或日志引用。

| 能力 | 步骤 | 通过标准 |
| --- | --- | --- |
| 首次启动与沙箱 | 在未运行过 Token Desk 的 macOS 14+ 账户启动 | 正常进入总览；容器、数据库和 Keychain 可用；无沙箱拒绝 |
| 出站网络 | 用官方公开接口测试一个可用 Provider，再切换离线 | HTTPS 同步成功；离线显示可恢复状态；无入站网络 entitlement |
| Keychain | 保存凭据、重启、测试连接、删除账户 | 凭据不回显且重启可用；SQLite、日志与导出无秘密；删除同步清理 Keychain |
| 定位拒绝 | 首次请求选择拒绝，输入手工城市并重启 | 用量核心功能正常；手工城市天气可用；不重复强制请求 |
| 定位允许/撤销 | 允许一次定位，随后在系统设置撤销 | 定位天气可用；撤销后安全降级到手工城市 |
| 通知拒绝 | 主动开启告警后拒绝权限 | 告警关闭或显示拒绝状态；其余功能正常；启动时不提前请求 |
| 通知允许/撤销 | 允许、发送测试通知、点击通知，再撤销 | 收到无敏感字段的本地通知；应用可打开；撤销后安全降级 |
| CSV/JSON 导出 | 分别导出含中文的数据到用户选择的位置 | 两种格式可写入且字段白名单正确；只授权所选文件 |
| 取消导出 | 在保存面板取消 | 不创建或修改文件；应用无错误状态残留 |
| 登录启动 | 开启 `SMAppService`，按系统提示批准，登出/登录，再关闭 | 登录后启动且状态准确；关闭后不再启动 |
| Wokyis M5 | 连接、选择、重启、断开、重连 1280×720 非触控副屏 | 指纹恢复且断连安全回退；窗口不越界；键盘主流程可用 |
| Archive/签名 | Organizer Validate App；复查导出包 | 验证通过；所有嵌套代码签名有效；脚本在严格模式通过 |

通知点击当前只验证“打开应用”；Provider 深链由 ALT-006 的专门集成验收确认。若最终 Archive 的
provisioning profile 注入了允许集合之外的 entitlement，必须先审查并更新本页策略，不能绕过脚本。

## 当前证据与未验证项

- 本变更补齐 sandbox 导出所需的用户选择单文件读写 entitlement，并由 Archive 脚本校验最终签名值。
- Apple silicon、Xcode 26.6 (`17F113`) 生成的 universal ad-hoc Release Archive 已通过校验：
  `arm64 x86_64`、Hardened Runtime、macOS 14.0、四项最小 entitlement、有效嵌套签名、完整
  Archive metadata，且主可执行文件未链接 PrivateFrameworks。严格模式按预期拒绝该 ad-hoc 签名。
- `swift test` 通过 19 个 XCTest 合同测试和 120 个 Swift Testing 测试；app target 的 3 个
  `TokenDeskTests` 通过。Swift format、fixture lint、secret scan、plist/shell 语法和 diff 检查通过。
- 源码定向扫描未发现临时沙箱例外、PrivateFrameworks、Home/Codex 私有目录、Cookie 或 WebView
  访问。最终签名 allowlist 仍由 Archive 脚本独立验证，不能只依赖源码扫描。
- 当前 Keychain 中没有有效代码签名身份，因此 Apple Development/Distribution 签名、Organizer
  Validation 与商店导出未执行。
- 当前运行环境没有干净 GUI 账户、通知/定位人工授权条件或 Wokyis M5，因此上表真机交互项未执行。

这些缺口是发布验收工作，不否定已完成的配置修复和自动化证据，但在补齐前 TD-064 的完整发布
门槛仍未通过，也不得提升依赖它的最终提交任务。
