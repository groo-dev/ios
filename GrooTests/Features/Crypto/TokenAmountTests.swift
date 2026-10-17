//
//  TokenAmountTests.swift
//  GrooTests
//
//  Decimal-string to base-unit conversion. Vector failures mean an amount
//  would be sent that nobody typed — never adjust the constants.
//

import BigInt
import Foundation
import Testing
@testable import Groo

struct TokenAmountTests {
    // MARK: - Scale comes from the asset, never a constant

    @Test func wholeAmountsScaleByTheTokensOwnDecimals() throws {
        #expect(try TokenAmount.baseUnits(from: "1", decimals: 18) == BigUInt("1000000000000000000"))
        #expect(try TokenAmount.baseUnits(from: "1", decimals: 6) == BigUInt(1_000_000))
        #expect(try TokenAmount.baseUnits(from: "1", decimals: 0) == BigUInt(1))
    }

    /// The bug this whole type exists to prevent: 1 USDC is 1_000_000, not
    /// 10^18. Treating every token as ETH overstates a 6-decimal transfer by a
    /// factor of a trillion.
    @Test func aSixDecimalTokenIsNotScaledLikeEther() throws {
        let usdc = try TokenAmount.baseUnits(from: "2.5", decimals: 6)
        let ether = try TokenAmount.baseUnits(from: "2.5", decimals: 18)
        #expect(usdc == BigUInt(2_500_000))
        #expect(ether == BigUInt("2500000000000000000"))
        #expect(ether / usdc == BigUInt("1000000000000"))
    }

    @Test func fractionsArePaddedNotTruncated() throws {
        // "1.5" with 6 decimals is 1_500_000 — pad right. Reading the fraction
        // as a plain integer would give 1_000_005.
        #expect(try TokenAmount.baseUnits(from: "1.5", decimals: 6) == BigUInt(1_500_000))
        #expect(try TokenAmount.baseUnits(from: "1.05", decimals: 6) == BigUInt(1_050_000))
        #expect(try TokenAmount.baseUnits(from: "0.000001", decimals: 6) == BigUInt(1))
    }

    // MARK: - Why Double was abandoned

    @Test func exactParsingDisagreesWithTheDoublePathOnAnOrdinaryAmount() throws {
        let exact = try TokenAmount.baseUnits(from: "1.1", decimals: 18)
        #expect(exact == BigUInt("1100000000000000000"))

        // The path this replaced. 1.1 has no exact binary representation, so
        // the multiplication lands 128 wei above what was typed. Tiny, but it
        // is not the number someone entered, and nothing in the old code could
        // notice.
        let viaDouble = BigUInt(Double("1.1")! * 1e18)
        #expect(viaDouble != exact,
                "if these now agree the test proves nothing — check the premise before deleting it")
        #expect(viaDouble == BigUInt("1100000000000000128"))
    }

    @Test func precisionSurvivesBeyondWhatDoubleCanHold() throws {
        // 27 significant digits; a Double carries about 17.
        let typed = "123456789.123456789123456789"
        #expect(try TokenAmount.baseUnits(from: typed, decimals: 18)
                == BigUInt("123456789123456789123456789"))
    }

    // MARK: - Too much precision is refused, not rounded away

    @Test func moreFractionalDigitsThanTheTokenHoldsIsRejected() {
        #expect(throws: TokenAmount.ParseError.tooManyFractionalDigits(allowed: 6)) {
            try TokenAmount.baseUnits(from: "0.1234567", decimals: 6)
        }
        #expect(throws: TokenAmount.ParseError.tooManyFractionalDigits(allowed: 0)) {
            try TokenAmount.baseUnits(from: "1.5", decimals: 0)
        }
    }

    /// Truncating would turn a deliberate figure into a different, smaller
    /// transfer that still reports success. Refusing makes the person decide.
    @Test func anAmountAtTheLimitIsStillAccepted() throws {
        #expect(try TokenAmount.baseUnits(from: "0.123456", decimals: 6) == BigUInt(123_456))
    }

    // MARK: - Shapes people actually type

    @Test func partialDecimalsAreAccepted() throws {
        #expect(try TokenAmount.baseUnits(from: "5.", decimals: 6) == BigUInt(5_000_000))
        #expect(try TokenAmount.baseUnits(from: ".5", decimals: 6) == BigUInt(500_000))
        #expect(try TokenAmount.baseUnits(from: "  1.5  ", decimals: 6) == BigUInt(1_500_000))
    }

    /// `.decimalPad` shows the locale's separator, so across much of Europe the
    /// only decimal key available types a comma. Before this, such a person
    /// could not enter a fractional amount at all.
    @Test func aLoneCommaIsTreatedAsTheDecimalSeparator() throws {
        #expect(try TokenAmount.baseUnits(from: "1,5", decimals: 6) == BigUInt(1_500_000))
    }

    @Test func ambiguousOrMalformedInputIsRefused() {
        for bad in ["", "   ", ".", "abc", "-1", "1.2.3", "1,234.5", "1e18", "0x10", "½", "٣"] {
            #expect(throws: (any Error).self, "accepted \(bad)") {
                try TokenAmount.baseUnits(from: bad, decimals: 18)
            }
        }
    }

    @Test func zeroParsesRatherThanThrowing() throws {
        // Zero is well-formed; refusing to *send* it is the caller's rule.
        #expect(try TokenAmount.baseUnits(from: "0", decimals: 18) == BigUInt(0))
        #expect(try TokenAmount.baseUnits(from: "0.0", decimals: 18) == BigUInt(0))
    }
}
