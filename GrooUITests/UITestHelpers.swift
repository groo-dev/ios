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

    /// Fresh, hermetic app instance. `selectedTab` and `phoneTabBar` seed
    /// launch-time UserDefaults so the app opens directly on that tab with
    /// that bar configuration, no navigation needed. `phoneTabBar` takes the
    /// JSON TabConfigurationStore persists,
    /// e.g. `{"order":["azan","pass","pad","stocks","crypto","drive","scratchpad"],"showsHome":true}`.
    ///
    /// `selectedTab` seeds BOTH persistence keys: `selectedTab` (AppRouter's
    /// pad selection) and `phoneSelectedTab` (its phone selection). The two are
    /// deliberately separate keys — see AppRouter — and UI tests run on iPhone,
    /// so seeding only the pad key would silently do nothing. Phone-only values
    /// like "more" are simply not parsed by the pad key's TabID(rawValue:).
    /// Both ride the ordinary NSArgumentDomain UserDefaults override (`-key
    /// value`), which works fine here because "home"/"more"/etc. never start
    /// with "{".
    ///
    /// `phoneTabBar` CANNOT use that same NSArgumentDomain override — its
    /// value is a JSON object, and Foundation treats any command-line value
    /// starting with "{" as an attempt at old-style property-list syntax.
    /// JSON isn't that syntax, so the parse fails and Foundation drops the
    /// argument entirely (not even a raw string survives). UITestMode.swift
    /// works around this by parsing `-phoneTabBar` out of argv by hand and
    /// writing it straight into UserDefaults, bypassing the NSArgumentDomain
    /// heuristic — see `UITestMode.seedPhoneTabBarIfProvided()`.
    static func launchApp(selectedTab: String? = nil, phoneTabBar: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--uitest"]
        if let selectedTab {
            app.launchArguments += ["-selectedTab", selectedTab,
                                    "-phoneSelectedTab", selectedTab]
        }
        if let phoneTabBar {
            app.launchArguments += ["-phoneTabBar", phoneTabBar]
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
        // `pass.menu` is the unlocked list's own toolbar affordance — `pass.add`
        // now lives inside that menu and does not exist until it is opened.
        XCTAssertTrue(app.buttons["pass.menu"].waitForExistence(timeout: timeout), "vault did not unlock into the item list", file: file, line: line)
    }

    /// Open the "Add Item" form. Add moved out of the toolbar and under the
    /// vault's overflow menu, so reaching it is two taps — keep that detail
    /// here rather than in every test that creates an item.
    static func openAddItem(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        app.buttons["pass.menu"].tap()
        let add = app.buttons["pass.add"]
        XCTAssertTrue(add.waitForExistence(timeout: timeout), "Add Item missing from the vault menu", file: file, line: line)
        add.tap()
    }

    /// Select a tab by title, falling back to the app-owned More screen.
    /// Unlike the old system overflow (a UIKit table), More is a SwiftUI List,
    /// so its rows are buttons carrying `more.row.<rawValue>` identifiers.
    ///
    /// Dismisses a stray keyboard first (see `dismissKeyboardIfPresent`):
    /// screens like PadUnlockView auto-focus a password field on appear
    /// whenever biometric unlock isn't available — which under `--uitest`
    /// (the fake keychain starts empty) is every single launch — and the
    /// system keyboard then sits directly on top of the tab bar in z-order,
    /// exactly as it would in any other tabbed iOS app. That's expected
    /// platform behavior, not a bug: a real user hits the same thing and
    /// would dismiss the keyboard before reaching the tab bar too.
    static func openTab(_ app: XCUIApplication, _ title: String, file: StaticString = #filePath, line: UInt = #line) {
        dismissKeyboardIfPresent(app)

        let direct = app.tabBars.buttons[title]
        if direct.exists {
            direct.tap()
            return
        }
        let more = app.tabBars.buttons["More"]
        if more.exists {
            more.tap()
            var entry = app.buttons["more.row.\(identifier(for: title))"].firstMatch
            if !entry.waitForExistence(timeout: 2) {
                // More's NavigationStack persists across tab switches — the
                // same default behavior as Settings.app or the App Store: if
                // an earlier visit drilled into a row (e.g. Wallet), a later
                // direct tab-bar tap on More restores that same pushed screen
                // rather than the row list, because it never went through
                // AppRouter.open(_:) (the only path that resets morePath) —
                // a raw tab-bar tap just flips TabView's selection binding.
                // Tapping the already-selected "More" tab again is the
                // standard iOS gesture that pops it to root; not a retry of
                // the same lookup, but a different, deliberate action taken
                // because the first one told us we're on the wrong screen.
                more.tap()
                entry = app.buttons["more.row.\(identifier(for: title))"].firstMatch
            }
            if entry.waitForExistence(timeout: timeout) {
                entry.tap()
                return
            }
        }
        XCTFail("Tab \(title) not reachable from the tab bar:\n\(app.tabBars.firstMatch.debugDescription)", file: file, line: line)
    }

    /// If a screen left a keyboard on screen, dismiss it before touching the
    /// tab bar: the keyboard is a full-width view docked at the bottom of the
    /// window, above the tab bar in z-order, and it swallows taps aimed at
    /// whatever it covers — XCTest reports those as an unhittable {-1, -1}
    /// point rather than tapping through to the element underneath. A no-op
    /// when no keyboard is up, so this is safe to call unconditionally.
    ///
    /// Every screen that can trigger this wires `.scrollDismissesKeyboard(.interactively)`,
    /// so a drag gesture over the content — not a tap, which that modifier's
    /// `.interactively` mode ignores — is the same lever a real user has.
    /// Dragging within the middle band of the screen keeps clear of the
    /// status bar/Dynamic Island at the very top (an accidental swipe there
    /// can open Control Center/Notification Center in the simulator) and of
    /// the keyboard itself at the bottom.
    private static func dismissKeyboardIfPresent(_ app: XCUIApplication) {
        guard app.keyboards.firstMatch.exists else { return }
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
        start.press(forDuration: 0.05, thenDragTo: end)
        let goneAway = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: app.keyboards.firstMatch
        )
        _ = XCTWaiter().wait(for: [goneAway], timeout: timeout)
    }

    /// Map a tab's display title to its TabID raw value.
    /// Mirrors TabID.title in Groo/Views/MainTabView.swift — keep in sync.
    private static func identifier(for title: String) -> String {
        switch title {
        case "Home": "home"
        case "Stocks": "stocks"
        case "Wallet": "crypto"
        case "Azan": "azan"
        case "Pad": "pad"
        case "Pass": "pass"
        case "Drive": "drive"
        case "Scratchpad": "scratchpad"
        case "Settings": "settings"
        default: title.lowercased()
        }
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
    /// Dismiss the system "Save this password?" sheet.
    ///
    /// It belongs to Springboard, not to the app, so `app.buttons` never
    /// matches it — the query has to go to the springboard process. Scoping it
    /// to the app looked like it worked only because the sheet used to appear
    /// after the assertions that cared; a save that takes a different amount of
    /// time is enough to leave it sitting over the next tap.
    static func dismissSavePasswordPromptIfPresent(_ app: XCUIApplication, timeout: TimeInterval = 3) {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for candidate in [springboard.buttons["Not Now"], app.buttons["Not Now"]]
        where candidate.waitForExistence(timeout: timeout) {
            candidate.tap()
            return
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
