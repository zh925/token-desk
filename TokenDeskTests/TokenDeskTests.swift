import XCTest
@testable import TokenDesk

@MainActor
final class TokenDeskTests: XCTestCase {
    func testAppTargetLoads() {
        XCTAssertNotNil(ContentView())
    }
}
