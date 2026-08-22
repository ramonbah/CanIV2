//
//  ReadmeScreenshotCaptureTests.swift
//  CanIV2UITests
//
//  Created for deterministic README screenshot capture.
//

import XCTest

final class ReadmeScreenshotCaptureTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    @MainActor
    func testCaptureReadmeScreenshots() throws {
        let outputDirectory = ProcessInfo.processInfo.environment["README_SCREENSHOT_OUTPUT_DIR"]
            ?? "/Users/ramonjrbahio/Documents/CanIV2/docs/screenshots"
        try FileManager.default.createDirectory(atPath: outputDirectory, withIntermediateDirectories: true)

        let app = launchApp(selectedTab: "home")
        XCTAssertTrue(app.navigationBars["Home"].waitForExistence(timeout: 10), app.debugDescription)
        capture("home.png", outputDirectory: outputDirectory)

        app.tabBars.buttons["Budgets"].tap()
        let augustPlan = app.buttons["plan-row-August Essentials"]
        XCTAssertTrue(augustPlan.waitForExistence(timeout: 10), app.debugDescription)
        augustPlan.tap()
        XCTAssertTrue(app.navigationBars["August Essentials"].waitForExistence(timeout: 10), app.debugDescription)
        capture("plan-items.png", outputDirectory: outputDirectory)

        app.tabBars.buttons["Transactions"].tap()
        XCTAssertTrue(app.textFields["transactions-search"].waitForExistence(timeout: 10), app.debugDescription)
        app.textFields["transactions-search"].tap()
        app.textFields["transactions-search"].typeText("Hotel")
        app.keyboards.buttons["search"].tap()
        app.buttons["Filters"].tap()
        tapSwitch(containing: "Household Budget", in: app)
        tapSwitch(containing: "August Essentials", in: app)
        tapSwitch(containing: "Hotel Balance", in: app)
        capture("transactions.png", outputDirectory: outputDirectory)

        app.tabBars.buttons["Budgets"].tap()
        XCTAssertTrue(app.navigationBars["August Essentials"].waitForExistence(timeout: 10), app.debugDescription)
        app.swipeUp()
        let reportsButton = app.buttons["plan-reports-button"]
        XCTAssertTrue(reportsButton.waitForExistence(timeout: 10), app.debugDescription)
        reportsButton.tap()
        XCTAssertTrue(app.navigationBars["Plan Reports"].waitForExistence(timeout: 10), app.debugDescription)
        capture("reports.png", outputDirectory: outputDirectory)

        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.staticTexts["Hidden"].waitForExistence(timeout: 10), app.debugDescription)
        app.buttons["Effort Calculator"].tap()
        XCTAssertTrue(app.navigationBars["Effort Calculator"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.staticTexts["time-effort-result"].waitForExistence(timeout: 10), app.debugDescription)
        capture("time-effort.png", outputDirectory: outputDirectory)
    }

    private func launchApp(selectedTab: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["UI_TESTING"] = "1"
        app.launchEnvironment["UI_TESTING_CURRENCY_CODE"] = "MYR"
        app.launchEnvironment["UI_TESTING_SEED_README_SCREENSHOTS"] = "1"
        app.launchEnvironment["UI_TESTING_TIME_EFFORT_AMOUNT"] = "120"
        app.launchArguments = [
            "-phase2.onboardingComplete", "YES",
            "-phase2.selectedTab", selectedTab,
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_MY",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryM"
        ]
        app.launch()
        return app
    }

    private func capture(_ fileName: String, outputDirectory: String) {
        let url = URL(fileURLWithPath: outputDirectory).appendingPathComponent(fileName)
        let data = XCUIScreen.main.screenshot().pngRepresentation
        XCTAssertTrue(FileManager.default.createFile(atPath: url.path, contents: data), "Failed to write \(url.path)")
    }

    private func tapSwitch(containing label: String, in app: XCUIApplication) {
        let element = app.switches.matching(NSPredicate(format: "label CONTAINS %@", label)).firstMatch
        for _ in 0..<6 {
            if element.waitForExistence(timeout: 0.5) {
                element.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
                return
            }
            app.swipeUp()
        }
        XCTAssertTrue(element.waitForExistence(timeout: 1), app.debugDescription)
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
    }

}
