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

`Package.resolved` pins the GRDB revision selected from the approved `7.x` range. Dependency
updates must change the lock file in a focused pull request and repeat both build configurations.

## Security configuration

The application target enables App Sandbox and Hardened Runtime in Debug and Release. Its only
initial Sandbox capability is outgoing network access. Location, notifications, user-selected
exports, Keychain, login items, and signing are introduced and verified by their dedicated tasks;
this baseline does not claim those runtime capabilities are already validated.

Unsigned CI builds prove compilation and settings consistency but do not replace signed Release,
Archive, Mac App Store, or physical Wokyis M5 verification. TD-064 owns that evidence.

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
