import AppKit
import SwiftUI
import TokenDeskFeatures
import TokenDeskPlatform
import XCTest
@testable import TokenDesk

@MainActor
final class TokenDeskTests: XCTestCase {
    func testAppTargetLoads() {
        XCTAssertNotNil(ContentView())
    }

    func testAppShellRendersAt1280By720() throws {
        let date = Date(timeIntervalSince1970: 1_786_417_268)
        for route in AppRoute.allCases {
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

        let settingsStore = SettingsStore()
        for section in SettingsSection.allCases {
            settingsStore.selectedSection = section
            let shell = TokenDeskAppShell(
                router: AppRouter(route: .settings),
                clock: DashboardClock(now: date, nowProvider: { date }),
                settingsStore: settingsStore
            )
            let renderer = ImageRenderer(content: shell)
            renderer.scale = 1
            let image = try XCTUnwrap(renderer.nsImage)
            let attachment = XCTAttachment(image: image)
            attachment.name = "TokenDesk-settings-\(section.rawValue)-1280x720"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    func testPageRenderingPerformanceMetrics() {
        let router = AppRouter()
        let clock = DashboardClock(
            now: Date(timeIntervalSince1970: 1_786_417_268),
            nowProvider: { Date(timeIntervalSince1970: 1_786_417_268) }
        )
        let shell = TokenDeskAppShell(router: router, clock: clock)
        let options = XCTMeasureOptions()
        options.iterationCount = 5

        measure(
            metrics: [XCTClockMetric(), XCTCPUMetric(), XCTMemoryMetric()],
            options: options
        ) {
            for route in AppRoute.allCases {
                router.select(route)
                let renderer = ImageRenderer(content: shell)
                renderer.scale = 1
                XCTAssertNotNil(renderer.nsImage)
            }
        }
        clock.stop()
    }

    func testDisplayCanvasSurvivesThreeNativeFullScreenRoundTrips() async throws {
        guard let screen = NSScreen.main else {
            throw XCTSkip("Native full-screen transitions require an interactive macOS display")
        }
        let initialFrame = fittedWindowFrame(in: screen.visibleFrame)
        let window = NSWindow(
            contentRect: initialFrame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentView = NSHostingView(
            rootView: DisplayCanvas {
                Color.accentColor
                    .frame(width: 1_280, height: 720)
            }
        )
        window.setFrame(initialFrame, display: false)
        window.makeKeyAndOrderFront(nil)
        let windowedFrame = window.frame
        defer {
            window.orderOut(nil)
            window.close()
        }

        for cycle in 1...3 {
            try await toggleFullScreen(
                window,
                awaiting: NSWindow.didEnterFullScreenNotification,
                cycle: cycle
            )
            XCTAssertTrue(window.styleMask.contains(.fullScreen))

            try await toggleFullScreen(
                window,
                awaiting: NSWindow.didExitFullScreenNotification,
                cycle: cycle
            )
            XCTAssertFalse(window.styleMask.contains(.fullScreen))
            XCTAssertEqual(window.frame.minX, windowedFrame.minX, accuracy: 2)
            XCTAssertEqual(window.frame.minY, windowedFrame.minY, accuracy: 2)
            XCTAssertEqual(window.frame.width, windowedFrame.width, accuracy: 2)
            XCTAssertEqual(window.frame.height, windowedFrame.height, accuracy: 2)
        }
    }

    private func fittedWindowFrame(in visibleFrame: NSRect) -> NSRect {
        let width = min(1_227, visibleFrame.width)
        let height = min(690, visibleFrame.height)
        return NSRect(
            x: visibleFrame.midX - width / 2,
            y: visibleFrame.midY - height / 2,
            width: width,
            height: height
        )
    }

    private func toggleFullScreen(
        _ window: NSWindow,
        awaiting notificationName: Notification.Name,
        cycle: Int
    ) async throws {
        let transition = XCTNSNotificationExpectation(
            name: notificationName,
            object: window,
            notificationCenter: .default
        )
        window.toggleFullScreen(nil)
        let result = await XCTWaiter.fulfillment(of: [transition], timeout: 10)
        XCTAssertEqual(
            result,
            .completed,
            "Full-screen transition \(notificationName.rawValue) timed out in cycle \(cycle)"
        )
    }
}
