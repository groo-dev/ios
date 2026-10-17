//
//  TokenAmount.swift
//  Groo
//
//  Converts a typed decimal amount into a token's base units.
//

import BigInt
import Foundation

/// Turns what someone typed into the integer a transaction actually carries.
///
/// Every amount on Ethereum is an integer of the smallest unit: ETH has 18
/// decimals, so 1.5 ETH is 1_500_000_000_000_000_000 wei. Tokens choose their
/// own — USDC uses 6, so 1.5 USDC is 1_500_000. The multiplier is a property
/// of the asset and is never a constant.
///
/// The conversion is done on the decimal string rather than through `Double`.
/// `Double` carries about 15–17 significant digits; an 18-decimal amount needs
/// up to 19 before any fractional part, so `Double(amount) * 1e18` can land a
/// few units either side of what was typed. Those units are real money, and
/// rounding them is a silent change to a figure someone entered deliberately.
enum TokenAmount {
    enum ParseError: Error, Equatable {
        /// Not a decimal number: empty, signed, or containing junk.
        case notANumber
        /// More fractional digits than the token can represent. Carries the
        /// token's limit so the caller can say so.
        case tooManyFractionalDigits(allowed: Int)
    }

    /// Parses `text` into base units for a token with `decimals` decimals.
    ///
    /// Deliberately strict. An amount with more precision than the token can
    /// hold is rejected rather than truncated: 0.1234567 USDC silently becoming
    /// 0.123456 is a wrong transfer that looks like a successful one, and the
    /// person who typed the extra digit is the only one who can say what they
    /// meant.
    static func baseUnits(from text: String, decimals: Int) throws -> BigUInt {
        precondition(decimals >= 0, "a token cannot have negative decimals")

        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // `.decimalPad` shows the locale's separator, so in much of the world
        // the only key available for a decimal point types a comma. Accept it
        // when it is unambiguously the separator — a lone comma with no dot.
        if !trimmed.contains("."), trimmed.filter({ $0 == "," }).count == 1 {
            trimmed = trimmed.replacingOccurrences(of: ",", with: ".")
        }

        guard !trimmed.isEmpty else { throw ParseError.notANumber }

        let parts = trimmed.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count <= 2 else { throw ParseError.notANumber }

        let whole = String(parts[0])
        let fraction = parts.count == 2 ? String(parts[1]) : ""

        // "5." and ".5" are both things people type; one empty side is fine,
        // but not both, and no side may hold anything but digits.
        guard !(whole.isEmpty && fraction.isEmpty) else { throw ParseError.notANumber }
        guard whole.allSatisfy(\.isASCIIDigit), fraction.allSatisfy(\.isASCIIDigit) else {
            throw ParseError.notANumber
        }

        guard fraction.count <= decimals else {
            throw ParseError.tooManyFractionalDigits(allowed: decimals)
        }

        let scale = BigUInt(10).power(decimals)
        let wholeUnits = (whole.isEmpty ? BigUInt(0) : BigUInt(whole) ?? 0) * scale

        // Right-pad so "1.5" with 6 decimals reads 500000, not 5.
        let padded = fraction.padding(toLength: decimals, withPad: "0", startingAt: 0)
        let fractionalUnits = padded.isEmpty ? BigUInt(0) : (BigUInt(padded) ?? 0)

        return wholeUnits + fractionalUnits
    }
}

private extension Character {
    /// `Character.isNumber` is true for "٣" and "½"; neither survives BigUInt
    /// parsing, and neither belongs in an amount field.
    var isASCIIDigit: Bool { self >= "0" && self <= "9" }
}
