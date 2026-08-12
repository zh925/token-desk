import CoreGraphics
import ImageIO
import XCTest

@MainActor
final class TokenDeskAcceptanceUITests: XCTestCase {
    func testPRD22PrimaryWorkflowAndScreenshotBaselines() throws {
        let application = launchApplication()
        let canvas = application.descendants(matching: .any)["app-shell-canvas"]

        XCTAssertTrue(canvas.waitForExistence(timeout: 3))
        XCTAssertEqual(canvas.frame.width, 1_280, accuracy: 1)
        XCTAssertEqual(canvas.frame.height, 720, accuracy: 1)
        XCTAssertTrue(application.descendants(matching: .any)["page-overview"].exists)
        XCTAssertTrue(application.staticTexts["31°"].exists)
        XCTAssertTrue(application.staticTexts["晴朗 · 体感 34°"].exists)
        XCTAssertTrue(application.staticTexts["降雨 10% · 湿度 63%"].exists)
        XCTAssertTrue(application.descendants(matching: .any)["overview-primary-plan"].exists)
        XCTAssertTrue(application.descendants(matching: .any)["overview-provider-openai"].exists)
        XCTAssertTrue(application.descendants(matching: .any)["overview-provider-deepseek"].exists)
        try assertScreenshotBaseline(application, named: "Overview")

        application.buttons["route-plans"].click()
        XCTAssertTrue(
            application.descendants(matching: .any)["page-plans"].waitForExistence(timeout: 1))
        for planID in ["codex-primary", "codex-week", "anthropic"] {
            XCTAssertTrue(application.descendants(matching: .any)["plan-window-\(planID)"].exists)
        }
        XCTAssertTrue(
            application.descendants(matching: .any)["plan-window-codex-primary"].label.contains(
                "0%")
        )
        XCTAssertTrue(
            application.descendants(matching: .any)["plan-window-codex-week"].label.contains("100%")
        )
        XCTAssertFalse(application.buttons["add-provider-button"].exists)
        try assertScreenshotBaseline(application, named: "Plans")

        application.buttons["route-tokens"].click()
        XCTAssertTrue(
            application.descendants(matching: .any)["page-tokens"].waitForExistence(timeout: 1))
        XCTAssertTrue(
            application.descendants(matching: .any)["token-input-metric"].label.contains("3.88M")
        )
        application.buttons["token-range-day"].click()
        XCTAssertTrue(
            application.descendants(matching: .any)["token-input-metric"].label.contains("432.0K")
        )
        application.buttons["token-range-month"].click()
        XCTAssertTrue(
            application.descendants(matching: .any)["token-input-metric"].label.contains("16.63M")
        )
        XCTAssertTrue(application.descendants(matching: .any)["token-cost-metric"].exists)
        XCTAssertTrue(application.descendants(matching: .any)["token-balance-metric"].exists)
        XCTAssertFalse(application.buttons["add-provider-button"].exists)
        application.buttons["token-range-week"].click()
        try assertScreenshotBaseline(application, named: "Tokens")

        application.buttons["settings-button"].click()
        XCTAssertTrue(
            application.descendants(matching: .any)["page-settings"].waitForExistence(timeout: 1))
        XCTAssertEqual(application.buttons.matching(identifier: "settings-button").count, 1)
        application.buttons["settings-section-appReview"].click()
        XCTAssertTrue(application.staticTexts["演示模式已启用"].exists)
        try assertScreenshotBaseline(application, named: "Settings")
        assertSettingsAcceptance(application)
    }

    func testVoiceOverSemanticsAndAccessibilityAuditsAllPages() throws {
        let application = launchApplication()
        let auditTypes: XCUIAccessibilityAuditType = [.action, .hitRegion]

        let routes = [
            ("route-overview", "page-overview", "总览页面"),
            ("route-plans", "page-plans", "套餐页面"),
            ("route-tokens", "page-tokens", "Token页面"),
            ("settings-button", "page-settings", "设置页面"),
        ]
        for (routeID, pageID, expectedLabel) in routes {
            application.buttons[routeID].click()
            XCTAssertEqual(
                application.descendants(matching: .any)[pageID].label,
                expectedLabel
            )
            try application.performAccessibilityAudit(for: auditTypes)
        }

        application.buttons["route-tokens"].click()
        XCTAssertGreaterThan(
            elements(application, withLabelContaining: "Token 使用趋势图，").count,
            0
        )
        for button in application.buttons.allElementsBoundByIndex where button.isHittable {
            XCTAssertFalse(button.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    func testKeyboardNavigationCoversPrimaryRoutesAndSettings() {
        let application = launchApplication()

        application.typeKey("2", modifierFlags: [])
        XCTAssertTrue(
            application.descendants(matching: .any)["page-plans"].waitForExistence(timeout: 1)
        )
        application.typeKey("3", modifierFlags: [])
        XCTAssertTrue(
            application.descendants(matching: .any)["page-tokens"].waitForExistence(timeout: 1)
        )
        application.typeKey("1", modifierFlags: [])
        XCTAssertTrue(
            application.descendants(matching: .any)["page-overview"].waitForExistence(timeout: 1)
        )

        application.buttons["settings-button"].click()
        XCTAssertTrue(
            application.descendants(matching: .any)["page-settings"].waitForExistence(timeout: 1)
        )
    }

    func testReduceMotionOverridePropagatesAndLeavesNoTransitioningFrame() throws {
        let application = launchApplication(reduceMotion: true)
        XCTAssertTrue(
            application.descendants(matching: .any)["ui-test-reduce-motion-enabled"]
                .waitForExistence(timeout: 2)
        )

        application.buttons["route-plans"].click()
        let canvas = application.descendants(matching: .any)["app-shell-canvas"]
        let first = try normalizedLuma(canvas.screenshot().pngRepresentation)
        Thread.sleep(forTimeInterval: 0.15)
        let settled = try normalizedLuma(canvas.screenshot().pngRepresentation)
        XCTAssertLessThanOrEqual(
            meanAbsoluteDifference(first, settled),
            0.002,
            "Reduce Motion should not leave an animated transition after navigation"
        )
    }

    private func launchApplication(reduceMotion: Bool = false) -> XCUIApplication {
        let application = XCUIApplication()
        application.launchArguments = [
            "-ApplePersistenceIgnoreState",
            "YES",
            "-NSQuitAlwaysKeepsWindows",
            "NO",
            "--ui-testing",
            "--ui-test-fixed-clock",
            "--app-review-demo",
        ]
        if reduceMotion {
            application.launchArguments.append("--ui-test-reduce-motion")
        }
        application.launch()
        addTeardownBlock { application.terminate() }
        XCTAssertTrue(application.staticTexts["Token Desk"].waitForExistence(timeout: 3))
        return application
    }

    private func assertSettingsAcceptance(_ application: XCUIApplication) {
        let sections = [
            "appReview", "providers", "weather", "display", "notifications", "dataExport",
        ]
        for section in sections {
            XCTAssertTrue(application.buttons["settings-section-\(section)"].exists)
        }

        application.buttons["settings-section-providers"].click()
        XCTAssertTrue(application.buttons["add-provider-button"].exists)
        application.buttons["settings-section-weather"].click()
        XCTAssertTrue(application.textFields["manual-city-field"].exists)
        application.buttons["settings-section-display"].click()
        XCTAssertTrue(application.descendants(matching: .any)["target-display-picker"].exists)
        XCTAssertTrue(application.checkBoxes["launch-at-login-toggle"].exists)
        application.buttons["settings-section-notifications"].click()
        XCTAssertTrue(application.checkBoxes["alerts-toggle"].exists)
        application.buttons["settings-section-dataExport"].click()
        XCTAssertTrue(application.buttons["export-history-button"].exists)
        XCTAssertTrue(
            application.staticTexts[
                "仅写入系统保存面板中选定的文件；不导出密钥、Prompt 或响应正文。"
            ].exists
        )
    }

    private func elements(
        _ application: XCUIApplication,
        withLabelContaining value: String
    ) -> XCUIElementQuery {
        application.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS %@", value)
        )
    }

    private func assertScreenshotBaseline(
        _ application: XCUIApplication,
        named name: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let canvas = application.descendants(matching: .any)["app-shell-canvas"]
        let screenshot = canvas.screenshot()
        let currentData = screenshot.pngRepresentation
        let currentAttachment = XCTAttachment(
            data: currentData, uniformTypeIdentifier: "public.png")
        currentAttachment.name = "TokenDesk-\(name)-1280x720-current"
        currentAttachment.lifetime = .keepAlways
        add(currentAttachment)

        let baselineURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Baselines/\(name).png")
        guard let baselineData = try? Data(contentsOf: baselineURL) else {
            XCTFail(
                "Missing screenshot baseline at TokenDeskUITests/Baselines/\(name).png", file: file,
                line: line)
            return
        }
        let current = try normalizedLuma(currentData)
        let baseline = try normalizedLuma(baselineData)
        let meanDifference = meanAbsoluteDifference(current, baseline)
        let materiallyChanged = changedPixelFraction(current, baseline, threshold: 0.12)
        if meanDifference > 0.035 || materiallyChanged > 0.20 {
            let baselineAttachment = XCTAttachment(
                data: baselineData,
                uniformTypeIdentifier: "public.png"
            )
            baselineAttachment.name = "TokenDesk-\(name)-1280x720-baseline"
            baselineAttachment.lifetime = .keepAlways
            add(baselineAttachment)
        }
        XCTAssertLessThanOrEqual(
            meanDifference,
            0.035,
            "\(name) mean screenshot delta \(meanDifference) exceeds 3.5%",
            file: file,
            line: line
        )
        XCTAssertLessThanOrEqual(
            materiallyChanged,
            0.20,
            "\(name) changed-pixel share \(materiallyChanged) exceeds 20%",
            file: file,
            line: line
        )
    }

    private func normalizedLuma(_ data: Data) throws -> [Double] {
        let source = CGImageSourceCreateWithData(data as CFData, nil)
        guard let source, let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw ScreenshotError.invalidPNG
        }
        let width = 160
        let height = 90
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard
            let context = CGContext(
                data: &pixels,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else {
            throw ScreenshotError.cannotCreateContext
        }
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return stride(from: 0, to: pixels.count, by: 4).map { index in
            let red = Double(pixels[index])
            let green = Double(pixels[index + 1])
            let blue = Double(pixels[index + 2])
            return (0.2126 * red + 0.7152 * green + 0.0722 * blue) / 255
        }
    }

    private func meanAbsoluteDifference(_ lhs: [Double], _ rhs: [Double]) -> Double {
        guard lhs.count == rhs.count, !lhs.isEmpty else { return 1 }
        let total = zip(lhs, rhs).reduce(0.0) { result, pair in
            result + abs(pair.0 - pair.1)
        }
        return total / Double(lhs.count)
    }

    private func changedPixelFraction(
        _ lhs: [Double],
        _ rhs: [Double],
        threshold: Double
    ) -> Double {
        guard lhs.count == rhs.count, !lhs.isEmpty else { return 1 }
        let changed = zip(lhs, rhs).reduce(0) { result, pair in
            result + (abs(pair.0 - pair.1) > threshold ? 1 : 0)
        }
        return Double(changed) / Double(lhs.count)
    }
}

private enum ScreenshotError: Error {
    case invalidPNG
    case cannotCreateContext
}
