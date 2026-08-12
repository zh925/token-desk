# TD-052/053 settings integration evidence

## Automated coverage

The settings integration keeps each external boundary independently injectable:

- `GRDBProviderAccountManager` stores Provider and account metadata in SQLite and credential
  material only in `CredentialStore`.
- `OfficialProviderConnectionTester` performs a user-initiated official endpoint read for OpenAI,
  Anthropic, DeepSeek, Kimi, and OpenRouter. Providers without a public test endpoint report a
  credential-only or unsupported state rather than inventing connectivity.
- `DisplaySettingsServicing`, location, notifications, login items, and preferences remain platform
  protocols consumed by `SettingsStore`.
- Application database initialization runs on a dedicated actor when settings first request it,
  instead of blocking the main actor during launch.

Automated tests cover:

- multiple personal and organization configurations, project hierarchy, enable/disable, and
  restart restoration;
- secure replacement and cancellation without exposing credential values through observable view
  state or SQLite;
- deletion with retained history and deletion with removed history;
- connection-test authentication failure guidance;
- platform preference and display-target save/cancel semantics across store recreation;
- denied, allowed, and revoked location/notification paths;
- all five settings sections rendered in the fixed 1280×720 canvas.

CI-equivalent verification commands:

```sh
swift format lint --strict --recursive TokenDesk Packages TokenDeskTests TokenDeskUITests
swift test --package-path Packages/TokenDeskKit \
  -Xswiftc -warnings-as-errors -Xswiftc -strict-concurrency=complete
xcodebuild -project TokenDesk.xcodeproj -scheme TokenDesk \
  -configuration Debug -destination 'platform=macOS' \
  -disableAutomaticPackageResolution CODE_SIGNING_ALLOWED=NO \
  -only-testing:TokenDeskTests test
./scripts/secret-scan.sh
./scripts/fixture-lint.py
```

Debug and Release builds are also verified for both `arm64` and `x86_64`. The checked-in
entitlements remain limited to App Sandbox, outgoing network client, and location access.

## Release sandbox and device acceptance

Run these steps with a signed Release build. Never capture or attach real credential values,
organization identifiers, exported history, or Keychain prompts containing private data.

| Scenario | Procedure | Pass condition |
|---|---|---|
| Wokyis target | Connect the Wokyis M5, choose it, save, relaunch, then disconnect/reconnect | Selection restores by fingerprint and the dashboard safely falls back while disconnected |
| Cancel target | Select another display and cancel | Window does not move and the saved target is unchanged |
| Location denied | Deny location, enter a manual city, save, relaunch | Weather can use the manual city and usage pages remain available |
| Notification denied/revoked | Deny once, then allow and revoke in System Settings | Other features remain available and revoked alerts are persisted off |
| Login item | Enable, approve if macOS requires it, relaunch and disable | UI reflects `SMAppService` state without claiming approval early |
| Provider account | Add personal and organization accounts with least-privilege test credentials | Credential status never reveals the key; capabilities and failures remain account-specific |
| Delete Provider | Test both “retain history” and “delete history” choices | Keychain item is removed; only the selected history disposition is applied |
| Offline test | Disable networking and run a connection test | Existing configuration remains intact and the UI reports a recoverable network failure |

Hardware display behavior, real system permission sheets, ServiceManagement approval, signed
Release Keychain access, and live Provider credentials require this manual acceptance environment;
the automated suite does not mark them as completed.
