//
//  PasswordHealthAnalyzer.swift
//  Groo
//
//  Analyzes password health including strength, age, reuse, and 2FA coverage.
//

import Foundation

// MARK: - Health Metrics

enum PasswordStrength: Int, Comparable {
    case weak = 1
    case fair = 2
    case good = 3
    case strong = 4

    var label: String {
        switch self {
        case .weak: "Weak"
        case .fair: "Fair"
        case .good: "Good"
        case .strong: "Strong"
        }
    }

    var color: String {
        switch self {
        case .weak: "red"
        case .fair: "orange"
        case .good: "yellow"
        case .strong: "green"
        }
    }

    static func < (lhs: PasswordStrength, rhs: PasswordStrength) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct PasswordHealthReport {
    let totalPasswords: Int
    let weakPasswords: [PassPasswordItem]
    let reusedPasswords: [String: [PassPasswordItem]]  // password hash -> items
    let oldPasswords: [PassPasswordItem]  // not updated in 90+ days
    let withoutTwoFactor: [PassPasswordItem]

    var weakCount: Int { weakPasswords.count }
    var reusedCount: Int { reusedPasswords.values.flatMap { $0 }.count }
    var oldCount: Int { oldPasswords.count }
    var withoutTwoFactorCount: Int { withoutTwoFactor.count }

    var overallScore: Int {
        guard totalPasswords > 0 else { return 100 }

        let weakPenalty = Double(weakCount) / Double(totalPasswords) * 40
        let reusedPenalty = Double(reusedCount) / Double(totalPasswords) * 30
        let oldPenalty = Double(oldCount) / Double(totalPasswords) * 20
        let twoFactorPenalty = Double(withoutTwoFactorCount) / Double(totalPasswords) * 10

        let score = 100 - Int(weakPenalty + reusedPenalty + oldPenalty + twoFactorPenalty)
        return max(0, min(100, score))
    }

    var scoreLabel: String {
        switch overallScore {
        case 90...100: "Excellent"
        case 70..<90: "Good"
        case 50..<70: "Fair"
        default: "Needs Attention"
        }
    }

    var scoreColor: String {
        switch overallScore {
        case 90...100: "green"
        case 70..<90: "blue"
        case 50..<70: "orange"
        default: "red"
        }
    }
}

// MARK: - Analyzer

struct PasswordHealthAnalyzer {

    /// Analyze all password items and generate a health report
    static func analyze(items: [PassVaultItem]) -> PasswordHealthReport {
        // Extract only non-deleted password items
        let passwords = items.compactMap { item -> PassPasswordItem? in
            guard case .password(let pwd) = item, pwd.deletedAt == nil else {
                return nil
            }
            return pwd
        }

        let weakPasswords = findWeakPasswords(passwords)
        let reusedPasswords = findReusedPasswords(passwords)
        let oldPasswords = findOldPasswords(passwords)
        let withoutTwoFactor = findWithoutTwoFactor(passwords)

        return PasswordHealthReport(
            totalPasswords: passwords.count,
            weakPasswords: weakPasswords,
            reusedPasswords: reusedPasswords,
            oldPasswords: oldPasswords,
            withoutTwoFactor: withoutTwoFactor
        )
    }

    /// Calculate strength of a single password
    static func calculateStrength(_ password: String) -> PasswordStrength {
        guard !password.isEmpty else { return .weak }

        var score = 0

        // Length scoring
        if password.count >= 16 {
            score += 2
        } else if password.count >= 12 {
            score += 1
        } else if password.count < 8 {
            return .weak
        }

        // Character variety
        let hasLowercase = password.contains(where: { $0.isLowercase })
        let hasUppercase = password.contains(where: { $0.isUppercase })
        let hasDigit = password.contains(where: { $0.isNumber })
        let hasSpecial = password.contains(where: { !$0.isLetter && !$0.isNumber })

        let varietyCount = [hasLowercase, hasUppercase, hasDigit, hasSpecial].filter { $0 }.count
        score += varietyCount

        // Common patterns penalty
        if isCommonPassword(password) {
            return .weak
        }

        if hasSequentialChars(password) || hasRepeatingChars(password) {
            score -= 1
        }

        // Final scoring
        switch score {
        case ...2: return .weak
        case 3: return .fair
        case 4...5: return .good
        default: return .strong
        }
    }

    // MARK: - Private Helpers

    private static func findWeakPasswords(_ passwords: [PassPasswordItem]) -> [PassPasswordItem] {
        passwords.filter { calculateStrength($0.password) <= .fair }
    }

    private static func findReusedPasswords(_ passwords: [PassPasswordItem]) -> [String: [PassPasswordItem]] {
        var passwordGroups: [String: [PassPasswordItem]] = [:]

        for item in passwords {
            let key = item.password  // In production, use a hash
            passwordGroups[key, default: []].append(item)
        }

        // Only return groups with more than one item (reused)
        return passwordGroups.filter { $0.value.count > 1 }
    }

    private static func findOldPasswords(_ passwords: [PassPasswordItem]) -> [PassPasswordItem] {
        let ninetyDaysAgo = Int(Date().timeIntervalSince1970 * 1000) - (90 * 24 * 60 * 60 * 1000)

        return passwords.filter { $0.updatedAt < ninetyDaysAgo }
    }

    private static func findWithoutTwoFactor(_ passwords: [PassPasswordItem]) -> [PassPasswordItem] {
        passwords.filter { $0.totp == nil }
    }

    private static func isCommonPassword(_ password: String) -> Bool {
        let common = [
            "password", "123456", "12345678", "qwerty", "abc123",
            "monkey", "1234567", "letmein", "trustno1", "dragon",
            "baseball", "iloveyou", "master", "sunshine", "ashley",
            "football", "shadow", "123123", "654321", "superman",
            "qazwsx", "michael", "password1", "password123"
        ]
        return common.contains(password.lowercased())
    }

    private static func hasSequentialChars(_ password: String) -> Bool {
        let sequences = ["123", "234", "345", "456", "567", "678", "789",
                        "abc", "bcd", "cde", "def", "efg", "fgh", "ghi",
                        "qwe", "wer", "ert", "rty", "tyu", "yui", "uio"]
        let lower = password.lowercased()
        return sequences.contains { lower.contains($0) }
    }

    private static func hasRepeatingChars(_ password: String) -> Bool {
        let chars = Array(password)
        for i in 0..<(chars.count - 2) {
            if chars[i] == chars[i+1] && chars[i+1] == chars[i+2] {
                return true
            }
        }
        return false
    }
}
