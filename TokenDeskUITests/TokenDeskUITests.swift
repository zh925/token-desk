import XCTest

@MainActor
final class TokenDeskUITests: XCTestCase {
    func testLaunchShowsProductName() {
        let application = XCUIApplication()
        application.launch()

        XCTAssertTrue(application.staticTexts["Token Desk"].waitForExistence(timeout: 2))
    }
}
