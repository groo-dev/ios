//
//  UITestHelpers.swift
//  GrooUITests
//
//  Shared launch + flow helpers. Every test launches a fresh app process with
//  --uitest (hermetic storage and stubs; see Groo/Core/UITestMode.swift).
//  No sleeps anywhere: waitForExistence + one predicate-expectation helper.
//

import XCTest

enum UITest {
    /// Must match UITestMode.masterPassword in the app target.
    static let masterPassword = "uitest-master-1"
    static let timeout: TimeInterval = 15

    /// Fresh, hermetic app instance. `selectedTab` uses the NSArgumentDomain
    /// UserDefaults override for @AppStorage("selectedTab") — the app opens
    /// directly on that tab, no tab-bar navigation needed.
    static func launchApp(selectedTab: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--uitest"]
        if let selectedTab {
            app.launchArguments += ["-selectedTab", selectedTab]
        }
        app.launch()
        return app
    }

    /// Unlock the Pass vault with the stub master password. Precondition:
    /// PassUnlockView is on screen (launch with selectedTab: "pass").
    static func unlockPass(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let field = app.secureTextFields["pass.unlock.password"]
        XCTAssertTrue(field.waitForExistence(timeout: timeout), "Pass unlock password field never appeared", file: file, line: line)
        field.tap()
        field.typeText(masterPassword)
        app.buttons["pass.unlock.submit"].tap()
        XCTAssertTrue(app.buttons["pass.add"].waitForExistence(timeout: timeout), "vault did not unlock into the item list", file: file, line: line)
    }

    /// Select a tab by title, falling back to the tab bar's "More" overflow
    /// (9 tabs may not all fit on an iPhone tab bar).
    static func openTab(_ app: XCUIApplication, _ title: String, file: StaticString = #filePath, line: UInt = #line) {
        let direct = app.tabBars.buttons[title]
        if direct.exists {
            direct.tap()
            return
        }
        let more = app.tabBars.buttons["More"]
        if more.exists {
            more.tap()
            let entry = app.buttons[title].firstMatch
            if entry.waitForExistence(timeout: timeout) {
                entry.tap()
                return
            }
        }
        XCTFail("Tab \(title) not reachable from the tab bar", file: file, line: line)
    }

    /// Dismiss a system permission alert (e.g. location on the Azan tab) if
    /// one appears. waitForExistence keeps this sleep-free; if no alert shows
    /// within `timeout`, this is a no-op.
    static func dismissSystemAlertIfPresent(timeout: TimeInterval = 3) {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let alert = springboard.alerts.firstMatch
        guard alert.waitForExistence(timeout: timeout) else { return }
        for label in ["Don’t Allow", "Don't Allow", "Allow Once", "OK"] {
            let button = alert.buttons[label]
            if button.exists {
                button.tap()
                return
            }
        }
    }

    /// Wait (run-loop, not sleep) for an element attribute change that can't
    /// be expressed as existence — e.g. a button label flipping to "Copied!".
    static func waitForLabel(_ element: XCUIElement, equals expected: String, timeout: TimeInterval = 5) -> Bool {
        let predicate = NSPredicate(format: "label == %@", expected)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }

    /// iOS's system "Save Password" prompt ("Save Password?" / "Not Now" / "Save")
    /// can appear after submitting a form containing a username + password field
    /// (textContentType(.username)/.password), and renders inside the app's own
    /// window hierarchy — obscuring every other element until dismissed. Not
    /// every save triggers it (simulator heuristics vary), so this is a no-op
    /// when it doesn't appear within `timeout`.
    static func dismissSavePasswordPromptIfPresent(_ app: XCUIApplication, timeout: TimeInterval = 3) {
        let notNow = app.buttons["Not Now"]
        if notNow.waitForExistence(timeout: timeout) {
            notNow.tap()
        }
    }
}

extension XCUIElement {
    /// Replace a text field's current value. Taps near the trailing edge so
    /// the caret lands at the end, then deletes backwards before typing.
    func clearAndTypeText(_ text: String) {
        coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        let current = (value as? String) ?? ""
        if !current.isEmpty {
            typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count + 5))
        }
        typeText(text)
    }
}
