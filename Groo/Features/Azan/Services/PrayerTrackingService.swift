//
//  PrayerTrackingService.swift
//  Groo
//
//  Analytics service for prayer tracking: streaks, weekly stats, per-prayer breakdown.
//

import Foundation
import SwiftUI

struct DaySummary: Identifiable {
    let dateString: String
    let completedCount: Int
    let onTimeCount: Int
    let lateCount: Int

    var id: String { dateString }
    var totalRequired: Int { 5 }
    var isFull: Bool { completedCount == totalRequired }
}

struct PrayerStat: Identifiable {
    let prayer: Prayer
    let onTimeCount: Int
    let lateCount: Int
    let totalDays: Int

    var id: String { prayer.rawValue }
    var totalLogged: Int { onTimeCount + lateCount }
    var onTimePercent: Double { totalDays > 0 ? Double(onTimeCount) / Double(totalDays) : 0 }
    var latePercent: Double { totalDays > 0 ? Double(lateCount) / Double(totalDays) : 0 }
}

@MainActor
@Observable
class PrayerTrackingService {
    private(set) var todayLogs: [Prayer: PrayerStatus] = [:]
    private(set) var todayCompletedCount: Int = 0
    let todayRequiredCount: Int = 5

    private(set) var currentStreak: Int = 0
    private(set) var bestStreak: Int = 0

    private(set) var weeklyGrid: [DaySummary] = []
    private(set) var perPrayerStats: [PrayerStat] = []
    private(set) var thisWeekPercent: Double = 0
    private(set) var thisMonthPercent: Double = 0
    private(set) var onTimeRate: Double = 0
    private(set) var totalPrayersLogged: Int = 0

    private let store: LocalStore
    private let trackablePrayers: [Prayer] = Prayer.notifiable

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    init(store: LocalStore = .shared) {
        self.store = store
    }

    // MARK: - Public API

    func logPrayer(dateString: String, prayer: Prayer, status: PrayerStatus) {
        let log = PrayerLog(dateString: dateString, prayer: prayer, status: status)
        store.savePrayerLog(log)
        recalculate()
    }

    func removePrayerLog(dateString: String, prayer: Prayer) {
        store.deletePrayerLog(dateString: dateString, prayer: prayer)
        recalculate()
    }

    func recalculate() {
        let today = Self.dateFormatter.string(from: Date())
        loadTodayLogs(today)
        calculateStreaks(from: today)
        calculateWeeklyGrid(from: today)
        calculatePerPrayerStats(from: today)
        calculateOverallStats(from: today)
    }

    func todayDateString() -> String {
        Self.dateFormatter.string(from: Date())
    }

    func logsForMonth(year: Int, month: Int) -> [String: [Prayer: PrayerStatus]] {
        let startDate = String(format: "%04d-%02d-01", year, month)
        let endDate = String(format: "%04d-%02d-31", year, month)
        let logs = store.getPrayerLogs(from: startDate, to: endDate)

        var result: [String: [Prayer: PrayerStatus]] = [:]
        for log in logs {
            var dayLogs = result[log.dateString, default: [:]]
            dayLogs[log.prayer] = log.status
            result[log.dateString] = dayLogs
        }
        return result
    }

    // MARK: - Private

    private func loadTodayLogs(_ today: String) {
        let logs = store.getPrayerLogs(forDateString: today)
        var map: [Prayer: PrayerStatus] = [:]
        for log in logs {
            map[log.prayer] = log.status
        }
        todayLogs = map
        todayCompletedCount = map.count
    }

    private func calculateStreaks(from today: String) {
        let calendar = Calendar.current
        guard let todayDate = Self.dateFormatter.date(from: today) else { return }

        var current = 0
        var best = 0
        var streak = 0
        var dayOffset = 0

        while true {
            guard let date = calendar.date(byAdding: .day, value: -dayOffset, to: todayDate) else { break }
            let ds = Self.dateFormatter.string(from: date)
            let logs = store.getPrayerLogs(forDateString: ds)

            let prayerSet = Set(logs.map { $0.prayer })
            let allFiveDone = trackablePrayers.allSatisfy { prayerSet.contains($0) }

            if allFiveDone {
                streak += 1
            } else {
                if dayOffset == 0 {
                    // Today incomplete doesn't break streak yet — check yesterday
                    dayOffset += 1
                    continue
                }
                break
            }

            dayOffset += 1

            // Safety: don't walk back more than ~10 years
            if dayOffset > 3650 { break }
        }

        current = streak

        // Best streak: scan last 365 days
        streak = 0
        best = current
        for offset in 0..<365 {
            guard let date = calendar.date(byAdding: .day, value: -offset, to: todayDate) else { break }
            let ds = Self.dateFormatter.string(from: date)
            let logs = store.getPrayerLogs(forDateString: ds)

            let prayerSet = Set(logs.map { $0.prayer })
            let allFiveDone = trackablePrayers.allSatisfy { prayerSet.contains($0) }

            if allFiveDone {
                streak += 1
                best = max(best, streak)
            } else {
                streak = 0
            }
        }

        currentStreak = current
        bestStreak = best
    }

    private func calculateWeeklyGrid(from today: String) {
        let calendar = Calendar.current
        guard let todayDate = Self.dateFormatter.date(from: today) else { return }

        var grid: [DaySummary] = []
        for offset in (0..<7).reversed() {
            guard let date = calendar.date(byAdding: .day, value: -offset, to: todayDate) else { continue }
            let ds = Self.dateFormatter.string(from: date)
            let logs = store.getPrayerLogs(forDateString: ds)

            let onTime = logs.filter { $0.status == .onTime }.count
            let late = logs.filter { $0.status == .late }.count
            grid.append(DaySummary(dateString: ds, completedCount: onTime + late, onTimeCount: onTime, lateCount: late))
        }
        weeklyGrid = grid
    }

    private func calculatePerPrayerStats(from today: String) {
        let calendar = Calendar.current
        guard let todayDate = Self.dateFormatter.date(from: today) else { return }
        guard let thirtyDaysAgo = calendar.date(byAdding: .day, value: -29, to: todayDate) else { return }

        let startDate = Self.dateFormatter.string(from: thirtyDaysAgo)
        let logs = store.getPrayerLogs(from: startDate, to: today)

        var stats: [PrayerStat] = []
        for prayer in trackablePrayers {
            let prayerLogs = logs.filter { $0.prayer == prayer }
            let onTime = prayerLogs.filter { $0.status == .onTime }.count
            let late = prayerLogs.filter { $0.status == .late }.count
            stats.append(PrayerStat(prayer: prayer, onTimeCount: onTime, lateCount: late, totalDays: 30))
        }
        perPrayerStats = stats
    }

    private func calculateOverallStats(from today: String) {
        let calendar = Calendar.current
        guard let todayDate = Self.dateFormatter.date(from: today) else { return }

        // This week (last 7 days)
        let weekTotal = weeklyGrid.reduce(0) { $0 + $1.completedCount }
        thisWeekPercent = Double(weekTotal) / Double(7 * 5) * 100

        // This month
        guard let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: todayDate)) else { return }
        let dayOfMonth = calendar.component(.day, from: todayDate)
        let monthStart = Self.dateFormatter.string(from: startOfMonth)
        let monthLogs = store.getPrayerLogs(from: monthStart, to: today)
        let monthTotal = monthLogs.count
        thisMonthPercent = Double(monthTotal) / Double(dayOfMonth * 5) * 100

        // On-time rate (last 30 days)
        guard let thirtyDaysAgo = calendar.date(byAdding: .day, value: -29, to: todayDate) else { return }
        let startDate = Self.dateFormatter.string(from: thirtyDaysAgo)
        let allLogs = store.getPrayerLogs(from: startDate, to: today)
        totalPrayersLogged = allLogs.count
        let onTimeLogs = allLogs.filter { $0.status == .onTime }.count
        onTimeRate = allLogs.isEmpty ? 0 : Double(onTimeLogs) / Double(allLogs.count) * 100
    }
}
