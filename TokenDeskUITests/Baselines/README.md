These 1280×720 XCUITest baselines use deterministic App Review fixtures and a fixed clock.

To intentionally update them, run the primary acceptance test with an `.xcresult` bundle and
export its attachments with `xcrun xcresulttool export attachments`. Review each
`TokenDesk-*-current` PNG before replacing the matching baseline, then rerun the test to prove the
visual-difference gate is active. Missing or changed baselines fail while retaining both current
and baseline images as reproducible evidence.
