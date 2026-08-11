import SwiftUI
import TokenDeskFeatures
import XCTest
@testable import TokenDesk

@MainActor
final class TokenDeskTests: XCTestCase {
    func testAppTargetLoads() {
        XCTAssertNotNil(ContentView())
    }

    func testAppShellRendersAt1280By720() throws {
        let date = Date(timeIntervalSince1970: 1_786_417_268)
        for route in AppRoute.primaryNavigation {
            let clock = DashboardClock(
                now: date,
                timeZoneOverrideIdentifier: "Asia/Shanghai",
                nowProvider: { date }
            )
            let shell = TokenDeskAppShell(router: AppRouter(route: route), clock: clock)
            let renderer = ImageRenderer(content: shell)
            renderer.scale = 1

            let image = try XCTUnwrap(renderer.nsImage)
            XCTAssertEqual(image.size.width, 1_280, accuracy: 1)
            XCTAssertEqual(image.size.height, 720, accuracy: 1)

            let attachment = XCTAttachment(image: image)
            attachment.name = "TokenDesk-\(route.rawValue)-1280x720"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }
}
