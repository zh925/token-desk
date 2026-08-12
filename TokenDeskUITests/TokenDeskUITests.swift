import XCTest

@MainActor
final class TokenDeskUITests: XCTestCase {
    func testAppShellFitsBaselineAndUsesSingleSettingsEntry() {
        let application = XCUIApplication()
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

        for section in ["providers", "weather", "display", "notifications", "dataExport"] {
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
}
