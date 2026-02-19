//
//  AzanModels.swift
//  Groo
//
//  Prayer time enums, calculation methods, and view models.
//

import Foundation
import SwiftUI

// MARK: - Prayer

enum Prayer: String, CaseIterable, Codable, Identifiable {
    case fajr, sunrise, dhuhr, asr, sunset, maghrib, isha

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .fajr: "Fajr"
        case .sunrise: "Sunrise"
        case .dhuhr: "Dhuhr"
        case .asr: "Asr"
        case .sunset: "Sunset"
        case .maghrib: "Maghrib"
        case .isha: "Isha"
        }
    }

    var icon: String {
        switch self {
        case .fajr: "sun.horizon"
        case .sunrise: "sunrise"
        case .dhuhr: "sun.max"
        case .asr: "sun.min"
        case .sunset: "sunset"
        case .maghrib: "moon.haze"
        case .isha: "moon.stars"
        }
    }

    /// Whether this is an informational row (not an actual prayer)
    var isInfoOnly: Bool {
        self == .sunrise || self == .sunset
    }

    /// Prayers that receive notification (exclude sunrise/sunset by default)
    static var notifiable: [Prayer] {
        [.fajr, .dhuhr, .asr, .maghrib, .isha]
    }
}

// MARK: - Prayer Status

enum PrayerStatus: String, CaseIterable, Codable {
    case onTime, late

    var displayName: String {
        switch self {
        case .onTime: "On Time"
        case .late: "Qaza"
        }
    }

    var icon: String {
        switch self {
        case .onTime: "checkmark.circle.fill"
        case .late: "clock.arrow.circlepath"
        }
    }

    var color: Color {
        switch self {
        case .onTime: Theme.Colors.success
        case .late: Theme.Colors.warning
        }
    }
}

// MARK: - Calculation Method

enum AzanCalculationMethod: String, CaseIterable, Codable, Identifiable {
    case muslimWorldLeague
    case egyptian
    case karachi
    case ummAlQura
    case dubai
    case moonsightingCommittee
    case northAmerica
    case kuwait
    case qatar
    case singapore
    case tehran
    case turkey

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .muslimWorldLeague: "Muslim World League"
        case .egyptian: "Egyptian General Authority"
        case .karachi: "University of Islamic Sciences, Karachi"
        case .ummAlQura: "Umm Al-Qura University, Makkah"
        case .dubai: "Dubai"
        case .moonsightingCommittee: "Moonsighting Committee"
        case .northAmerica: "ISNA (North America)"
        case .kuwait: "Kuwait"
        case .qatar: "Qatar"
        case .singapore: "Singapore"
        case .tehran: "Tehran"
        case .turkey: "Turkey"
        }
    }
}

// MARK: - Madhab

enum AzanMadhab: String, CaseIterable, Codable, Identifiable {
    case shafi
    case hanafi

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .shafi: "Shafi'i, Maliki, Hanbali"
        case .hanafi: "Hanafi"
        }
    }

    var description: String {
        switch self {
        case .shafi: "Standard Asr time (shadow equals object length)"
        case .hanafi: "Later Asr time (shadow equals twice object length)"
        }
    }
}

// MARK: - Prayer Time Entry (View Model)

struct PrayerTimeEntry: Identifiable {
    let prayer: Prayer
    let time: Date
    let isNext: Bool
    let isPassed: Bool
    let isCurrent: Bool
    let currentUrgency: PrayerDeadline.Urgency?
    let notificationEnabled: Bool
    let adjustment: Int
    let fridayLabel: String?
    let ramadanLabel: String?

    var id: String { prayer.rawValue }

    var displayTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: time)
    }

    var displayName: String {
        if let label = fridayLabel {
            return label
        }
        return prayer.displayName
    }
}

// MARK: - Countdown

struct PrayerCountdown {
    let prayer: Prayer
    let time: Date
    let remaining: TimeInterval

    var displayName: String {
        prayer.displayName
    }

    var formattedCountdown: String {
        let hours = Int(remaining) / 3600
        let minutes = (Int(remaining) % 3600) / 60
        let seconds = Int(remaining) % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }

    var formattedTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: time)
    }
}

// MARK: - Prayer Deadline (Qaza Countdown)

struct PrayerDeadline {
    let prayer: Prayer
    let deadline: Date
    let remaining: TimeInterval

    var formattedRemaining: String {
        let hours = Int(remaining) / 3600
        let minutes = (Int(remaining) % 3600) / 60
        let seconds = Int(remaining) % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }

    // MARK: - Urgency

    enum Urgency {
        case plenty, warning, urgent

        var color: Color {
            switch self {
            case .plenty: Theme.Brand.primary
            case .warning: Theme.Colors.warning
            case .urgent: Theme.Colors.error
            }
        }
    }

    private var warningThreshold: TimeInterval {
        switch prayer {
        case .fajr: 25 * 60
        case .dhuhr: 40 * 60
        case .asr: 25 * 60
        case .maghrib: 30 * 60
        case .isha: 35 * 60
        default: 25 * 60
        }
    }

    private var urgentThreshold: TimeInterval {
        switch prayer {
        case .fajr: 15 * 60
        case .dhuhr: 30 * 60
        case .asr: 15 * 60
        case .maghrib: 20 * 60
        case .isha: 25 * 60
        default: 15 * 60
        }
    }

    var urgency: Urgency {
        if remaining < urgentThreshold { return .urgent }
        if remaining < warningThreshold { return .warning }
        return .plenty
    }
}

// MARK: - Ramadan Info

struct RamadanInfo {
    let isRamadan: Bool
    let day: Int
    let totalDays: Int
    let suhoorTime: Date?
    let iftarTime: Date?
    let fastingDuration: TimeInterval?

    var dayLabel: String {
        "Day \(day) of Ramadan"
    }

    var formattedFastingDuration: String? {
        guard let duration = fastingDuration else { return nil }
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        return "\(hours)h \(minutes)m"
    }
}
