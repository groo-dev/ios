//
//  PrayerGuideModels.swift
//  Groo
//
//  Data models for the interactive prayer guide feature.
//

import SwiftUI

// MARK: - Fiqh Madhab (for prayer guide, all 4 individually)

enum FiqhMadhab: String, CaseIterable, Identifiable {
    case hanafi, shafii, maliki, hanbali

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .hanafi: "Hanafi"
        case .shafii: "Shafi'i"
        case .maliki: "Maliki"
        case .hanbali: "Hanbali"
        }
    }
}

// MARK: - Prayer Role

enum PrayerRole: String, CaseIterable, Identifiable {
    case munfarid   // Praying alone
    case imam       // Leading prayer
    case muqtadi    // Following imam

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .munfarid: "Alone"
        case .imam: "Imam"
        case .muqtadi: "Following"
        }
    }

    var icon: String {
        switch self {
        case .munfarid: "person"
        case .imam: "person.wave.2"
        case .muqtadi: "person.2"
        }
    }
}

// MARK: - Recitation Mode

enum RecitationMode: String {
    case aloud, silent

    var displayName: String {
        switch self {
        case .aloud: "Aloud"
        case .silent: "Silent"
        }
    }

    var icon: String {
        switch self {
        case .aloud: "speaker.wave.2"
        case .silent: "speaker.slash"
        }
    }
}

// MARK: - Prayer Posture (for visual icons)

enum PrayerPosture: String, CaseIterable {
    case standing        // Qiyam — hands folded below navel (Hanafi)
    case handsRaised     // Takbir — hands raised to ears
    case bowing          // Ruku — bent at waist, hands on knees
    case standingBrief   // Qawmah — standing straight after ruku
    case prostrating     // Sujud — forehead on ground
    case sitting         // Jalsah/Tashahhud — sitting on legs
    case salam           // Turning head to side while sitting
}

// MARK: - Rakat Category

enum RakatCategory: String, CaseIterable, Identifiable {
    case sunnahMuakkadah
    case sunnahGhairMuakkadah
    case fard
    case wajib
    case nafl

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .sunnahMuakkadah: "Sunnah Mu'akkadah"
        case .sunnahGhairMuakkadah: "Sunnah Ghair Mu'akkadah"
        case .fard: "Fard"
        case .wajib: "Wajib"
        case .nafl: "Nafl"
        }
    }

    var shortName: String {
        switch self {
        case .sunnahMuakkadah: "Sunnah"
        case .sunnahGhairMuakkadah: "Sunnah (Ghair)"
        case .fard: "Fard"
        case .wajib: "Wajib"
        case .nafl: "Nafl"
        }
    }

    var color: Color {
        switch self {
        case .sunnahMuakkadah: .green
        case .sunnahGhairMuakkadah: .mint
        case .fard: Theme.Brand.primary
        case .wajib: .orange
        case .nafl: .blue
        }
    }
}

// MARK: - Rakat Timing

enum RakatTiming: String {
    case before = "Before"
    case main = ""
    case after = "After"
}

// MARK: - Rakat Unit

struct RakatUnit: Identifiable {
    let category: RakatCategory
    let count: Int
    let timing: RakatTiming
    let notes: String?
    let isOptional: Bool

    var id: String { "\(category.rawValue)-\(timing.rawValue)" }

    init(category: RakatCategory, count: Int, timing: RakatTiming = .main, notes: String? = nil, isOptional: Bool = false) {
        self.category = category
        self.count = count
        self.timing = timing
        self.notes = notes
        self.isOptional = isOptional
    }
}

// MARK: - Niyyah Text

struct NiyyahText {
    let arabic: String
    let transliteration: String
    let english: String
}

// MARK: - Sitting Type

enum SittingType {
    case midTashahhud      // Tashahhud only, then stand (e.g. rakat 2 of 4)
    case finalTashahhud    // Tashahhud + Durood + Dua + Salam (end of prayer)
}

// MARK: - Rakat Action

struct RakatAction: Identifiable {
    let id = UUID()
    let name: String
    let arabicText: String?
    let transliteration: String?
    let instruction: String
    let icon: String
    let isSpecial: Bool
    let posture: PrayerPosture?
    let isAloud: Bool

    init(name: String, arabicText: String? = nil, transliteration: String? = nil,
         instruction: String, icon: String, isSpecial: Bool = false,
         posture: PrayerPosture? = nil, isAloud: Bool = false) {
        self.name = name
        self.arabicText = arabicText
        self.transliteration = transliteration
        self.instruction = instruction
        self.icon = icon
        self.isSpecial = isSpecial
        self.posture = posture
        self.isAloud = isAloud
    }
}

// MARK: - Rakat Detail

struct RakatDetail: Identifiable {
    let id = UUID()
    let number: Int
    let actions: [RakatAction]
    let sittingType: SittingType?

    init(number: Int, actions: [RakatAction], sittingType: SittingType? = nil) {
        self.number = number
        self.actions = actions
        self.sittingType = sittingType
    }
}

// MARK: - Rakat Group Guide

struct RakatGroupGuide: Identifiable {
    let id = UUID()
    let unit: RakatUnit
    let displayTitle: String
    let niyyah: NiyyahText
    let recitationMode: RecitationMode
    let rakats: [RakatDetail]
    let notes: [String]
}

// MARK: - Prayer Guide Data

struct PrayerGuideData: Identifiable {
    let prayer: Prayer
    let arabicName: String
    let rakatBreakdown: [RakatUnit]
    let groups: [RakatGroupGuide]
    let generalNotes: [String]

    var id: String { prayer.rawValue }

    var totalRakats: Int {
        rakatBreakdown.filter { !$0.isOptional }.reduce(0) { $0 + $1.count }
    }

    var fardCount: Int {
        rakatBreakdown.first { $0.category == .fard }?.count ?? 0
    }
}
