//
//  PassCrudUITests.swift
//  GrooUITests
//
//  The spec's Pass CRUD journey: create login item → visible in list → edit →
//  detail reflects change → trash → restore. Every mutation round-trips
//  through real AES-GCM encryption and the in-process stub server's
//  optimistic-locking PUT.
//

import XCTest

final class PassCrudUITests: XCTestCase {
    func testLoginItemLifecycleCreateEditDetailTrashRestore() {
        let app = UITest.launchApp(selectedTab: "pass")
        UITest.unlockPass(app)

        // ---- Create ----
        app.buttons["pass.add"].tap()
        let nameField = app.textFields["pass.form.name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: UITest.timeout))
        nameField.tap()
        nameField.typeText("GitHub Test")
        let usernameField = app.textFields["pass.form.username"]
        usernameField.tap()
        usernameField.typeText("octocat@example.com")
        let passwordField = app.secureTextFields["pass.form.password"]
        passwordField.tap()
        passwordField.typeText("hunter2-secret")
        app.buttons["Save"].tap()
        UITest.dismissSavePasswordPromptIfPresent(app)

        // ---- Visible in list ----
        let rowText = app.staticTexts["GitHub Test"]
        XCTAssertTrue(rowText.waitForExistence(timeout: UITest.timeout), "created item must appear in the list")

        // ---- Edit (leading swipe → Edit) ----
        let cell = app.cells.containing(.staticText, identifier: "GitHub Test").firstMatch
        cell.swipeRight()
        let editButton = app.buttons["Edit"]
        XCTAssertTrue(editButton.waitForExistence(timeout: UITest.timeout))
        editButton.tap()
        let editUsername = app.textFields["pass.form.username"]
        XCTAssertTrue(editUsername.waitForExistence(timeout: UITest.timeout))
        editUsername.clearAndTypeText("octocat+edited@example.com")
        app.buttons["Save"].tap()
        UITest.dismissSavePasswordPromptIfPresent(app)

        // ---- Detail reflects the edit ----
        XCTAssertTrue(rowText.waitForExistence(timeout: UITest.timeout))
        rowText.tap()
        XCTAssertTrue(app.staticTexts["octocat+edited@example.com"].waitForExistence(timeout: UITest.timeout),
                      "detail must show the edited username")
        app.buttons["pass.detail.close"].tap()

        // ---- Trash (trailing swipe → Delete) ----
        XCTAssertTrue(rowText.waitForExistence(timeout: UITest.timeout))
        cell.swipeLeft()
        let deleteButton = app.buttons["Delete"]
        XCTAssertTrue(deleteButton.waitForExistence(timeout: UITest.timeout))
        deleteButton.tap()
        XCTAssertTrue(app.staticTexts["No items in your vault"].waitForExistence(timeout: UITest.timeout),
                      "trashed item must leave the list")

        // ---- Restore from trash ----
        app.buttons["pass.menu"].tap()
        let trashMenuItem = app.buttons["Trash"]
        XCTAssertTrue(trashMenuItem.waitForExistence(timeout: UITest.timeout))
        trashMenuItem.tap()
        let trashedText = app.staticTexts["GitHub Test"]
        XCTAssertTrue(trashedText.waitForExistence(timeout: UITest.timeout), "item must be in the trash")
        let trashCell = app.cells.containing(.staticText, identifier: "GitHub Test").firstMatch
        trashCell.swipeRight()
        let restoreButton = app.buttons["Restore"]
        XCTAssertTrue(restoreButton.waitForExistence(timeout: UITest.timeout))
        restoreButton.tap()
        XCTAssertTrue(app.staticTexts["Trash is Empty"].waitForExistence(timeout: UITest.timeout),
                      "restore must empty the trash")
        app.buttons["Done"].tap()

        // ---- Restored item back in the list ----
        XCTAssertTrue(app.staticTexts["GitHub Test"].waitForExistence(timeout: UITest.timeout),
                      "restored item must reappear in the list")
    }
}
