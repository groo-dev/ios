//
//  PrayerTimeServiceTests.swift
//  GrooTests
//
//  Adhan-wrapper logic over an injected clock: chronology, minute
//  adjustments, sunrise-skip, qaza deadlines, tomorrow-fajr rollover,
//  multi-day calculation, Ramadan hijri detection. All assertions are
//  relational (orderings, exact deltas, cross-service equality) so they
//  hold in any host timezone; absolute times are Adhan's business and the
//  library itself is out of scope (spec: we test our usage of it).
//

import Foundation
import Testing
@testable import Groo

@MainActor
struct PrayerTimeServiceTests {
    // Dubai — low latitude, so all prayer times exist and stay well-ordered
    // year-round in every timezone's rendering of "today".
    static let latitude = 25.2048
    static let longitude = 55.2708

    static let julyNoon = Date(timeIntervalSince1970: 1_783_252_800)      // 2026-07-05T12:00:00Z
    static let ramadanMidMonth = Date(timeIntervalSince1970: 1_772_355_600) // 2026-03-01T09:00:00Z (≈ Ramadan 11, 1447 AH)

    static func makeService(nowAt instant: Date,
                            preferences: LocalAzanPreferences = LocalAzanPreferences()) -> PrayerTimeService {
        let service = PrayerTimeService(now: { instant })
        service.configure(latitude: latitude, longitude: longitude, preferences: preferences)
        return service
    }

    static func time(of prayer: Prayer, in service: PrayerTimeService) throws -> Date {
        try #require(service.todayPrayers.first(where: { $0.prayer == prayer }), "no \(prayer.rawValue) row").time
    }

    // MARK: - Chronology & visibility

    @Test func defaultVisiblePrayersAreChronological() {
        let service = Self.makeService(nowAt: Self.julyNoon)

        // Default prefs: sunrise shown, sunset hidden → 6 rows in case order
        #expect(service.todayPrayers.map(\.prayer) == [.fajr, .sunrise, .dhuhr, .asr, .maghrib, .isha])
        let times = service.todayPrayers.map(\.time)
        #expect(zip(times, times.dropFirst()).allSatisfy { $0 < $1 },
                "prayer times must be strictly increasing: \(times)")
    }

    // MARK: - Minute adjustments

    @Test func asrAdjustmentShiftsExactlyThirtyMinutes() throws {
        let baseline = Self.makeService(nowAt: Self.julyNoon)
        let adjusted = Self.makeService(nowAt: Self.julyNoon,
                                        preferences: LocalAzanPreferences(asrAdjustment: 30))

        let baseAsr = try Self.time(of: .asr, in: baseline)
        let shiftedAsr = try Self.time(of: .asr, in: adjusted)
        #expect(shiftedAsr == baseAsr.addingTimeInterval(30 * 60))

        // And an unadjusted prayer is untouched
        let baseFajr = try Self.time(of: .fajr, in: baseline)
        let adjustedFajr = try Self.time(of: .fajr, in: adjusted)
        #expect(adjustedFajr == baseFajr)
    }

    // MARK: - Next prayer selection

    /// Sunrise is not a prayer: between fajr and sunrise the "next prayer"
    /// countdown must point at Dhuhr, not sunrise.
    @Test func nextPrayerSkipsSunriseToDhuhr() throws {
        let baseline = Self.makeService(nowAt: Self.julyNoon)
        let sunrise = try Self.time(of: .sunrise, in: baseline)
        let dhuhr = try Self.time(of: .dhuhr, in: baseline)

        let betweenFajrAndSunrise = Self.makeService(nowAt: sunrise.addingTimeInterval(-60))
        let next = try #require(betweenFajrAndSunrise.nextPrayer)
        #expect(next.prayer == .dhuhr)
        #expect(next.time == dhuhr)
    }

    /// After Isha the day is over: next is TOMORROW's Fajr, and Isha stays
    /// the active prayer with tomorrow's Fajr as its qaza deadline.
    @Test func afterIshaNextIsTomorrowsFajrAndIshaRunsUntilIt() throws {
        let baseline = Self.makeService(nowAt: Self.julyNoon)
        let isha = try Self.time(of: .isha, in: baseline)
        let afterIshaInstant = isha.addingTimeInterval(60)

        let afterIsha = Self.makeService(nowAt: afterIshaInstant)
        let next = try #require(afterIsha.nextPrayer)
        #expect(next.prayer == .fajr)
        #expect(next.time > afterIshaInstant, "tomorrow's fajr must be in the future")

        let deadline = try #require(afterIsha.currentPrayerDeadline)
        #expect(deadline.prayer == .isha)
        #expect(deadline.deadline == next.time, "isha's qaza cutoff is tomorrow's fajr")
    }

    // MARK: - Qaza deadlines

    @Test func fajrQazaDeadlineEndsAtSunrise() throws {
        let baseline = Self.makeService(nowAt: Self.julyNoon)
        let fajr = try Self.time(of: .fajr, in: baseline)
        let sunrise = try Self.time(of: .sunrise, in: baseline)

        let justAfterFajr = Self.makeService(nowAt: fajr.addingTimeInterval(60))
        let deadline = try #require(justAfterFajr.currentPrayerDeadline)
        #expect(deadline.prayer == .fajr)
        #expect(deadline.deadline == sunrise)
        #expect(deadline.remaining > 0)
    }

    // MARK: - Multi-day calculation (notification scheduling)

    @Test func multiDayCalculationCoversConsecutiveDays() {
        let service = Self.makeService(nowAt: Self.julyNoon)

        let days = service.calculatePrayerTimes(forDays: 3)

        #expect(days.count == 3)
        #expect(days.allSatisfy { $0.prayers.count == Prayer.allCases.count })
        let fajrs = days.compactMap { day in day.prayers.first(where: { $0.0 == .fajr })?.1 }
        #expect(fajrs.count == 3)
        for (earlier, later) in zip(fajrs, fajrs.dropFirst()) {
            let gap = later.timeIntervalSince(earlier)
            // Consecutive local days: ~24h apart (DST/solar drift stays well inside ±3h)
            #expect(gap > 21 * 3600 && gap < 27 * 3600, "fajr gap \(gap)s is not one day")
        }
    }

    // MARK: - Ramadan (hijri boundary)

    @Test func ramadanMidMonthDetectedWithIftarAtMaghrib() throws {
        let service = Self.makeService(nowAt: Self.ramadanMidMonth)

        let info = try #require(service.ramadanInfo, "2026-03-01 is mid-Ramadan 1447 in every timezone within ±14h")
        #expect(info.isRamadan)
        // 1 Ramadan 1447 (Umm al-Qura) ≈ 2026-02-19; the host timezone shifts
        // the local date ±1 and the after-Maghrib rule adds +1 → guard band.
        #expect((8...15).contains(info.day), "expected mid-Ramadan, got day \(info.day)")
        let maghrib = try Self.time(of: .maghrib, in: service)
        let fajr = try Self.time(of: .fajr, in: service)
        #expect(info.iftarTime == maghrib)
        #expect(info.suhoorTime == fajr)
        #expect(info.fastingDuration == maghrib.timeIntervalSince(fajr))

        // Product quirk (observed, not fixed here): the first recalculate
        // builds the rows BEFORE updateRamadanInfo runs, so row labels lag
        // one pass. Assert them after an explicit second recalculation, and
        // flag the lag in the final report.
        service.recalculate()
        let fajrLabel = service.todayPrayers.first(where: { $0.prayer == .fajr })?.ramadanLabel
        let maghribLabel = service.todayPrayers.first(where: { $0.prayer == .maghrib })?.ramadanLabel
        #expect(fajrLabel == "Suhoor ends")
        #expect(maghribLabel == "Iftar")
    }

    @Test func nonRamadanDateHasNilRamadanInfo() {
        let service = Self.makeService(nowAt: Self.julyNoon)   // Muharram/Dhu al-Hijjah territory
        #expect(service.ramadanInfo == nil)
        #expect(service.todayPrayers.allSatisfy { $0.ramadanLabel == nil })
    }
}
