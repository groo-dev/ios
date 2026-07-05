//
//  PasswordGeneratorUITests.swift
//  GrooUITests
//
//  Generator sheet from the item form: generate, options respected
//  (charset + length), copy confirmation, and Use Password flowing into a
//  saved item (verified by revealing it in the detail view — SecureField
//  values are not readable from XCUITest).
//

import XCTest

final class PasswordGeneratorUITests: XCTestCase {
    /// Flip a Toggle by accessibility identifier. SwiftUI renders the row as
    /// a wide switch element whose center is the label area, so the tap
    /// lands near the trailing edge where the actual control sits — but the
    /// flip is verified by value (run-loop wait, not a sleep), so a
    /// hit-target regression fails here instead of corrupting later asserts.
    private func flipToggle(_ app: XCUIApplication, _ identifier: String) {
        let toggle = app.switches[identifier].firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: UITest.timeout), "toggle \(identifier) not found")
        let before = (toggle.value as? String) ?? ""
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        let flipped = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value != %@", before),
            object: toggle
        )
        XCTAssertEqual(XCTWaiter().wait(for: [flipped], timeout: 5), .completed,
                       "toggle \(identifier) did not flip from \(before)")
    }

    func testGenerateOptionsCopyAndUsePassword() {
        let app = UITest.launchApp(selectedTab: "pass")
        UITest.unlockPass(app)

        // Open the form, then the generator
        app.buttons["pass.add"].tap()
        let nameField = app.textFields["pass.form.name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: UITest.timeout))
        nameField.tap()
        nameField.typeText("Generated Login")
        app.buttons["pass.form.generate"].tap()

        let valueText = app.staticTexts["passgen.value"]
        XCTAssertTrue(valueText.waitForExistence(timeout: UITest.timeout))
        let initial = valueText.label
        XCTAssertEqual(initial.count, 16, "default length is 16")

        // Regenerate produces a different password (16 random chars colliding
        // is ~2^-90 — equality means regenerate is broken)
        app.buttons["passgen.regenerate"].tap()
        XCTAssertNotEqual(valueText.label, initial)

        // Options respected: switch off everything but numbers, addressed by
        // identifier (Phase 6 fast-follow — no more label-text coupling)
        flipToggle(app, "passgen.toggle.uppercase")
        flipToggle(app, "passgen.toggle.lowercase")
        flipToggle(app, "passgen.toggle.symbols")
        let numericOnly = valueText.label
        XCTAssertTrue(numericOnly.allSatisfy(\.isNumber), "numbers-only charset violated: \(numericOnly)")

        // Length respected: slider to max, then compare against the displayed count
        app.sliders["passgen.length"].adjust(toNormalizedSliderPosition: 1.0)
        let displayedLength = Int(app.staticTexts["passgen.length.value"].label) ?? -1
        XCTAssertGreaterThan(displayedLength, 16, "slider at max must exceed the default")
        XCTAssertEqual(valueText.label.count, displayedLength, "generated length must match the length control")

        // Copy shows its confirmation (label flip, not pasteboard — see plan notes)
        let copyButton = app.buttons["passgen.copy"]
        copyButton.tap()
        XCTAssertTrue(UITest.waitForLabel(copyButton, equals: "Copied!"), "copy must confirm")

        // Use Password → back on the form → save → reveal in detail
        let finalPassword = valueText.label
        app.buttons["passgen.use"].tap()
        XCTAssertTrue(nameField.waitForExistence(timeout: UITest.timeout))
        app.buttons["Save"].tap()
        let row = app.staticTexts["Generated Login"]
        XCTAssertTrue(row.waitForExistence(timeout: UITest.timeout))
        row.tap()
        let reveal = app.buttons["pass.detail.showPassword"]
        XCTAssertTrue(reveal.waitForExistence(timeout: UITest.timeout))
        reveal.tap()
        XCTAssertTrue(app.staticTexts[finalPassword].waitForExistence(timeout: UITest.timeout),
                      "detail must reveal exactly the generated password")
    }
}
