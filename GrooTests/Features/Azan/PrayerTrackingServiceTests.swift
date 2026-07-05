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
}
