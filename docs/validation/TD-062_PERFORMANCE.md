## TD-062 performance validation

This record covers the TD-062 launch, resident-memory, idle-CPU, page-switch, chart,
and polling budgets. Measurements were taken on a physical Apple M4 Mac mini with
24 GB memory, macOS 26.6.1, and Xcode 26.6. The app was built with the Release
configuration for arm64.

## Results

| Budget | Release evidence | Result |
|---|---|---|
| Cold launch <= 2 s | `XCTApplicationLaunchMetric`, 5 launches: 0.472, 0.474, 0.487, 0.493, 0.475 s; average 0.480 s | Pass |
| Resident memory <= 150 MB | `XCTMemoryMetric`, 3 active-idle samples: 11,863, 11,584, 11,601 kB peak physical; average 11.41 MiB | Pass |
| Idle CPU <= 2% | `XCTCPUMetric`, 3 five-second active-idle samples: 0.001747, 0.000806, 0.001332 CPU seconds; average 0.0259% of one core | Pass |
| Page switch <= 100 ms | Release Swift Testing gate warms and rasterizes every complete dashboard page individually; every measured page is asserted below 100 ms | Pass |
| Chart main-thread block < 16 ms | Release Swift Testing gate warms the full Token page, then rasterizes it 10 times with a total measured budget below 160 ms | Pass |

The passing resource result bundle is
`/tmp/td062-release-resource-testable.xcresult`. This path is intentionally
machine-local; reproduce the run below instead of treating it as a checked-in artifact.
The UI performance build enables testability only for XCTest injection. A separate
standard Release build succeeded and its signed app contained the App Sandbox,
outbound-network, and location entitlements with no temporary file or Mach lookup
exceptions. Distribution signing and Archive validation remain owned by TD-064.

The XCTest page-switch smoke also exercises three real accessibility button clicks.
Its wall-clock metric includes XCUI process and event-synthesis overhead, so it is not
used as the in-process 100 ms acceptance measurement.

## Implemented controls

- The active polling loop now has independent one-minute usage/plan, five-minute
  cost/balance, and configurable weather lanes. It stops with the scene lifecycle and
  sleeps with tolerance instead of maintaining a busy timer.
- Provider synchronization receives only the capabilities due in the current lane, so
  a frequent usage tick cannot refetch slow-changing monetary data.
- Multi-provider, 35-day dashboard and chart projection runs outside `MainActor`, checks
  cancellation, and publishes one atomic projection back to observable UI state.
- Route changes no longer force a fresh identity for the whole content subtree.
- The one-second clock reuses its presentation formatters and stops while inactive; only
  the clock model publishes at that cadence.

## Reproduction

Run the deterministic Release render budgets:

```sh
swift test --package-path Packages/TokenDeskKit -c release \
  --filter RenderingStays \
  -Xswiftc -warnings-as-errors -Xswiftc -strict-concurrency=complete
```

Run the Release launch/resource metrics on a physical Mac:

```sh
xcodebuild test -project TokenDesk.xcodeproj -scheme TokenDesk \
  -configuration Release -destination 'platform=macOS,arch=arm64' \
  -resultBundlePath /tmp/td062-release-resource.xcresult \
  -only-testing:TokenDeskUITests/TokenDeskUITests/testColdLaunchPerformance \
  -only-testing:TokenDeskUITests/TokenDeskUITests/testActiveIdleResourcePerformance \
  ENABLE_TESTABILITY=YES CODE_SIGN_IDENTITY=-

xcrun xcresulttool get test-results metrics \
  --path /tmp/td062-release-resource.xcresult --format json
```

Verify the normal Release app separately:

```sh
xcodebuild build -project TokenDesk.xcodeproj -scheme TokenDesk \
  -configuration Release -destination 'platform=macOS,arch=arm64' \
  CODE_SIGN_IDENTITY=-

codesign -d --entitlements :- \
  ~/Library/Developer/Xcode/DerivedData/TokenDesk-*/Build/Products/Release/TokenDesk.app
```
