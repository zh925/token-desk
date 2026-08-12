# TD-065 built-in App Review demonstration

> Reviewed: 2026-08-12. This is deterministic development evidence. Signed Release App Sandbox
> execution remains part of TD-064 and store metadata/review-copy assembly remains part of TD-066.

## Reviewer entry and exit

No Provider credential, organization role, location permission, notification permission, or existing
account is required.

1. Launch Token Desk and select the single **设置** entry in the upper-right corner.
2. Select **App Review**, then **代表性数据**.
3. Verify **1 总览**, **2 套餐**, **3 Token**, and return to **设置**.
4. In **App Review**, select **离线降级**, **认证失败**, and **限流错误** in turn. Revisit the
   page named below after each selection.
5. Select **退出演示并恢复本地数据** to resume cache reads and normal synchronization.

For deterministic UI automation, launch with `--app-review-demo`. This argument selects the same
built-in representative scenario; it is not a credential or hidden production capability.

## Expected evidence matrix

| Scenario | Page to inspect | Expected result |
| --- | --- | --- |
| Representative | All four | Header and page source labels say App Review/demo; plans include 0% and 100%; Token ranges and Providers switch together |
| Offline | Overview, Plans, Token | Cached values remain visible; overview reports a partial offline issue; plans are stale; Token values retain an offline banner |
| Authentication | Plans, Token | OpenAI shows a redacted authentication failure with cached data; other Providers stay readable |
| Rate limited | Overview, Token | The OpenAI state names `Retry-After 60` and contains no substitute numeric value; other Providers stay readable |
| Unsupported | Plans, Token → Codex | GATE-02 remains explicit; no Cookie/private-container access and no invented quota or reset value |

The fixed header disables synchronization while a demonstration scenario is active. Changing a
scenario cancels an in-flight dashboard refresh before publishing the fixture state.

## Data and privacy contract

- Demonstration values are compiled static snapshots. They contain no API key, email address,
  organization ID, project ID, workspace ID, remote account identifier, prompt, or response body.
- Plans mark values as `◇ 演示数据` or a visibly distinct estimate. Token cost labels start with
  `◇ 演示`; overview weather and usage panels say `演示数据`; the header says `APP REVIEW 演示`.
- Demonstration selection does not write usage, cost, balance, plan, or weather records to SQLite and
  does not place credential material in UserDefaults or Keychain.
- Codex fixtures are value-free because GATE-02 is closed. Demonstration mode never converts them
  into apparent production data.
- Leaving demonstration mode explicitly reloads the local cache and normal official/public data
  boundaries; no demonstration value is used as a production fallback.

## Reproducible automated checks

From the repository root:

```sh
swift format lint --strict --recursive TokenDesk Packages TokenDeskTests TokenDeskUITests
swift test --package-path Packages/TokenDeskKit \
  -Xswiftc -warnings-as-errors -Xswiftc -strict-concurrency=complete
xcodebuild -quiet -project TokenDesk.xcodeproj -scheme TokenDesk \
  -configuration Release -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
xcodebuild -quiet -project TokenDesk.xcodeproj -scheme TokenDesk \
  -destination 'platform=macOS' test
./scripts/secret-scan.sh
./scripts/fixture-lint.py
```

`appReviewDemoIsCredentialFreeVisiblyLabeledAndCoversFourScenarios` locks the state matrix and the
permanent Token labels. `testCredentialFreeAppReviewWorkflowCoversPagesErrorsAndDegradation` walks
the review route through all four top-level pages and the three failure/degradation selectors.

## Deferred release acceptance

TD-064 must repeat the workflow in a signed Release App Sandbox build and confirm the final
entitlements and absence of unauthorized file access. TD-066 should reuse the entry/exit steps and
expected-state wording in the App Review notes and store materials. These are downstream release
checks, not evidence supplied by this development task.
