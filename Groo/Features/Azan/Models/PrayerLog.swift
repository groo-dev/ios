//
//  PrayerLog.swift
//  Groo
//
//  SwiftData model for tracking individual prayer completions.
//

import Foundation
import os
import SwiftData

@Model
final class PrayerLog {
    @Attribute(.unique) var id: String
    var dateString: String
    var prayerRaw: String
    var statusRaw: String
    var loggedAt: Date

    var prayer: Prayer {
        get {
            guard let parsed = Prayer(rawValue: prayerRaw) else {
                Log.azan.error("[PrayerLog] Unknown prayerRaw '\(self.prayerRaw, privacy: .public)' in log '\(self.id, privacy: .public)' — falling back to Fajr")
                return .fajr
            }
            return parsed
        }
        set { prayerRaw = newValue.rawValue }
    }

    var status: PrayerStatus {
        get {
            guard let parsed = PrayerStatus(rawValue: statusRaw) else {
                Log.azan.error("[PrayerLog] Unknown statusRaw '\(self.statusRaw, privacy: .public)' in log '\(self.id, privacy: .public)' — falling back to on-time")
                return .onTime
            }
            return parsed
        }
        set { statusRaw = newValue.rawValue }
    }

    init(dateString: String, prayer: Prayer, status: PrayerStatus) {
        self.id = "\(dateString)_\(prayer.rawValue)"
        self.dateString = dateString
        self.prayerRaw = prayer.rawValue
        self.statusRaw = status.rawValue
        self.loggedAt = Date()
    }
}
