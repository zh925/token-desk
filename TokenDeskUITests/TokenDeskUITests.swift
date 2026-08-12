import XCTest

@MainActor
final class TokenDeskUITests: XCTestCase {
    func testColdLaunchPerformance() {
        let options = XCTMeasureOptions()
        options.iterationCount = 5
        measure(
            metrics: [XCTApplicationLaunchMetric(waitUntilResponsive: true)],
            options: options
        ) {
            let application = XCUIApplication()
            application.launch()
            XCTAssertTrue(application.staticTexts["Token Desk"].waitForExistence(timeout: 2))
            application.terminate()
        }
    }

    func testActiveIdleResourcePerformance() {
        let application = XCUIApplication()
        application.launch()
        XCTAssertTrue(application.staticTexts["Token Desk"].waitForExistence(timeout: 2))
        let options = XCTMeasureOptions()
        options.iterationCount = 3

        measure(metrics: [XCTCPUMetric(), XCTMemoryMetric()], options: options) {
            Thread.sleep(forTimeInterval: 5)
        }
    }

    func testPageSwitchPerformance() {
        let application = XCUIApplication()
        application.launch()
        XCTAssertTrue(application.buttons["route-overview"].waitForExistence(timeout: 2))
        let options = XCTMeasureOptions()
        options.iterationCount = 5

        measure(metrics: [XCTClockMetric()], options: options) {
            application.buttons["route-plans"].click()
            application.buttons["route-tokens"].click()
            application.buttons["route-overview"].click()
        }
    }

    func testAppShellFitsBaselineAndUsesSingleSettingsEntry() {
        let application = XCUIApplication()
        application.launchArguments = ["--app-review-demo"]
        application.launch()

        XCTAssertTrue(application.staticTexts["Token Desk"].waitForExistence(timeout: 2))
        XCTAssertTrue(application.staticTexts["总览页面"].exists)

        let overviewButton = application.buttons["route-overview"]
        XCTAssertTrue(overviewButton.exists)
        XCTAssertGreaterThanOrEqual(overviewButton.frame.width, 40)
        XCTAssertGreaterThanOrEqual(overviewButton.frame.height, 40)

        let settingsButtons = application.buttons.matching(identifier: "settings-button")
        XCTAssertEqual(settingsButtons.count, 1)

        let canvas = application.groups["app-shell-canvas"]
        XCTAssertTrue(canvas.exists)
        XCTAssertEqual(canvas.frame.width, 1_280, accuracy: 1)
        XCTAssertEqual(canvas.frame.height, 720, accuracy: 1)

        let attachment = XCTAttachment(screenshot: application.screenshot())
        attachment.name = "TokenDeskShell-1280x720"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testKeyboardNavigationAndSettingsRoute() {
        let application = XCUIApplication()
        application.launchArguments = ["--app-review-demo"]
        application.launch()

        XCTAssertTrue(application.staticTexts["总览页面"].waitForExistence(timeout: 2))

        application.typeKey("2", modifierFlags: [])
        XCTAssertTrue(application.staticTexts["套餐页面"].waitForExistence(timeout: 1))

        application.typeKey("3", modifierFlags: [])
        XCTAssertTrue(application.staticTexts["Token页面"].waitForExistence(timeout: 1))

        application.typeKey("1", modifierFlags: [])
        XCTAssertTrue(application.staticTexts["总览页面"].waitForExistence(timeout: 1))

        application.buttons["settings-button"].click()
        XCTAssertTrue(application.staticTexts["设置页面"].waitForExistence(timeout: 1))

        for section in [
            "appReview", "providers", "weather", "display", "notifications", "dataExport",
        ] {
            XCTAssertTrue(application.buttons["settings-section-\(section)"].exists)
        }

        application.buttons["settings-section-weather"].click()
        XCTAssertTrue(application.textFields["manual-city-field"].exists)

        application.buttons["settings-section-dataExport"].click()
        XCTAssertTrue(application.buttons["export-history-button"].exists)

        let attachment = XCTAttachment(screenshot: application.screenshot())
        attachment.name = "TokenDeskSettings-1280x720"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testAllNineProvidersCanSwitchAndCodexRemainsValueFree() {
        let application = XCUIApplication()
        application.launchArguments = ["--app-review-demo"]
        application.launch()

        XCTAssertTrue(application.staticTexts["总览页面"].waitForExistence(timeout: 2))
        application.typeKey("3", modifierFlags: [])
        XCTAssertTrue(application.staticTexts["Token页面"].waitForExistence(timeout: 1))

        let providerIDs = [
            "openai", "anthropic", "deepseek", "glm", "kimi", "minimax", "openrouter", "gemini",
            "codex",
        ]
        for providerID in providerIDs {
            let provider = application.buttons["token-provider-\(providerID)"]
            XCTAssertTrue(provider.exists, "Missing Provider selector: \(providerID)")
            provider.click()
            XCTAssertTrue(provider.isSelected, "Provider did not become selected: \(providerID)")
        }

        XCTAssertTrue(
            application.descendants(matching: .any)["app-review-state-unsupported"].exists
        )
        let inventedCodexValue = application.staticTexts.matching(
            NSPredicate(format: "label CONTAINS 'Codex API'")
        ).firstMatch
        XCTAssertFalse(inventedCodexValue.exists)
    }

    func testCredentialFreeAppReviewWorkflowCoversPagesErrorsAndDegradation() {
        let application = XCUIApplication()
        application.launchArguments = ["--app-review-demo"]
        application.launch()

        XCTAssertTrue(application.staticTexts["Token Desk"].waitForExistence(timeout: 2))
        XCTAssertTrue(application.staticTexts["app-review-demo-banner"].exists)
        XCTAssertTrue(application.staticTexts["总览页面"].exists)
        XCTAssertTrue(application.staticTexts["今日用量 · 演示数据"].exists)

        application.buttons["route-plans"].click()
        XCTAssertTrue(application.staticTexts["套餐页面"].waitForExistence(timeout: 1))
        XCTAssertTrue(application.staticTexts["PLAN WINDOWS · DEMO"].exists)
        XCTAssertTrue(
            application.descendants(matching: .any)["plan-window-codex-primary"].exists
        )

        application.buttons["route-tokens"].click()
        XCTAssertTrue(application.staticTexts["Token页面"].waitForExistence(timeout: 1))
        XCTAssertTrue(application.staticTexts["TOKEN USAGE · DEMO"].exists)

        application.buttons["settings-button"].click()
        application.buttons["settings-section-appReview"].click()
        XCTAssertTrue(application.staticTexts["app-review-demo-active"].exists)

        application.buttons["app-review-scenario-authentication"].click()
        application.buttons["route-tokens"].click()
        let authenticationBanner = application.descendants(matching: .any)[
            "app-review-state-authentication"
        ]
        XCTAssertTrue(authenticationBanner.waitForExistence(timeout: 1))

        application.buttons["settings-button"].click()
        application.buttons["settings-section-appReview"].click()
        application.buttons["app-review-scenario-rateLimited"].click()
        application.buttons["route-tokens"].click()
        let rateLimitMessage = application.descendants(matching: .any)[
            "app-review-state-rate-limited"
        ]
        XCTAssertTrue(rateLimitMessage.waitForExistence(timeout: 1))

        application.buttons["settings-button"].click()
        application.buttons["settings-section-appReview"].click()
        application.buttons["app-review-scenario-offline"].click()
        application.buttons["route-overview"].click()
        let offlineBanner = application.descendants(matching: .any)["app-review-state-offline"]
        XCTAssertTrue(offlineBanner.waitForExistence(timeout: 1))
    }
}
