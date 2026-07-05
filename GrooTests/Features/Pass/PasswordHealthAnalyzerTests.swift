//
//  PasswordHealthAnalyzerTests.swift
//  GrooTests
//

import Foundation
import Testing
@testable import Groo

struct PasswordHealthAnalyzerTests {
    /// Fixed "now" so age-based checks are deterministic: 2023-11-14T22:13:20Z
    static let now = Date(timeIntervalSince1970: 1_700_000_000)
    static let nowMs = 1_700_000_000_000

    func item(_ id: String, password: String, updatedAt: Int = nowMs,
              totp: PassTotpConfig? = nil, deletedAt: Int? = nil) -> PassVaultItem {
        .password(VaultItemFixtures.samplePasswordItem(
            id: id, password: password, totp: totp, updatedAt: updatedAt, deletedAt: deletedAt))
    }

    // MARK: Strength

    @Test(arguments: [
        "",                    // empty
        "short1!",             // < 8 chars
        "password123",         // common-password list
        "qwerty",              // common-password list
        "aaaaaaaaaaaa",        // repeating, no variety
    ])
    func weakPasswords(_ password: String) {
        #expect(PasswordHealthAnalyzer.calculateStrength(password) == .weak)
    }

    @Test func longVariedPasswordIsStrong() {
        #expect(PasswordHealthAnalyzer.calculateStrength("kV9#mQ2$xL7@wF4z") == .strong)
    }

    @Test func sequentialCharsArePenalized() {
        // Same length/variety, one contains "123"
        let withSeq = PasswordHealthAnalyzer.calculateStrength("Bx123!qZmWpL#kV9")
        let without = PasswordHealthAnalyzer.calculateStrength("Bx739!qZmWpL#kV2")
        #expect(withSeq < without)
    }

    // MARK: Report

    @Test func emptyVaultScoresPerfect() {
        let report = PasswordHealthAnalyzer.analyze(items: [], now: Self.now)
        #expect(report.totalPasswords == 0)
        #expect(report.overallScore == 100)
    }

    @Test func reusedPasswordsAreGrouped() {
        let report = PasswordHealthAnalyzer.analyze(items: [
            item("a", password: "kV9#mQ2$xL7@wF4z"),
            item("b", password: "kV9#mQ2$xL7@wF4z"),
            item("c", password: "uniqueUnique#77!"),
        ], now: Self.now)
        #expect(report.reusedCount == 2)
        #expect(report.reusedPasswords.count == 1)
    }

    @Test func oldPasswordBoundaryAt90Days() {
        let dayMs = 24 * 60 * 60 * 1000
        let report = PasswordHealthAnalyzer.analyze(items: [
            item("old", password: "kV9#mQ2$xL7@wF4z", updatedAt: Self.nowMs - 91 * dayMs),
            item("fresh", password: "uniqueUnique#77!", updatedAt: Self.nowMs - 89 * dayMs),
        ], now: Self.now)
        #expect(report.oldPasswords.map(\.id) == ["old"])
    }

    @Test func totpCoverageIsTracked() {
        let totp = PassTotpConfig(secret: "JBSWY3DPEHPK3PXP", algorithm: .sha1, digits: 6, period: 30)
        let report = PasswordHealthAnalyzer.analyze(items: [
            item("with", password: "kV9#mQ2$xL7@wF4z", totp: totp),
            item("without", password: "uniqueUnique#77!"),
        ], now: Self.now)
        #expect(report.withoutTwoFactor.map(\.id) == ["without"])
    }

    @Test func deletedItemsAreExcluded() {
        let report = PasswordHealthAnalyzer.analyze(items: [
            item("deleted", password: "password123", deletedAt: Self.nowMs),
        ], now: Self.now)
        #expect(report.totalPasswords == 0)
    }

    @Test func scoreStaysWithinBounds() {
        // All-bad vault must clamp at >= 0
        let items = (0..<5).map { item("i\($0)", password: "password123", updatedAt: 0) }
        let report = PasswordHealthAnalyzer.analyze(items: items, now: Self.now)
        #expect((0...100).contains(report.overallScore))
        #expect(report.scoreLabel == "Needs Attention")
    }
}
