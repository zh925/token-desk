import SwiftUI
import XCTest
@testable import TokenDesk

@MainActor
final class TokenDeskTests: XCTestCase {
    func testAppTargetLoads() {
        XCTAssertNotNil(ContentView())
    }

    func testDesignCatalogRendersAt1280By720() throws {
        let renderer = ImageRenderer(content: ContentView())
        renderer.scale = 1

        let image = try XCTUnwrap(renderer.nsImage)
        XCTAssertEqual(image.size.width, 1_280, accuracy: 1)
        XCTAssertEqual(image.size.height, 720, accuracy: 1)

        let attachment = XCTAttachment(image: image)
        attachment.name = "TokenDeskDesign-1280x720"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
