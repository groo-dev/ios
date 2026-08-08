//
//  TabNavigationUITests.swift
//  GrooUITests
//
//  Every tab renders its known marker without crashing, reached either from
//  the tab bar or the app-owned More screen. First Azan visit may pop the
//  system location alert — dismissed via springboard, sleep-free.
//

import XCTest

final class TabNavigationUITests: XCTestCase {
    func testEveryTabRendersWithoutCrashing() {
        let app = UITest.launchApp(selectedTab: "home")
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: UITest.timeout))

        let visits: [(tab: String, marker: XCUIElement)] = [
            ("Stocks", app.staticTexts["Stock Portfolio"]),          // empty-portfolio onboarding
            ("Wallet", app.staticTexts["Ethereum Wallet"]),          // wallet onboarding
            ("Azan", app.navigationBars.staticTexts["Azan"]),        // principal toolbar title
            ("Pad", app.staticTexts["Pad is Locked"]),
            ("Pass", app.staticTexts["Pass is Locked"]),
            ("Drive", app.staticTexts["Coming Soon"]),
            ("Scratchpad", app.staticTexts["Scratchpad Locked"]),
            // The app owns More now, so SwiftUI's .navigationTitle survives —
            // the old workaround of matching a row label is no longer needed.
            ("Settings", app.navigationBars.staticTexts["Settings"]),
        ]

        for (tab, marker) in visits {
            UITest.openTab(app, tab)
            if tab == "Azan" {
                UITest.dismissSystemAlertIfPresent()
            }
            XCTAssertTrue(marker.waitForExistence(timeout: UITest.timeout), "\(tab) tab did not render its marker")
            XCTAssertEqual(app.state, .runningForeground, "\(tab) tab crashed the app")
        }

        // And back to Home (empty-state stocks card)
        UITest.openTab(app, "Home")
        XCTAssertTrue(app.staticTexts["Add your first stock"].waitForExistence(timeout: UITest.timeout))
        XCTAssertEqual(app.state, .runningForeground)
    }

    func testDefaultConfigurationPutsHomeAzanPassPadInTheBar() {
        let app = UITest.launchApp(selectedTab: "home")
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: UITest.timeout))

        for title in ["Home", "Azan", "Pass", "Pad", "More"] {
            XCTAssertTrue(app.tabBars.buttons[title].exists, "\(title) missing from the tab bar")
        }
        for title in ["Stocks", "Wallet", "Drive", "Scratchpad", "Settings"] {
            XCTAssertFalse(app.tabBars.buttons[title].exists, "\(title) should live in More, not the tab bar")
        }
    }

    func testSeededConfigurationChangesTheBar() {
        let app = UITest.launchApp(
            selectedTab: "more",
            phoneTabBar: #"{"order":["drive","scratchpad","stocks","crypto","azan","pass","pad"],"showsHome":false}"#)
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: UITest.timeout))

        for title in ["Drive", "Scratchpad", "Stocks", "Wallet", "More"] {
            XCTAssertTrue(app.tabBars.buttons[title].exists, "\(title) missing from the seeded tab bar")
        }
        XCTAssertFalse(app.tabBars.buttons["Home"].exists, "Home should be absent when showsHome is false")
        XCTAssertTrue(app.buttons["more.row.pass"].waitForExistence(timeout: UITest.timeout),
                      "Pass should have fallen past the cut into More")
    }

    func testSettingsReachesTheTabBarEditor() {
        let app = UITest.launchApp(selectedTab: "more")
        XCTAssertTrue(app.buttons["more.row.settings"].waitForExistence(timeout: UITest.timeout))
        app.buttons["more.row.settings"].tap()

        let customize = app.buttons["Customize Tabs"]
        XCTAssertTrue(customize.waitForExistence(timeout: UITest.timeout))
        customize.tap()

        XCTAssertTrue(app.switches["tabeditor.home.toggle"].waitForExistence(timeout: UITest.timeout),
                      "the iPhone editor did not open")
        // Match the identifier wherever SwiftUI surfaces it in the hierarchy —
        // never fall back to a bare title like "Azan", which the tab bar also
        // carries and which would let this assertion pass with no editor.
        let orderRow = app.descendants(matching: .any)["tabeditor.row.azan"].firstMatch
        XCTAssertTrue(orderRow.waitForExistence(timeout: UITest.timeout),
                      "the draggable order section did not render")
    }
}
