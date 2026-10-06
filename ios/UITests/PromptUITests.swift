import XCTest

/// Opens the prompt through doorway://gate/signal, types a reason and checks "Open Signal" enables at exactly the
/// required word count (read from the "0 / 5 words" label, so it works whatever is already logged today).
final class PromptUITests: XCTestCase {
    func testOpenEnablesAfterEnoughWords() throws {
        let app = XCUIApplication()
        app.launch()
        app.open(URL(string: "doorway://gate/signal")!)

        XCTAssertTrue(app.staticTexts["Why open Signal?"].waitForExistence(timeout: 10))
        let counter = app.staticTexts["words"]
        XCTAssertTrue(counter.waitForExistence(timeout: 5))
        let required = try XCTUnwrap(Int(counter.label.split(separator: " ")[2]))
        let open = app.buttons["open"]
        XCTAssertFalse(open.isEnabled)

        let reason = app.textViews["reason"].exists ? app.textViews["reason"] : app.textFields["reason"]
        reason.tap()
        reason.typeText(Array(repeating: "word", count: required - 1).joined(separator: " "))
        XCTAssertFalse(open.isEnabled, "one word short")
        reason.typeText(" last")
        XCTAssertTrue(open.isEnabled, "enough words")
    }
}
