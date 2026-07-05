//
//  AzanPreferencesTests.swift
//  GrooTests
//
//  LocalAzanPreferences defaults/fallbacks/per-prayer accessors and the
//  single-row persistence contract through LocalStore, plus PrayerLog
//  upsert + raw-value fallbacks.
//

import Foundation
import SwiftData
import Testing
@testable import Groo

@MainActor
struct AzanPreferencesTests {
    @Test func defaultsPinProductChoices() {
        let prefs = LocalAzanPreferences()

        #expect(prefs.id == "default")
        #expect(prefs.parsedCalculationMethod == .muslimWorldLeague)
        #expect(prefs.parsedMadhab == .hanafi)
        #expect(prefs.showSunrise && !prefs.showSunset)
        #expect(prefs.jumuahReminderMinutes == 60)
        #expect(prefs.suhoorReminderMinutes == 30)
        #expect(prefs.hijriDateAdjustment == 0)
    }

    @Test func unknownRawValuesFallBackSafely() {
        let prefs = LocalAzanPreferences(calculationMethod: "bogus-method", madhab: "bogus-madhab")

        // A bad persisted string must degrade to defaults, never crash or
        // silently compute wrong times with a nil method
        #expect(prefs.parsedCalculationMethod == .muslimWorldLeague)
        #expect(prefs.parsedMadhab == .hanafi)
    }

    @Test func perPrayerAccessorsMapCorrectly() {
        let prefs = LocalAzanPreferences(
            showSunrise: false,
            sunriseNotification: true,
            ishaNotification: false,
            asrAdjustment: 7,
            ishaAdjustment: -3
        )

        #expect(prefs.isNotificationEnabled(for: .sunrise))
        #expect(!prefs.isNotificationEnabled(for: .isha))
        #expect(prefs.adjustment(for: .asr) == 7)
        #expect(prefs.adjustment(for: .isha) == -3)
        #expect(prefs.adjustment(for: .fajr) == 0)
        #expect(!prefs.isVisible(prayer: .sunrise))   // tracks showSunrise
        #expect(prefs.isVisible(prayer: .dhuhr))      // real prayers always visible
    }

    @Test func saveReplacesTheSingletonRow() throws {
        let store = try InMemoryLocalStore.make()
        store.saveAzanPreferences(LocalAzanPreferences(latitude: 21.42, longitude: 39.83, locationName: "Makkah"))

        store.saveAzanPreferences(LocalAzanPreferences(latitude: 24.47, longitude: 39.61, locationName: "Madinah"))

        let loaded = try #require(store.getAzanPreferences())
        #expect(loaded.locationName == "Madinah")
        #expect(loaded.latitude == 24.47)
        #expect(try store.context.fetchCount(FetchDescriptor<LocalAzanPreferences>()) == 1)
    }

    @Test func prayerLogUpsertsByDateAndPrayer() throws {
        let store = try InMemoryLocalStore.make()
        store.savePrayerLog(PrayerLog(dateString: "2026-07-01", prayer: .fajr, status: .onTime))
        store.savePrayerLog(PrayerLog(dateString: "2026-07-01", prayer: .fajr, status: .late))
        store.savePrayerLog(PrayerLog(dateString: "2026-07-02", prayer: .fajr, status: .onTime))

        let day1 = store.getPrayerLogs(forDateString: "2026-07-01")
        #expect(day1.count == 1)
        #expect(day1.first?.status == .late)   // second log replaced the first
        #expect(store.getPrayerLogs(from: "2026-07-01", to: "2026-07-02").count == 2)

        store.deletePrayerLog(dateString: "2026-07-01", prayer: .fajr)
        #expect(store.getPrayerLogs(forDateString: "2026-07-01").isEmpty)
    }

    @Test func prayerLogUnknownRawValuesFallBack() {
        let log = PrayerLog(dateString: "2026-07-01", prayer: .asr, status: .late)
        log.prayerRaw = "bogus"
        log.statusRaw = "bogus"

        #expect(log.prayer == .fajr)      // documented fallback
        #expect(log.status == .onTime)    // documented fallback
    }
}
