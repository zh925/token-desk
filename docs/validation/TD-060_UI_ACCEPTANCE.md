## TD-060 UI acceptance matrix

The `TokenDeskAcceptanceUITests` target turns PRD 18.4 and 22.1–22.4 into a reproducible macOS
acceptance gate. UI-test launch arguments are accepted only by the test process and never alter
the normal production launch path.

| Area | Automated evidence |
| --- | --- |
| 1280×720 canvas | Exact accessibility-frame assertion and four reviewed PNG baselines |
| Overview | Clock/weather values, primary plan, two Provider summaries, visual diff |
| Plans | Multiple windows, 0% and 100% boundaries, no configuration entry, visual diff |
| Tokens | Day/week/month updates, independent cost/balance metrics, chart text alternative, visual diff |
| Settings | Single top-level entry and all six settings destinations, visual diff |
| Keyboard and VoiceOver | Existing keyboard navigation test plus page labels, non-empty button labels, chart summary, action/hit-region audits |
| Reduce Motion | Test-only environment override and frame-stability assertion after navigation |
| Failure evidence | Current screenshots retained in `.xcresult`; baseline images are also attached on visual-diff failure |

The screenshot comparator downsamples both images to 160×90 luminance values. A test fails if
the mean absolute delta exceeds 3.5% or if more than 20% of pixels differ by over 12%. This avoids
single-pixel rendering noise while still catching layout, content, and state changes.

The fixed-clock App Review fixtures contain no credentials, account identifiers, Prompt/response
content, or production usage. UI-test settings use a dedicated `UserDefaults` suite, and settings
services are unavailable test doubles, so screenshot generation neither reaches external systems
nor writes account data.

Manual VoiceOver listening, signed/notarized Release behavior, and physical Wokyis M5 legibility
remain unverified by this task and must be collected by TD-064/TD-065 before final release.
