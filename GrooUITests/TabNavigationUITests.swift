//
//  TabNavigationUITests.swift
//  GrooUITests
//
//  Every tab renders its known marker without crashing. First Azan visit may
//  pop the system location alert — dismissed via springboard, sleep-free.
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
            // SettingsView is reached through the tab bar's "More" overflow —
            // a UIKit navigation controller where SwiftUI's
            // .navigationTitle("Settings") is not applied (the bar keeps the
            // identifier 'More'; observed in the failure hierarchy) — so match
            // a row unique to SettingsView instead of the navigation bar.
            ("Settings", app.staticTexts["Customize Tabs"]),
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
}
