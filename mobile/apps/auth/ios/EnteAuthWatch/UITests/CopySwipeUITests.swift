import XCTest

final class CopySwipeUITests: XCTestCase {
    func testRevealCopyToiPhone() {
        let app = XCUIApplication()
        app.launchArguments = ["-ente-screenshot", "copy"]
        app.launch()

        let cell = app.cells.matching(NSPredicate(format: "label CONTAINS %@", "GitHub")).firstMatch
        XCTAssertTrue(cell.waitForExistence(timeout: 8))

        cell.swipeLeft(velocity: .fast)
        var revealed = copyButton(in: app).waitForExistence(timeout: 2)
        if !revealed {
            let start = cell.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.45))
            let end = cell.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.45))
            start.press(forDuration: 0.01, thenDragTo: end)
            revealed = copyButton(in: app).waitForExistence(timeout: 2)
        }
        if !revealed {
            app.swipeLeft()
            revealed = copyButton(in: app).waitForExistence(timeout: 2)
        }
        XCTAssertTrue(revealed)
    }

    private func copyButton(in app: XCUIApplication) -> XCUIElement {
        app.buttons["Copy to iPhone"]
    }
}
