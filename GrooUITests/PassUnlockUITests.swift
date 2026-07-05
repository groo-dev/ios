//
//  PassUnlockUITests.swift
//  GrooUITests
//
//  Pass vault unlock/lock: wrong master password rejected (real PBKDF2 +
//  AES-GCM against the stub vault), correct password reaches the item list,
//  Lock Vault re-locks. No biometrics under --uitest, so PassUnlockView
//  always shows the password field directly.
//

import XCTest

final class PassUnlockUITests: XCTestCase {
    func testWrongMasterPasswordIsRejected() {
        let app = UITest.launchApp(selectedTab: "pass")

        let field = app.secureTextFields["pass.unlock.password"]
        XCTAssertTrue(field.waitForExistence(timeout: UITest.timeout))
        field.tap()
        field.typeText("definitely-wrong-password")
        app.buttons["pass.unlock.submit"].tap()

        // Wrong key ⇒ AES-GCM open fails ⇒ error surfaces, vault stays locked
        XCTAssertTrue(app.staticTexts["pass.unlock.error"].waitForExistence(timeout: UITest.timeout))
        XCTAssertTrue(app.staticTexts["Pass is Locked"].exists)
        XCTAssertFalse(app.buttons["pass.add"].exists)
    }

    func testUnlockThenLockVaultRelocks() {
        let app = UITest.launchApp(selectedTab: "pass")

        UITest.unlockPass(app)
        // Seeded vault is empty — the empty state is the post-unlock screen
        XCTAssertTrue(app.staticTexts["No items in your vault"].waitForExistence(timeout: UITest.timeout))

        app.buttons["pass.menu"].tap()
        let lockButton = app.buttons["Lock Vault"]
        XCTAssertTrue(lockButton.waitForExistence(timeout: UITest.timeout))
        lockButton.tap()

        // Locked again: unlock screen back, list gone
        XCTAssertTrue(app.staticTexts["Pass is Locked"].waitForExistence(timeout: UITest.timeout))
        XCTAssertTrue(app.secureTextFields["pass.unlock.password"].waitForExistence(timeout: UITest.timeout))
        XCTAssertFalse(app.buttons["pass.add"].exists)
    }
}
