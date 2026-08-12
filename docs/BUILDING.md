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
