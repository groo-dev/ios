//
//  LocalAzanPreferences.swift
//  Groo
//
//  SwiftData model for Azan user preferences.
//  Single row with unique "default" id.
//

import Foundation
import SwiftData

@Model
final class LocalAzanPreferences {
    @Attribute(.unique) var id: String

    // MARK: - Location

    var latitude: Double
    var longitude: Double
    var locationName: String
    var useDeviceLocation: Bool

    // MARK: - Calculation

    var calculationMethod: String   // AzanCalculationMethod.rawValue
    var madhab: String              // AzanMadhab.rawValue

    // MARK: - Display

    var showSunrise: Bool
    var showSunset: Bool

    // MARK: - Per-Prayer Notification Toggles

    var fajrNotification: Bool
    var sunriseNotification: Bool
    var dhuhrNotification: Bool
    var asrNotification: Bool
    var sunsetNotification: Bool
    var maghribNotification: Bool
    var ishaNotification: Bool

    // MARK: - Jumu'ah (Friday)

    var jumuahReminderEnabled: Bool
    var jumuahReminderMinutes: Int

    // MARK: - Hijri Calendar

    var hijriDateAdjustment: Int    // -2...+2 days to match local moon sighting

    // MARK: - Ramadan

    var suhoorReminderEnabled: Bool
    var suhoorReminderMinutes: Int

    // MARK: - Audio

    var azanSound: String           // filename or "default"
    var fajrAzanSound: String       // separate sound for Fajr
    var playFullAzanOnTap: Bool

    // MARK: - Per-Prayer Minute Adjustments

    var fajrAdjustment: Int
    var sunriseAdjustment: Int
    var dhuhrAdjustment: Int
    var asrAdjustment: Int
    var sunsetAdjustment: Int
    var maghribAdjustment: Int
    var ishaAdjustment: Int

    init(
        id: String = "default",
        latitude: Double = 0,
        longitude: Double = 0,
        locationName: String = "",
        useDeviceLocation: Bool = true,
        calculationMethod: String = AzanCalculationMethod.muslimWorldLeague.rawValue,
        madhab: String = AzanMadhab.hanafi.rawValue,
        showSunrise: Bool = true,
        showSunset: Bool = false,
        fajrNotification: Bool = true,
        sunriseNotification: Bool = false,
        dhuhrNotification: Bool = true,
        asrNotification: Bool = true,
        sunsetNotification: Bool = false,
        maghribNotification: Bool = true,
        ishaNotification: Bool = true,
        jumuahReminderEnabled: Bool = false,
        jumuahReminderMinutes: Int = 60,
        hijriDateAdjustment: Int = 0,
        suhoorReminderEnabled: Bool = false,
        suhoorReminderMinutes: Int = 30,
        azanSound: String = "default",
        fajrAzanSound: String = "default",
        playFullAzanOnTap: Bool = true,
        fajrAdjustment: Int = 0,
        sunriseAdjustment: Int = 0,
        dhuhrAdjustment: Int = 0,
        asrAdjustment: Int = 0,
        sunsetAdjustment: Int = 0,
        maghribAdjustment: Int = 0,
        ishaAdjustment: Int = 0
    ) {
        self.id = id
        self.latitude = latitude
        self.longitude = longitude
        self.locationName = locationName
        self.useDeviceLocation = useDeviceLocation
        self.calculationMethod = calculationMethod
        self.madhab = madhab
        self.showSunrise = showSunrise
        self.showSunset = showSunset
        self.fajrNotification = fajrNotification
        self.sunriseNotification = sunriseNotification
        self.dhuhrNotification = dhuhrNotification
        self.asrNotification = asrNotification
        self.sunsetNotification = sunsetNotification
        self.maghribNotification = maghribNotification
        self.ishaNotification = ishaNotification
        self.jumuahReminderEnabled = jumuahReminderEnabled
        self.jumuahReminderMinutes = jumuahReminderMinutes
        self.hijriDateAdjustment = hijriDateAdjustment
        self.suhoorReminderEnabled = suhoorReminderEnabled
        self.suhoorReminderMinutes = suhoorReminderMinutes
        self.azanSound = azanSound
        self.fajrAzanSound = fajrAzanSound
        self.playFullAzanOnTap = playFullAzanOnTap
        self.fajrAdjustment = fajrAdjustment
        self.sunriseAdjustment = sunriseAdjustment
        self.dhuhrAdjustment = dhuhrAdjustment
        self.asrAdjustment = asrAdjustment
        self.sunsetAdjustment = sunsetAdjustment
        self.maghribAdjustment = maghribAdjustment
        self.ishaAdjustment = ishaAdjustment
    }

    // MARK: - Helpers

    func isNotificationEnabled(for prayer: Prayer) -> Bool {
        switch prayer {
        case .fajr: fajrNotification
        case .sunrise: sunriseNotification
        case .dhuhr: dhuhrNotification
        case .asr: asrNotification
        case .sunset: sunsetNotification
        case .maghrib: maghribNotification
        case .isha: ishaNotification
        }
    }

    func isVisible(prayer: Prayer) -> Bool {
        switch prayer {
        case .sunrise: showSunrise
        case .sunset: showSunset
        default: true
        }
    }

    func adjustment(for prayer: Prayer) -> Int {
        switch prayer {
        case .fajr: fajrAdjustment
        case .sunrise: sunriseAdjustment
        case .dhuhr: dhuhrAdjustment
        case .asr: asrAdjustment
        case .sunset: sunsetAdjustment
        case .maghrib: maghribAdjustment
        case .isha: ishaAdjustment
        }
    }

    var parsedCalculationMethod: AzanCalculationMethod {
        AzanCalculationMethod(rawValue: calculationMethod) ?? .muslimWorldLeague
    }

    var parsedMadhab: AzanMadhab {
        AzanMadhab(rawValue: madhab) ?? .hanafi
    }

    // MARK: - App Group Sync (for Widget)

    func syncToAppGroup() {
        guard let defaults = UserDefaults(suiteName: appGroupIdentifier) else { return }
        defaults.set(latitude, forKey: "azan_latitude")
        defaults.set(longitude, forKey: "azan_longitude")
        defaults.set(calculationMethod, forKey: "azan_calculationMethod")
        defaults.set(madhab, forKey: "azan_madhab")
        defaults.set(fajrAdjustment, forKey: "azan_fajrAdjustment")
        defaults.set(sunriseAdjustment, forKey: "azan_sunriseAdjustment")
        defaults.set(dhuhrAdjustment, forKey: "azan_dhuhrAdjustment")
        defaults.set(asrAdjustment, forKey: "azan_asrAdjustment")
        defaults.set(maghribAdjustment, forKey: "azan_maghribAdjustment")
        defaults.set(ishaAdjustment, forKey: "azan_ishaAdjustment")
    }

    private var appGroupIdentifier: String {
        #if DEBUG
        "group.dev.groo.ios.debug"
        #else
        "group.dev.groo.ios"
        #endif
    }
}
