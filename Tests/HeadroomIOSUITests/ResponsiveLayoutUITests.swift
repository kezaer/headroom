import XCTest

@MainActor
final class ResponsiveLayoutUITests: XCTestCase {
    func testCompactCardsShareLeadingTitleGuide() {
        let app = XCUIApplication()
        app.launchArguments = ["--demo"]
        app.launch()

        let window = app.windows.firstMatch
        guard window.frame.width < 700 else { return }

        let claudeTitle = app.staticTexts["Claude"].firstMatch
        let anthropicTitle = app.staticTexts["Anthropic API"].firstMatch
        let openAITitle = app.staticTexts["OpenAI API"].firstMatch
        XCTAssertTrue(claudeTitle.waitForExistence(timeout: 5))
        XCTAssertTrue(anthropicTitle.exists)
        XCTAssertTrue(openAITitle.exists)
        XCTAssertEqual(anthropicTitle.frame.minX, claudeTitle.frame.minX, accuracy: 1)
        XCTAssertEqual(openAITitle.frame.minX, claudeTitle.frame.minX, accuracy: 1)
    }

    func testDemoContentFitsCurrentPhoneOrTabletWindow() {
        let app = XCUIApplication()
        app.launchArguments = ["--demo"]
        app.launch()

        let window = app.windows.firstMatch
        let isTablet = window.frame.width >= 700
        defer { XCUIDevice.shared.orientation = .portrait }
        let claude = app.descendants(matching: .any)["headroom.provider.claude"]
        let codex = app.descendants(matching: .any)["headroom.provider.codex"]
        XCTAssertTrue(claude.waitForExistence(timeout: 5))
        XCTAssertTrue(codex.exists)
        XCTAssertTrue(window.frame.contains(claude.frame))
        XCTAssertTrue(window.frame.contains(codex.frame))

        if isTablet {
            XCTAssertLessThan(abs(claude.frame.midY - codex.frame.midY), 80)
            XCTAssertGreaterThan(codex.frame.minX, claude.frame.minX)
        } else {
            XCTAssertGreaterThan(codex.frame.minY, claude.frame.minY)
        }

        XCTAssertTrue(app.buttons["headroom.settings"].isHittable)

        if isTablet {
            XCUIDevice.shared.orientation = .landscapeLeft
            let rotated = XCTNSPredicateExpectation(
                predicate: NSPredicate { _, _ in window.frame.width > window.frame.height },
                object: nil
            )
            XCTAssertEqual(XCTWaiter.wait(for: [rotated], timeout: 5), .completed)
            XCTAssertTrue(window.frame.contains(claude.frame))
            XCTAssertTrue(window.frame.contains(codex.frame))
            XCTAssertLessThan(abs(claude.frame.midY - codex.frame.midY), 80)
            XCTAssertTrue(app.buttons["headroom.settings"].isHittable)
        }
    }
}
