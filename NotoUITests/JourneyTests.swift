import XCTest

final class JourneyTests: XCTestCase {
    @MainActor private func capture(_ name: String, app: XCUIApplication) {
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = name
        image.lifetime = .keepAlways
        add(image)
    }

    @MainActor func testPastDatedProofreadingSurvivesRelaunch() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-noto-fixture","-cloud","YES","-spell","NO"]
        app.launch()
        let title = "Field notes " + UUID().uuidString.prefix(6)
        app.buttons["New note"].tap()
        app.buttons["noteDate"].tap()
        let shortcut = app.buttons["10 days ago"]
        if !shortcut.isHittable { app.swipeUp() }
        shortcut.tap()
        XCTAssertTrue(shortcut.waitForNonExistence(timeout: 5))
        let selectedDay = app.buttons["noteDate"].label
        let expected = Calendar(identifier: .gregorian).date(byAdding: .day, value: -10, to: .now)!
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        XCTAssertTrue(selectedDay.contains(formatter.string(from: expected)))
        let titleField = app.descendants(matching: .any).matching(identifier: "title").firstMatch
        titleField.tap()
        titleField.typeText(String(title))
        app.textViews["body"].tap()
        app.textViews["body"].typeText("Yesterday I goes home.")
        app.buttons["Hide keyboard"].tap()
        app.buttons["Writing assistant"].tap()
        app.buttons["Proofread Note"].tap()
        XCTAssertTrue(app.buttons["Dismiss"].waitForExistence(timeout:20))
        app.buttons["Dismiss"].tap()
        XCTAssertEqual(app.textViews["body"].value as? String,"Yesterday I goes home.")
        app.buttons["Writing assistant"].tap()
        app.buttons["Proofread Note"].tap()
        XCTAssertTrue(app.buttons["Accept"].waitForExistence(timeout:20))
        capture("Review on iPhone", app: app)
        app.buttons["Accept"].tap()
        XCTAssertEqual(app.textViews["body"].value as? String,"Yesterday I went home.")
        app.buttons["Formatting"].tap()
        app.buttons["Undo"].tap()
        XCTAssertEqual(app.textViews["body"].value as? String,"Yesterday I goes home.")
        app.buttons["Formatting"].tap()
        app.buttons["Redo"].tap()
        XCTAssertEqual(app.textViews["body"].value as? String,"Yesterday I went home.")
        func created() -> String {
            app.buttons["Note options"].tap()
            app.buttons["Note information"].tap()
            let value = app.descendants(matching:.any).matching(identifier:"created").firstMatch
            XCTAssertTrue(value.waitForExistence(timeout:5))
            let stamp = value.label + String(describing:value.value)
            app.buttons["Done"].tap()
            return stamp
        }
        let stamp = created()
        app.terminate()
        app.launch()
        let entry = app.descendants(matching: .any).matching(identifier: "entry-" + String(title)).firstMatch
        XCTAssertTrue(entry.waitForExistence(timeout:5))
        entry.tap()
        XCTAssertEqual(app.buttons["noteDate"].label,selectedDay)
        XCTAssertEqual(app.textViews["body"].value as? String,"Yesterday I went home.")
        XCTAssertEqual(created(),stamp)
        app.navigationBars.buttons.element(boundBy:0).tap()
        app.buttons["Timeline"].tap()
        XCTAssertTrue(entry.exists)
        capture("Timeline", app: app)
        app.buttons["Calendar"].tap()
        app.buttons["calendarDay"].tap()
        if !shortcut.isHittable { app.swipeUp() }
        shortcut.tap()
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        capture("Calendar", app: app)
    }
    @MainActor func testLargeTypeDarkEditor() {
        let app = XCUIApplication()
        app.launchArguments = ["-appearance","Dark","-UIPreferredContentSizeCategoryName","UICTContentSizeCategoryAccessibilityL","-AppleLanguages","(fa)"]
        app.launch()
        app.buttons["New note"].tap()
        XCTAssertTrue(app.textViews["body"].isHittable)
        XCTAssertTrue(app.buttons["Writing assistant"].isHittable)
        _ = app.buttons["New note"].waitForNonExistence(timeout: 2)
        let shot = XCTAttachment(screenshot:app.screenshot())
        shot.name = "Large type dark editor"
        shot.lifetime = .keepAlways
        add(shot)
    }
}
