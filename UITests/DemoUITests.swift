import XCTest

/// アプリの試し打ち画面で実際にキーを押し、各モードの画面を撮る。
final class DemoUITests: XCTestCase {
    func testTypeAndScreenshots() {
        let app = XCUIApplication()
        app.launch()

        let ka = app.descendants(matching: .any)["key-か"].firstMatch
        XCTAssertTrue(ka.waitForExistence(timeout: 10))
        ka.tap()

        // わ を上へフリック → ん
        let wa = app.descendants(matching: .any)["key-わ"].firstMatch
        let start = wa.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -45)))

        let demo = app.descendants(matching: .any)["demo-text"].firstMatch
        XCTAssertEqual(demo.value as? String, "かん")
        XCTAssertTrue(app.buttons["candidate-0"].waitForExistence(timeout: 5))
        shot(app, "1-kana")

        app.buttons["mode"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["key-q"].waitForExistence(timeout: 5))
        shot(app, "2-qwerty")

        app.buttons["mode"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["key-1"].waitForExistence(timeout: 5))
        shot(app, "3-number")
    }

    private func shot(_ app: XCUIApplication, _ name: String) {
        let a = XCTAttachment(screenshot: app.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }
}
