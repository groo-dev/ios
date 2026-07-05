//
//  PrayerTrackingServiceTests.swift
//  GrooTests
//
//  Streaks, weekly grid, and stats over an in-memory LocalStore with an
//  injected fixed clock. Date strings are derived from the same fixed now
//  through the same formatter the service uses — timezone-independent.
//

import Foundation
import Testing
@testable import Groo

@MainActor
struct PrayerTrackingServiceTests {
    static let fixedNow = Date(timeIntervalSince1970: 1_751_700_000)   // 2025-07-05T07:20Z

    static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    static func dateString(daysAgo: Int) -> String {
        let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: fixedNow)!
        return formatter.string(from: date)
    }

    static func makeService() throws -> PrayerTrackingService {
        let store = try InMemoryLocalStore.make()
        return PrayerTrackingService(store: store, now: { Self.fixedNow })
    }

    static func logFullDay(_ service: PrayerTrackingService, daysAgo: Int, status: PrayerStatus = .onTime) {
        for prayer in Prayer.notifiable {
            service.logPrayer(dateString: Self.dateString(daysAgo: daysAgo), prayer: prayer, status: status)
        }
    }

    @Test func loggingUpdatesTodayCountsAndUpserts() throws {
        let service = try Self.makeService()

        service.logPrayer(dateString: Self.dateString(daysAgo: 0), prayer: .fajr, status: .onTime)
        service.logPrayer(dateString: Self.dateString(daysAgo: 0), prayer: .fajr, status: .late)
        service.logPrayer(dateString: Self.dateString(daysAgo: 0), prayer: .dhuhr, status: .onTime)

        #expect(service.todayCompletedCount == 2)          // fajr upserted, not duplicated
        #expect(service.todayLogs[.fajr] == .late)
        #expect(service.todayLogs[.dhuhr] == .onTime)
        #expect(service.todayDateString() == Self.dateString(daysAgo: 0))
    }

    @Test func incompleteTodayDoesNotBreakTheStreak() throws {
        let service = try Self.makeService()
        Self.logFullDay(service, daysAgo: 2)
        Self.logFullDay(service, daysAgo: 1)
        // Nothing logged today — the day isn't over yet

        #expect(service.currentStreak == 2)
    }

    @Test func fullTodayExtendsTheStreak() throws {
        let service = try Self.makeService()
        Self.logFullDay(service, daysAgo: 1)
        Self.logFullDay(service, daysAgo: 0)

        #expect(service.currentStreak == 2)
        #expect(service.bestStreak == 2)
    }

    @Test func gapBreaksCurrentStreakButBestRemembers() throws {
        let service = try Self.makeService()
        Self.logFullDay(service, daysAgo: 5)
        Self.logFullDay(service, daysAgo: 4)
        Self.logFullDay(service, daysAgo: 3)
        // daysAgo 2: gap
        Self.logFullDay(service, daysAgo: 1)

        #expect(service.currentStreak == 1)
        #expect(service.bestStreak == 3)
    }

    @Test func weeklyGridCoversSevenDaysOldestFirst() throws {
        let service = try Self.makeService()
        service.logPrayer(dateString: Self.dateString(daysAgo: 6), prayer: .asr, status: .late)
        service.logPrayer(dateString: Self.dateString(daysAgo: 0), prayer: .fajr, status: .onTime)
        service.logPrayer(dateString: Self.dateString(daysAgo: 0), prayer: .dhuhr, status: .onTime)

        try #require(service.weeklyGrid.count == 7)
        #expect(service.weeklyGrid.first?.dateString == Self.dateString(daysAgo: 6))
        #expect(service.weeklyGrid.first?.lateCount == 1)
        #expect(service.weeklyGrid.first?.completedCount == 1)
        #expect(service.weeklyGrid.last?.dateString == Self.dateString(daysAgo: 0))
        #expect(service.weeklyGrid.last?.onTimeCount == 2)
        #expect(service.weeklyGrid.last?.isFull == false)
    }

    @Test func removingALogRecalculates() throws {
        let service = try Self.makeService()
        Self.logFullDay(service, daysAgo: 0)
        #expect(service.todayCompletedCount == 5)

        service.removePrayerLog(dateString: Self.dateString(daysAgo: 0), prayer: .isha)

        #expect(service.todayCompletedCount == 4)
        #expect(service.todayLogs[.isha] == nil)
    }

    @Test func onTimeRateAndWeekPercentAggregate() throws {
        let service = try Self.makeService()
        // Today: 4 on-time + 1 late = 5 of 35 possible this week
        for prayer in [Prayer.fajr, .dhuhr, .asr, .maghrib] {
            service.logPrayer(dateString: Self.dateString(daysAgo: 0), prayer: prayer, status: .onTime)
        }
        service.logPrayer(dateString: Self.dateString(daysAgo: 0), prayer: .isha, status: .late)

        #expect(service.totalPrayersLogged == 5)
        #expect(abs(service.onTimeRate - 80.0) < 0.0001)                    // 4/5
        #expect(abs(service.thisWeekPercent - (5.0 / 35.0 * 100)) < 0.0001)
    }

    // MARK: - Date-boundary sweep (Phase 6)

    static func makeService(now fixedNow: Date) throws -> PrayerTrackingService {
        let store = try InMemoryLocalStore.make()
        return PrayerTrackingService(store: store, now: { fixedNow })
    }

    static func dateString(daysAgo: Int, from now: Date) -> String {
        let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: now)!
        return formatter.string(from: date)
    }

    static func logFullDay(_ service: PrayerTrackingService, daysAgo: Int, from now: Date) {
        for prayer in Prayer.notifiable {
            service.logPrayer(dateString: Self.dateString(daysAgo: daysAgo, from: now),
                              prayer: prayer, status: .onTime)
        }
    }

    /// The streak walk crosses Dec 31 → Jan 1 via Calendar day arithmetic +
    /// string round-trips; an off-by-one at the year boundary breaks here.
    @Test func streakWalksAcrossTheYearBoundary() throws {
        let newYear = Date(timeIntervalSince1970: 1_767_268_800)   // 2026-01-01T12:00:00Z
        let service = try Self.makeService(now: newYear)

        for daysAgo in 0...2 { Self.logFullDay(service, daysAgo: daysAgo, from: newYear) }

        // In every timezone within ±14h these three days straddle the year
        // boundary (local "today" is Jan 1 or Jan 2)
        #expect(service.currentStreak == 3)
        #expect(service.bestStreak == 3)
    }

    @Test func weeklyGridIsSevenUniqueConsecutiveDaysAcrossLeapDay() throws {
        let afterLeap = Date(timeIntervalSince1970: 1_835_611_200)   // 2028-03-02T12:00:00Z
        let service = try Self.makeService(now: afterLeap)
        service.recalculate()

        let dates = service.weeklyGrid.map(\.dateString)
        #expect(dates.count == 7)
        #expect(Set(dates).count == 7, "grid duplicated a day: \(dates)")
        // Oldest-first, derived through the same calendar walk the service uses
        let expected = (0..<7).reversed().map { Self.dateString(daysAgo: $0, from: afterLeap) }
        #expect(dates == expected)
        // The 7-day window straddles the leap day for local "today" of
        // either Mar 2 or Mar 3 (every timezone within ±14h of UTC)
        #expect(dates.contains("2028-02-29"), "leap day missing from \(dates)")
    }

    /// US DST 2026 springs forward on Mar 8: local-midnight day arithmetic
    /// must neither skip nor duplicate a date string across the jump.
    @Test func streakSurvivesTheSpringForwardWeek() throws {
        let afterDst = Date(timeIntervalSince1970: 1_773_144_000)   // 2026-03-10T12:00:00Z
        let service = try Self.makeService(now: afterDst)

        for daysAgo in 0...4 { Self.logFullDay(service, daysAgo: daysAgo, from: afterDst) }

        let walked = (0...4).map { Self.dateString(daysAgo: $0, from: afterDst) }
        #expect(Set(walked).count == 5, "day walk skipped/duplicated a date: \(walked)")
        #expect(service.currentStreak == 5)
    }
}
