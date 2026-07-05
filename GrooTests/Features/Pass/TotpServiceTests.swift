//
//  TotpServiceTests.swift
//  GrooTests
//
//  RFC 6238 Appendix B vectors + rotation boundaries + URI parsing.
//

import Foundation
import Testing
@testable import Groo

struct TotpServiceTests {
    // RFC 6238 test secrets, base32-encoded:
    //   SHA1:   ASCII "12345678901234567890"                       (20 bytes)
    //   SHA256: ASCII "12345678901234567890123456789012"           (32 bytes)
    //   SHA512: ASCII "1234567890...1234" repeated to 64 bytes
    static let sha1Secret   = "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ"
    static let sha256Secret = "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZA===="
    static let sha512Secret = "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNA="

    static let rfcTimes: [TimeInterval] = [59, 1_111_111_109, 1_111_111_111, 1_234_567_890, 2_000_000_000, 20_000_000_000]
    static let sha1Expected   = ["94287082", "07081804", "14050471", "89005924", "69279037", "65353130"]
    static let sha256Expected = ["46119246", "68084774", "67062674", "91819424", "90698825", "77737706"]
    static let sha512Expected = ["90693936", "25091201", "99943326", "93441116", "38618901", "47863826"]

    @Test(arguments: zip(rfcTimes, sha1Expected))
    func rfc6238Sha1(_ t: TimeInterval, expected: String) {
        let config = PassTotpConfig(secret: Self.sha1Secret, algorithm: .sha1, digits: 8, period: 30)
        #expect(TotpService.generateCode(config: config, time: Date(timeIntervalSince1970: t)) == expected)
    }

    @Test(arguments: zip(rfcTimes, sha256Expected))
    func rfc6238Sha256(_ t: TimeInterval, expected: String) {
        let config = PassTotpConfig(secret: Self.sha256Secret, algorithm: .sha256, digits: 8, period: 30)
        #expect(TotpService.generateCode(config: config, time: Date(timeIntervalSince1970: t)) == expected)
    }

    @Test(arguments: zip(rfcTimes, sha512Expected))
    func rfc6238Sha512(_ t: TimeInterval, expected: String) {
        let config = PassTotpConfig(secret: Self.sha512Secret, algorithm: .sha512, digits: 8, period: 30)
        #expect(TotpService.generateCode(config: config, time: Date(timeIntervalSince1970: t)) == expected)
    }

    @Test func sixDigitCodesAreLastSixOfEightDigit() {
        let config6 = PassTotpConfig(secret: Self.sha1Secret, algorithm: .sha1, digits: 6, period: 30)
        #expect(TotpService.generateCode(config: config6, time: Date(timeIntervalSince1970: 59)) == "287082")
    }

    // MARK: Rotation boundaries

    @Test func codeIsStableWithinAPeriodAndRotatesAtBoundary() {
        let config = PassTotpConfig(secret: Self.sha1Secret, algorithm: .sha1, digits: 6, period: 30)
        let at30 = TotpService.generateCode(config: config, time: Date(timeIntervalSince1970: 30))
        let at59 = TotpService.generateCode(config: config, time: Date(timeIntervalSince1970: 59))
        let at60 = TotpService.generateCode(config: config, time: Date(timeIntervalSince1970: 60))
        #expect(at30 == at59)
        #expect(at59 != at60)
    }

    @Test func secondsRemainingAndProgress() {
        #expect(TotpService.secondsRemaining(period: 30, time: Date(timeIntervalSince1970: 59)) == 1)
        #expect(TotpService.secondsRemaining(period: 30, time: Date(timeIntervalSince1970: 60)) == 30)
        #expect(TotpService.progress(period: 30, time: Date(timeIntervalSince1970: 45)) == 0.5)
        #expect(TotpService.progress(period: 30, time: Date(timeIntervalSince1970: 60)) == 0.0)
    }

    // MARK: Invalid secrets — divergent by design: app shows placeholder, extension gets nil

    @Test func invalidSecretYieldsPlaceholderInApp() {
        let config = PassTotpConfig(secret: "!!!!", algorithm: .sha1, digits: 6, period: 30)
        #expect(TotpService.generateCode(config: config, time: Date(timeIntervalSince1970: 59)) == "------")
    }

    @Test func invalidSecretYieldsNilInSharedTotp() {
        let config = SharedPassTotpConfig(secret: "!!!!", algorithm: .sha1, digits: 6, period: 30)
        #expect(SharedTotp.generateCode(config: config, time: Date(timeIntervalSince1970: 59)) == nil)
    }

    @Test func sharedTotpMatchesAppTotp() {
        let app = PassTotpConfig(secret: Self.sha1Secret, algorithm: .sha1, digits: 6, period: 30)
        let shared = SharedPassTotpConfig(secret: Self.sha1Secret, algorithm: .sha1, digits: 6, period: 30)
        let t = Date(timeIntervalSince1970: 1_234_567_890)
        #expect(SharedTotp.generateCode(config: shared, time: t) == TotpService.generateCode(config: app, time: t))
    }

    @Test func base32DecodingIsCaseAndPaddingTolerant() {
        let lower = PassTotpConfig(secret: Self.sha1Secret.lowercased(), algorithm: .sha1, digits: 8, period: 30)
        #expect(TotpService.generateCode(config: lower, time: Date(timeIntervalSince1970: 59)) == "94287082")
    }

    // MARK: Epoch boundary (Phase 6)

    /// t = 0 → counter 0 → HMAC over eight 0x00 bytes. RFC 4226 Appendix D:
    /// HOTP(0) for the 20-byte SHA1 test secret is 755224. A
    /// counter-encoding bug (skipping leading zero bytes, wrong endianness
    /// at zero) breaks exactly here and nowhere in the RFC 6238 vectors.
    @Test func epochCounterZeroMatchesRfc4226AndRotatesAt30() {
        let config = PassTotpConfig(secret: Self.sha1Secret, algorithm: .sha1, digits: 6, period: 30)
        let atEpoch = TotpService.generateCode(config: config, time: Date(timeIntervalSince1970: 0))
        #expect(atEpoch == "755224")
        #expect(TotpService.generateCode(config: config, time: Date(timeIntervalSince1970: 29)) == "755224")
        #expect(TotpService.generateCode(config: config, time: Date(timeIntervalSince1970: 30)) != "755224")
    }
}

// MARK: - otpauth:// URI parsing

struct TotpUriParsingTests {
    @Test func parsesFullUri() throws {
        let config = try #require(TotpService.parseUri(
            "otpauth://totp/Groo:user@example.com?secret=JBSWY3DPEHPK3PXP&algorithm=SHA256&digits=8&period=60"))
        #expect(config.secret == "JBSWY3DPEHPK3PXP")
        #expect(config.algorithm == .sha256)
        #expect(config.digits == 8)
        #expect(config.period == 60)
    }

    @Test func appliesDefaultsWhenParamsMissing() throws {
        let config = try #require(TotpService.parseUri("otpauth://totp/Groo?secret=JBSWY3DPEHPK3PXP"))
        #expect(config.algorithm == .sha1)
        #expect(config.digits == 6)
        #expect(config.period == 30)
    }

    @Test(arguments: [
        "otpauth://hotp?secret=ABC",          // wrong host (counter-based)
        "https://totp?secret=ABC",            // wrong scheme
        "otpauth://totp?secret=",             // empty secret
        "otpauth://totp",                     // no query
        "not a uri at all",
    ])
    func rejectsInvalidUris(_ uri: String) {
        #expect(TotpService.parseUri(uri) == nil)
    }

    @Test func unknownAlgorithmFallsBackToSha1() throws {
        let config = try #require(TotpService.parseUri("otpauth://totp/x?secret=ABCD&algorithm=MD5"))
        #expect(config.algorithm == .sha1)
    }
}
