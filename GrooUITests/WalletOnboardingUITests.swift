//
//  WalletOnboardingUITests.swift
//  GrooUITests
//
//  Create-wallet onboarding up to — not including — real network: real BIP39
//  mnemonic + BIP32 address derivation, wallet item persisted through the
//  stub vault PUT, recovery-phrase screen verified, then the portfolio view
//  must render (its RPC/price calls all hit dead-end/stubbed URLs and may
//  show error/empty states — rendering without crashing is the contract).
//

import XCTest

final class WalletOnboardingUITests: XCTestCase {
    func testCreateWalletShowsRecoveryPhraseThenPortfolio() {
        let app = UITest.launchApp(selectedTab: "pass")
        // Wallet creation stores keys in the Pass vault — unlock it first
        UITest.unlockPass(app)

        UITest.openTab(app, "Wallet")
        let createButton = app.buttons["wallet.create"]
        XCTAssertTrue(createButton.waitForExistence(timeout: UITest.timeout))
        createButton.tap()

        // Real BIP39/keystore derivation is slow in Debug — generous wait
        XCTAssertTrue(app.staticTexts["Recovery Phrase"].waitForExistence(timeout: 60))

        // 12 numbered words (indices 1…12, and no 13th)
        XCTAssertTrue(app.staticTexts["12"].exists, "12th mnemonic word index missing")
        XCTAssertFalse(app.staticTexts["13"].exists, "mnemonic must be exactly 12 words")

        // Derived address is shown and well-formed
        let address = app.staticTexts["wallet.address"]
        XCTAssertTrue(address.waitForExistence(timeout: UITest.timeout))
        XCTAssertTrue(address.label.hasPrefix("0x"), "address must be hex: \(address.label)")
        XCTAssertEqual(address.label.count, 42, "address must be 20 bytes hex: \(address.label)")

        // Confirm backup → onboarding is replaced by the portfolio
        app.buttons["wallet.mnemonic.confirm"].tap()
        let portfolio = app.descendants(matching: .any).matching(identifier: "wallet.portfolio").firstMatch
        XCTAssertTrue(portfolio.waitForExistence(timeout: UITest.timeout),
                      "portfolio must render after onboarding (network-dependent content may be empty/error)")
        XCTAssertEqual(app.state, .runningForeground)
    }
}
