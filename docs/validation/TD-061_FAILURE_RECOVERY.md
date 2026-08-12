## TD-061 failure and recovery validation

This review covers the development-level failure matrix required by PRD 22.5. Automated evidence
uses deterministic fakes and temporary databases; it does not claim physical Wokyis M5 or signed
Release App Sandbox acceptance.

## Result

The development delivery is reviewable. Network, 401, 403, 429, 500, cancellation, display-event,
wake, and database-failure paths have reproducible automated coverage. Cached values remain visible
with a typed degraded state, failures stay isolated, and a later successful refresh clears the
degraded state.

Final release acceptance is not yet passed. Physical sleep/wake and disconnect/reconnect evidence is
owned by TD-063, and signed Release App Sandbox/Archive evidence is owned by TD-064. Neither is
represented as completed here.

## Reproducible evidence

| Scenario | Expected behavior | Automated evidence | Development result |
| --- | --- | --- | --- |
| Offline/network | Keep cached values, label offline, retry idempotent reads, recover on success | `productionDashboardIsolatesAuthenticationAndOfflineAsPartialData`, `productionDashboardRecoversAfterOfflineFailure`, `syncRetriesNetworkAndRetryAfterButNeverRetriesAuthentication` | Pass |
| HTTP 401 | Do not retry; isolate the affected Provider and preserve other/cached data | `productionDashboardIsolatesAuthenticationAndOfflineAsPartialData`, `oneFailedProviderDoesNotAffectTheOtherEightMVPProviders`, connector contract tests | Pass |
| HTTP 403 | Do not retry; show permission failure without converting it to empty data | `productionDashboardKeepsCachedDataForPermissionAndServerFailures`, `syncRetriesServerFailureButNeverRetriesPermissionFailure`, `permissionFailureIsNotFoldedIntoAnEmptyRead` | Pass |
| HTTP 429 | Honor `Retry-After`; do not invent values when no cache exists | `productionDashboardShowsRateLimitWithoutInventingValues`, `syncRetriesNetworkAndRetryAfterButNeverRetriesAuthentication`, connector contract tests | Pass |
| HTTP 500 | Retry bounded idempotent reads; preserve cached values and show unavailable state | `productionDashboardKeepsCachedDataForPermissionAndServerFailures`, `syncRetriesServerFailureButNeverRetriesPermissionFailure` | Pass |
| Cancellation | Stop before persistence and retain independent Provider results | `cancellationStopsAnInFlightProviderBeforePersistence`, `connectorReadPreservesTaskCancellation`, `weatherSyncPreservesCachedDataOnOfflineFailureAndCancellation` | Pass |
| Database read failure | Never substitute demo data; retain the last in-memory snapshot, show persistence failure on every data page, and recover on the next successful read | `productionDashboardRecoversAfterTransientDatabaseReadFailure` | Pass after fixing the Tokens-page issue propagation |
| Sleep/wake orchestration | Refresh the clock immediately, request one data refresh, and restart bounded display recovery | `clockResumeRefreshesImmediatelyAndRestartsTicker`, `wakeNotificationRestartsRecoveryAfterSleepCancelledIt`; `TokenDeskAppShell` refreshes when the scene becomes active | Pass in automation; physical cycle unverified |
| Display disconnect/reconnect | Fall back safely, re-resolve the persisted fingerprint, and stop retrying after five seconds | `displayChangeNotificationRecoversFromSafeFallback`, `manualSelectionPersistsFingerprintAndReconnectsToNewRuntimeIdentifier`, `recoveryStopsAtFiveSecondDeadlineUntilAnotherExplicitEvent` | Pass in automation; physical M5 unverified |

Run the automated gate from the repository root:

```sh
swift format lint --strict --recursive TokenDesk Packages TokenDeskTests TokenDeskUITests
swift test --package-path Packages/TokenDeskKit \
  -Xswiftc -warnings-as-errors -Xswiftc -strict-concurrency=complete
xcodebuild -quiet -project TokenDesk.xcodeproj -scheme TokenDesk \
  -configuration Release -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
./scripts/secret-scan.sh
./scripts/fixture-lint.py
```

The unsigned Release build checks compilation and configured entitlements only. It is not evidence
that a signed/notarized application executed inside the production sandbox.

## Deferred final acceptance

TD-063 must execute the physical Wokyis M5 matrix with a Release candidate: direct and docked paths,
20 sleep/wake cycles, 50 disconnect/reconnect cycles, correct target display, visible nonblank page,
fresh clock, one post-wake sync, and recovery within five seconds. Record every failure combination
and monotonic recovery duration.

TD-064 must execute the signed Release Sandbox/Archive matrix: outbound network, Keychain,
Application Support database, location denial/manual city, notification denial, user-selected
export, and login item. Inspect the final signed entitlements and verify that logs, database, export,
fixtures, and diagnostic artifacts contain no credential material.

These deferred checks are release gates, not blockers to reviewing this development change. A final
go/no-go decision must wait for their evidence.
