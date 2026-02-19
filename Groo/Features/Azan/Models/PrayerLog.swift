//
//  PrayerLog.swift
//  Groo
//
//  SwiftData model for tracking individual prayer completions.
//

import Foundation
import SwiftData

@Model
final class PrayerLog {
    @Attribute(.unique) var id: String
    var dateString: String
    var prayerRaw: String
    var statusRaw: String
    var loggedAt: Date

    var prayer: Prayer {
        get { Prayer(rawValue: prayerRaw) ?? .fajr }
        set { prayerRaw = newValue.rawValue }
    }

    var status: PrayerStatus {
        get { PrayerStatus(rawValue: statusRaw) ?? .onTime }
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
