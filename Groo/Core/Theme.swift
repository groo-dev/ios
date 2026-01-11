//
//  Theme.swift
//  Groo
//
//  Centralized design tokens following Apple HIG for iOS.
//

import SwiftUI

enum Theme {
    // MARK: - Brand Colors

    enum Brand {
        static let primary = Color(hex: "8B5CF6")      // Violet 500
        static let primaryDark = Color(hex: "7C3AED")  // Violet 600
        static let primaryLight = Color(hex: "A78BFA") // Violet 400
    }

    // MARK: - Spacing Scale (4pt base)

    enum Spacing {
        static let xxs: CGFloat = 2
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }

    // MARK: - Sizes (iOS-optimized)

    enum Size {
        // Item rows
        static let rowHeight: CGFloat = 56
        static let selectedBorderWidth: CGFloat = 3

        // Icons
        static let iconXS: CGFloat = 14
        static let iconSM: CGFloat = 18
        static let iconMD: CGFloat = 22
        static let iconLG: CGFloat = 28
        static let iconXL: CGFloat = 36
        static let iconHero: CGFloat = 56

        // Hit targets (iOS minimum 44pt)
        static let minTapTarget: CGFloat = 44
        static let iconButtonSize: CGFloat = 44

        // Status
        static let statusDot: CGFloat = 10
    }

    // MARK: - Corner Radius

    enum Radius {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 6
        static let md: CGFloat = 10
        static let lg: CGFloat = 14
        static let xl: CGFloat = 20
    }

    // MARK: - Animation

    enum Animation {
        static let fast: Double = 0.15
        static let normal: Double = 0.25
        static let slow: Double = 0.35

        static var fastSpring: SwiftUI.Animation {
            .easeInOut(duration: fast)
        }

        static var normalSpring: SwiftUI.Animation {
            .easeInOut(duration: normal)
        }
    }

    // MARK: - Colors (Semantic)

    enum Colors {
        // Backgrounds
        static let surfaceHover = Color.primary.opacity(0.04)
        static let surfacePressed = Color.primary.opacity(0.08)
        static let surfaceSubtle = Color.primary.opacity(0.02)
        static let surfaceSelected = Color.accentColor.opacity(0.1)

        // Status
        static let success = Color.green
        static let warning = Color.orange
        static let error = Color.red
        static let info = Color.blue

        // Dividers
        static let divider = Color.primary.opacity(0.08)

        // Selection
        static let selectedBorder = Color.accentColor
    }

    // MARK: - Text Line Limits

    enum LineLimit {
        static let itemPreview: Int = 3
        static let singleLine: Int = 1
    }
}

// MARK: - View Extensions

extension View {
    /// Standard horizontal padding for content
    func contentPadding() -> some View {
        padding(.horizontal, Theme.Spacing.lg)
    }

    /// Standard list row padding
    func rowPadding() -> some View {
        padding(.horizontal, Theme.Spacing.lg)
            .padding(.vertical, Theme.Spacing.md)
    }
}

// MARK: - Color Hex Extension

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
