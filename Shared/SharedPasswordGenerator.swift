//
//  SharedPasswordGenerator.swift
//  Groo
//
//  Password generation, extracted from PasswordGeneratorView so the AutoFill
//  extension can generate too — a different target cannot see an app-target
//  view, and a `private func` inside a `View` cannot be tested at all.
//

import Foundation

struct SharedPasswordGeneratorOptions {
    var length: Int = 20
    var includeUppercase = true
    var includeLowercase = true
    var includeNumbers = true
    var includeSymbols = true

    static let uppercase = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    static let lowercase = "abcdefghijklmnopqrstuvwxyz"
    static let numbers = "0123456789"
    static let symbols = "!@#$%^&*()_+-=[]{}|;:,.<>?"

    /// The character classes the caller enabled, each as its own alphabet, so
    /// the generator can guarantee one character from each.
    var enabledClasses: [String] {
        var classes: [String] = []
        if includeUppercase { classes.append(Self.uppercase) }
        if includeLowercase { classes.append(Self.lowercase) }
        if includeNumbers { classes.append(Self.numbers) }
        if includeSymbols { classes.append(Self.symbols) }
        return classes
    }
}

enum SharedPasswordGenerator {
    /// Generate a password containing at least one character from every enabled
    /// class, when the requested length allows it.
    ///
    /// `randomElement()` draws from `SystemRandomNumberGenerator`, which is
    /// cryptographically secure on Apple platforms. Do not swap it for a seeded
    /// generator to make tests deterministic — assert properties instead.
    static func generate(_ options: SharedPasswordGeneratorOptions) -> String {
        let classes = options.enabledClasses
        guard !classes.isEmpty, options.length > 0 else { return "" }

        let alphabet = Array(classes.joined())

        // One guaranteed character per class first, then fill. Truncating to
        // `length` keeps a short request in bounds rather than overrunning it.
        var characters: [Character] = classes
            .prefix(options.length)
            .compactMap { Array($0).randomElement() }

        while characters.count < options.length {
            if let next = alphabet.randomElement() { characters.append(next) }
        }

        return String(characters.shuffled())
    }
}
