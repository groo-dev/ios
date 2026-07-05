//
//  SmokeUITests.swift
//  GrooUITests
//
//  Proves the UI test target can launch the app.
//

import XCTest

final class SmokeUITests: XCTestCase {
    func testAppLaunches() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertEqual(app.state, .runningForeground)
    }
}
