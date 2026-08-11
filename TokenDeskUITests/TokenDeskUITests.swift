import XCTest

@MainActor
final class TokenDeskUITests: XCTestCase {
    func testDesignCatalogFitsBaselineAndUsesAccessibleTargets() {
        let application = XCUIApplication()
        application.launch()

        XCTAssertTrue(application.staticTexts["Token Desk"].waitForExistence(timeout: 2))
        XCTAssertTrue(application.staticTexts["Design system ready"].exists)

        let button = application.buttons["standard-button"]
        XCTAssertTrue(button.exists)
        XCTAssertGreaterThanOrEqual(button.frame.width, 40)
        XCTAssertGreaterThanOrEqual(button.frame.height, 40)

        let canvas = application.groups["design-system-canvas"]
        XCTAssertTrue(canvas.exists)
        XCTAssertEqual(canvas.frame.width, 1_280, accuracy: 1)
        XCTAssertEqual(canvas.frame.height, 720, accuracy: 1)

        let attachment = XCTAttachment(screenshot: application.screenshot())
        attachment.name = "TokenDeskDesign-1280x720"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
