//
//  SmokeUITests.swift
//  GrooUITests
//
//  Proves the --uitest bootstrap works: the app launches hermetically into
//  the main tab UI with no OAuth login and no lock screen.
//

import XCTest

final class SmokeUITests: XCTestCase {
    func testAppLaunchesIntoMainTabsWithoutLogin() {
        let app = UITest.launchApp(selectedTab: "home")

        XCTAssertEqual(app.state, .runningForeground)
        // --uitest bypasses OAuth: the tab bar must appear…
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: UITest.timeout))
        // …and the login screen must not
        XCTAssertFalse(app.buttons["Sign in with Groo"].exists)
    }
}
