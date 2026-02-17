//
//  AzanModels.swift
//  Groo
//
//  Prayer time enums, calculation methods, and view models.
//

import Foundation

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
