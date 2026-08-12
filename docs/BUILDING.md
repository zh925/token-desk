# Build baseline

Token Desk targets macOS 14 or later and uses Swift 6 language mode with complete strict
concurrency checking. The repository is pinned to Xcode 26.6 (`17F113`) in `.xcode-version`.
The CI runner selects `/Applications/Xcode_26.6.app/Contents/Developer` explicitly instead of
depending on the moving `macos-latest` default.

## Local prerequisites

- Xcode 26.6 with its macOS SDK installed.
- The active developer directory set to the matching full Xcode installation.
- Git access to resolve the public GRDB Swift package.

Open `TokenDesk.xcodeproj` and use the shared `TokenDesk` scheme, or run:

```sh
swift package resolve --package-path Packages/TokenDeskKit
swift format lint --strict --recursive TokenDesk Packages TokenDeskTests TokenDeskUITests
swift test --package-path Packages/TokenDeskKit \
  -Xswiftc -warnings-as-errors -Xswiftc -strict-concurrency=complete
xcodebuild -project TokenDesk.xcodeproj -scheme TokenDesk \
  -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO \
  -only-testing:TokenDeskTests test
xcodebuild -project TokenDesk.xcodeproj -scheme TokenDesk \
  -configuration Release -destination 'platform=macOS' ENABLE_TESTABILITY=YES \
  -resultBundlePath TD060-ui.xcresult \
  -only-testing:TokenDeskUITests/TokenDeskAcceptanceUITests test
xcodebuild -project TokenDesk.xcodeproj -scheme TokenDesk \
  -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project TokenDesk.xcodeproj -scheme TokenDesk \
  -configuration Release -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
./scripts/secret-scan.sh
./scripts/fixture-lint.py
```

TD-064 Release Archive 的最终签名、entitlement 与私有 framework 检查见
`docs/validation/TD-064_RELEASE_SANDBOX.md`。开发机可生成明确标注的 ad-hoc Archive 作为
构建证据，但发布验收必须使用 Apple 签名身份并以严格模式运行
`scripts/verify-release-archive.sh`。

`Package.resolved` pins the GRDB revision selected from the approved `7.x` range. Dependency
updates must change the lock file in a focused pull request and repeat both build configurations.

## Security configuration

The application target enables App Sandbox and Hardened Runtime in Debug and Release. Its Sandbox
capabilities are outgoing network access, location, and read/write access to the single file chosen
through a system panel. Notifications, Keychain, and `SMAppService.mainApp` do not require broader
container or file access. Final Apple signing and clean-account runtime evidence remain explicit
release acceptance work; unsigned or ad-hoc builds do not claim those checks passed.

Unsigned Debug CI builds and ad-hoc Release Archives prove compilation and settings consistency but
do not replace Apple-signed Release, Mac App Store, or physical Wokyis M5 verification. TD-064 owns
that evidence.

## UI acceptance evidence

`TokenDeskAcceptanceUITests` launches a sandboxed Release build in a deterministic App Review
mode. It fixes the clock, isolates preferences, renders a borderless 1280×720 canvas, exercises
the four primary pages and settings sections, audits actionable controls and hit regions, checks
VoiceOver labels and chart summaries, and verifies the Reduce Motion path. Screenshot baselines
live in `TokenDeskUITests/Baselines`; the comparison normalizes images to 160×90 luminance and
fails above either 3.5% mean delta or 20% materially changed pixels.

On a UI failure, CI retains the `.xcresult` for 14 days. Export its screenshots with
`xcrun xcresulttool export attachments --path TD060-ui.xcresult --output-path attachments`.
Baseline changes require visual review of all four `TokenDesk-*-current` PNGs and a clean rerun.
Automated results do not replace manual VoiceOver listening, signed Release validation, or the
Wokyis M5 viewing-distance check; those remain part of TD-064/TD-065 release acceptance.
