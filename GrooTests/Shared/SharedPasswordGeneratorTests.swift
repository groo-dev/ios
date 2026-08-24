//
//  SharedPasswordGeneratorTests.swift
//  GrooTests
//

import Foundation
import Testing
@testable import Groo

struct SharedPasswordGeneratorTests {
    private static let symbolSet = Set("!@#$%^&*()_+-=[]{}|;:,.<>?")

    @Test func generatesRequestedLength() {
        var options = SharedPasswordGeneratorOptions()
        options.length = 32
        #expect(SharedPasswordGenerator.generate(options).count == 32)
    }

    @Test func includesAtLeastOneOfEveryEnabledClass() {
        // Run repeatedly: a guarantee that holds only sometimes is not one.
        for _ in 0..<200 {
            var options = SharedPasswordGeneratorOptions()
            options.length = 8
            let password = SharedPasswordGenerator.generate(options)
            // Hoisted out of #expect: contains(where:) is rethrows, and the
            // macro expansion cannot prove the closure non-throwing.
            let hasUppercase = password.contains { $0.isUppercase }
            let hasLowercase = password.contains { $0.isLowercase }
            let hasNumber = password.contains { $0.isNumber }
            let hasSymbol = password.contains { Self.symbolSet.contains($0) }
            #expect(hasUppercase)
            #expect(hasLowercase)
            #expect(hasNumber)
            #expect(hasSymbol)
        }
    }

    @Test func omitsDisabledClasses() {
        var options = SharedPasswordGeneratorOptions()
        options.length = 40
        options.includeSymbols = false
        options.includeNumbers = false

        let password = SharedPasswordGenerator.generate(options)

        let hasSymbol = password.contains { Self.symbolSet.contains($0) }
        let hasNumber = password.contains { $0.isNumber }
        let allLetters = password.allSatisfy { $0.isLetter }
        #expect(!hasSymbol)
        #expect(!hasNumber)
        #expect(allLetters)
    }

    @Test func emptyCharsetYieldsEmptyPassword() {
        var options = SharedPasswordGeneratorOptions()
        options.includeUppercase = false
        options.includeLowercase = false
        options.includeNumbers = false
        options.includeSymbols = false

        #expect(SharedPasswordGenerator.generate(options).isEmpty)
    }

    @Test func successiveCallsDiffer() {
        let options = SharedPasswordGeneratorOptions()
        let first = SharedPasswordGenerator.generate(options)
        let second = SharedPasswordGenerator.generate(options)
        #expect(first != second)
    }

    /// A length shorter than the number of enabled classes cannot satisfy every
    /// guarantee. It must still return exactly `length` characters rather than
    /// overrun the buffer.
    @Test func lengthShorterThanClassCountStaysInBounds() {
        var options = SharedPasswordGeneratorOptions()
        options.length = 2
        #expect(SharedPasswordGenerator.generate(options).count == 2)
    }
}
