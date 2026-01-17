//
//  PasswordGeneratorView.swift
//  Groo
//
//  Password generator with configurable options for length and character types.
//

import SwiftUI
import UIKit

struct PasswordGeneratorView: View {
    @Environment(\.dismiss) private var dismiss

    let onPasswordGenerated: (String) -> Void

    @State private var password = ""
    @State private var length: Double = 16
    @State private var includeUppercase = true
    @State private var includeLowercase = true
    @State private var includeNumbers = true
    @State private var includeSymbols = true
    @State private var copiedToClipboard = false

    private let minLength: Double = 8
    private let maxLength: Double = 64

    var body: some View {
        NavigationStack {
            VStack(spacing: Theme.Spacing.xl) {
                // Generated password display
                passwordDisplay

                // Options
                optionsSection

                Spacer()

                // Use password button
                Button {
                    onPasswordGenerated(password)
                    dismiss()
                } label: {
                    Text("Use Password")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Theme.Brand.primary)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
                }
            }
            .padding(Theme.Spacing.lg)
            .navigationTitle("Generate Password")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                generatePassword()
            }
        }
    }

    // MARK: - Password Display

    private var passwordDisplay: some View {
        VStack(spacing: Theme.Spacing.md) {
            Text(password)
                .font(.system(.title3, design: .monospaced))
                .multilineTextAlignment(.center)
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))

            HStack(spacing: Theme.Spacing.md) {
                Button {
                    generatePassword()
                } label: {
                    Label("Regenerate", systemImage: "arrow.clockwise")
                        .font(.subheadline)
                }

                Button {
                    UIPasteboard.general.string = password
                    copiedToClipboard = true
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()

                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        copiedToClipboard = false
                    }
                } label: {
                    Label(copiedToClipboard ? "Copied!" : "Copy", systemImage: copiedToClipboard ? "checkmark" : "doc.on.doc")
                        .font(.subheadline)
                }
            }

            // Password strength indicator
            passwordStrengthIndicator
        }
    }

    // MARK: - Password Strength

    private var passwordStrengthIndicator: some View {
        let strength = calculateStrength()

        return VStack(spacing: Theme.Spacing.xs) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color(.systemGray5))
                        .frame(height: 4)

                    RoundedRectangle(cornerRadius: 2)
                        .fill(strength.color)
                        .frame(width: geometry.size.width * strength.percentage, height: 4)
                }
            }
            .frame(height: 4)

            Text(strength.label)
                .font(.caption)
                .foregroundStyle(strength.color)
        }
    }

    private func calculateStrength() -> (label: String, color: Color, percentage: Double) {
        var score = 0

        // Length scoring
        if length >= 12 { score += 1 }
        if length >= 16 { score += 1 }
        if length >= 24 { score += 1 }

        // Character variety
        var charTypes = 0
        if includeUppercase { charTypes += 1 }
        if includeLowercase { charTypes += 1 }
        if includeNumbers { charTypes += 1 }
        if includeSymbols { charTypes += 1 }

        score += charTypes

        switch score {
        case 0...2:
            return ("Weak", .red, 0.25)
        case 3...4:
            return ("Fair", .orange, 0.5)
        case 5...6:
            return ("Strong", .green, 0.75)
        default:
            return ("Very Strong", Theme.Brand.primary, 1.0)
        }
    }

    // MARK: - Options Section

    private var optionsSection: some View {
        VStack(spacing: Theme.Spacing.lg) {
            // Length slider
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                HStack {
                    Text("Length")
                        .font(.headline)
                    Spacer()
                    Text("\(Int(length))")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                Slider(value: $length, in: minLength...maxLength, step: 1) { _ in
                    generatePassword()
                }
                .tint(Theme.Brand.primary)
            }

            Divider()

            // Character type toggles
            VStack(spacing: Theme.Spacing.sm) {
                characterToggle(
                    title: "Uppercase (A-Z)",
                    isOn: $includeUppercase,
                    disabled: !includeLowercase && !includeNumbers && !includeSymbols
                )

                characterToggle(
                    title: "Lowercase (a-z)",
                    isOn: $includeLowercase,
                    disabled: !includeUppercase && !includeNumbers && !includeSymbols
                )

                characterToggle(
                    title: "Numbers (0-9)",
                    isOn: $includeNumbers,
                    disabled: !includeUppercase && !includeLowercase && !includeSymbols
                )

                characterToggle(
                    title: "Symbols (!@#$...)",
                    isOn: $includeSymbols,
                    disabled: !includeUppercase && !includeLowercase && !includeNumbers
                )
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
    }

    private func characterToggle(title: String, isOn: Binding<Bool>, disabled: Bool) -> some View {
        Toggle(title, isOn: isOn)
            .disabled(disabled)
            .onChange(of: isOn.wrappedValue) { _, _ in
                generatePassword()
            }
    }

    // MARK: - Password Generation

    private func generatePassword() {
        var charset = ""

        if includeUppercase {
            charset += "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
        }
        if includeLowercase {
            charset += "abcdefghijklmnopqrstuvwxyz"
        }
        if includeNumbers {
            charset += "0123456789"
        }
        if includeSymbols {
            charset += "!@#$%^&*()_+-=[]{}|;:,.<>?"
        }

        guard !charset.isEmpty else {
            password = ""
            return
        }

        let charArray = Array(charset)
        var result = ""

        for _ in 0..<Int(length) {
            if let randomChar = charArray.randomElement() {
                result.append(randomChar)
            }
        }

        // Ensure at least one character from each selected type
        var finalPassword = Array(result)
        var index = 0

        if includeUppercase && !result.contains(where: { $0.isUppercase }) {
            if let char = "ABCDEFGHIJKLMNOPQRSTUVWXYZ".randomElement() {
                finalPassword[index] = char
                index += 1
            }
        }
        if includeLowercase && !result.contains(where: { $0.isLowercase }) {
            if let char = "abcdefghijklmnopqrstuvwxyz".randomElement() {
                finalPassword[index] = char
                index += 1
            }
        }
        if includeNumbers && !result.contains(where: { $0.isNumber }) {
            if let char = "0123456789".randomElement() {
                finalPassword[index] = char
                index += 1
            }
        }
        if includeSymbols && !result.contains(where: { "!@#$%^&*()_+-=[]{}|;:,.<>?".contains($0) }) {
            if let char = "!@#$%^&*()_+-=[]{}|;:,.<>?".randomElement() {
                finalPassword[index] = char
            }
        }

        // Shuffle to randomize positions of guaranteed characters
        password = String(finalPassword.shuffled())
    }
}

#Preview {
    PasswordGeneratorView { password in
        print("Generated: \(password)")
    }
}
