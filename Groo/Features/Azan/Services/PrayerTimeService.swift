//
//  PrayerTimeService.swift
//  Groo
//
//  Wraps adhan-swift for prayer time calculation.
//  Provides today's prayers, next prayer countdown, and Ramadan detection.
//

import Adhan
import Foundation

@MainActor
@Observable
class PrayerTimeService {
    private(set) var todayPrayers: [PrayerTimeEntry] = []
    private(set) var nextPrayer: PrayerCountdown?
    private(set) var ramadanInfo: RamadanInfo?

    private var countdownTimer: Timer?
    private var currentCoordinates: Coordinates?
    private var currentParams: CalculationParameters?
    private var preferences: LocalAzanPreferences?

    // MARK: - Configuration

    func configure(latitude: Double, longitude: Double, preferences: LocalAzanPreferences) {
        self.preferences = preferences
        currentCoordinates = Coordinates(latitude: latitude, longitude: longitude)
        currentParams = buildParams(from: preferences)
        recalculate()
        startCountdownTimer()
    }

    // MARK: - Calculation

    func recalculate() {
        guard let coords = currentCoordinates, let params = currentParams else { return }

        let cal = Calendar.current
        let today = cal.dateComponents([.year, .month, .day], from: Date())

        guard let prayerTimes = PrayerTimes(coordinates: coords, date: today, calculationParameters: params) else {
            return
        }

        let now = Date()
        let nextAdhanPrayer = prayerTimes.nextPrayer(at: now)

        todayPrayers = Prayer.allCases
            .filter { preferences?.isVisible(prayer: $0) ?? ($0 != .sunset) }
            .map { prayer in
                let time = adjustedTime(for: prayer, from: prayerTimes)
                let isNext = matchesPrayer(prayer, adhanPrayer: nextAdhanPrayer)
                let isPassed = time < now && !isNext
                let isFriday = cal.component(.weekday, from: now) == 6

                return PrayerTimeEntry(
                    prayer: prayer,
                    time: time,
                    isNext: isNext,
                    isPassed: isPassed,
                    notificationEnabled: preferences?.isNotificationEnabled(for: prayer) ?? false,
                    adjustment: preferences?.adjustment(for: prayer) ?? 0,
                    fridayLabel: (prayer == .dhuhr && isFriday) ? "Jumu'ah" : nil,
                    ramadanLabel: ramadanLabel(for: prayer)
                )
            }

        updateNextPrayer(prayerTimes: prayerTimes, now: now)
        updateRamadanInfo(prayerTimes: prayerTimes)
    }

    // MARK: - Multi-Day Calculation (for notifications)

    func calculatePrayerTimes(forDays days: Int) -> [(date: Date, prayers: [(Prayer, Date)])] {
        guard let coords = currentCoordinates, let params = currentParams else { return [] }

        let cal = Calendar.current
        var results: [(date: Date, prayers: [(Prayer, Date)])] = []

        for dayOffset in 0..<days {
            guard let date = cal.date(byAdding: .day, value: dayOffset, to: Date()) else { continue }
            let components = cal.dateComponents([.year, .month, .day], from: date)
            guard let prayerTimes = PrayerTimes(coordinates: coords, date: components, calculationParameters: params) else { continue }

            let prayers: [(Prayer, Date)] = Prayer.allCases.map { prayer in
                (prayer, adjustedTime(for: prayer, from: prayerTimes))
            }
            results.append((date: date, prayers: prayers))
        }

        return results
    }

    // MARK: - Jumu'ah Reminder Time

    func jumuahReminderTime(minutesBefore: Int) -> Date? {
        guard let coords = currentCoordinates, let params = currentParams else { return nil }
        let cal = Calendar.current

        // Find next Friday
        var date = Date()
        while cal.component(.weekday, from: date) != 6 {
            guard let next = cal.date(byAdding: .day, value: 1, to: date) else { return nil }
            date = next
        }

        let components = cal.dateComponents([.year, .month, .day], from: date)
        guard let prayerTimes = PrayerTimes(coordinates: coords, date: components, calculationParameters: params) else { return nil }

        let dhuhrTime = adjustedTime(for: .dhuhr, from: prayerTimes)
        return cal.date(byAdding: .minute, value: -minutesBefore, to: dhuhrTime)
    }

    // MARK: - Suhoor Reminder Time

    func suhoorReminderTime(forDate date: Date, minutesBefore: Int) -> Date? {
        guard let coords = currentCoordinates, let params = currentParams else { return nil }
        let cal = Calendar.current
        let components = cal.dateComponents([.year, .month, .day], from: date)
        guard let prayerTimes = PrayerTimes(coordinates: coords, date: components, calculationParameters: params) else { return nil }

        let fajrTime = adjustedTime(for: .fajr, from: prayerTimes)
        return cal.date(byAdding: .minute, value: -minutesBefore, to: fajrTime)
    }

    // MARK: - Private

    private func buildParams(from prefs: LocalAzanPreferences) -> CalculationParameters {
        var params: CalculationParameters
        switch prefs.parsedCalculationMethod {
        case .muslimWorldLeague: params = CalculationMethod.muslimWorldLeague.params
        case .egyptian: params = CalculationMethod.egyptian.params
        case .karachi: params = CalculationMethod.karachi.params
        case .ummAlQura: params = CalculationMethod.ummAlQura.params
        case .dubai: params = CalculationMethod.dubai.params
        case .moonsightingCommittee: params = CalculationMethod.moonsightingCommittee.params
        case .northAmerica: params = CalculationMethod.northAmerica.params
        case .kuwait: params = CalculationMethod.kuwait.params
        case .qatar: params = CalculationMethod.qatar.params
        case .singapore: params = CalculationMethod.singapore.params
        case .tehran: params = CalculationMethod.tehran.params
        case .turkey: params = CalculationMethod.turkey.params
        }

        switch prefs.parsedMadhab {
        case .shafi: params.madhab = .shafi
        case .hanafi: params.madhab = .hanafi
        }

        return params
    }

    private func adjustedTime(for prayer: Prayer, from prayerTimes: PrayerTimes) -> Date {
        let baseTime: Date
        switch prayer {
        case .fajr: baseTime = prayerTimes.fajr
        case .sunrise: baseTime = prayerTimes.sunrise
        case .dhuhr: baseTime = prayerTimes.dhuhr
        case .asr: baseTime = prayerTimes.asr
        case .sunset: baseTime = prayerTimes.maghrib  // Sunset = Maghrib astronomically
        case .maghrib: baseTime = prayerTimes.maghrib
        case .isha: baseTime = prayerTimes.isha
        }

        let adjustment = preferences?.adjustment(for: prayer) ?? 0
        if adjustment != 0 {
            return Calendar.current.date(byAdding: .minute, value: adjustment, to: baseTime) ?? baseTime
        }
        return baseTime
    }

    private func matchesPrayer(_ prayer: Prayer, adhanPrayer: Adhan.Prayer?) -> Bool {
        guard let adhanPrayer else { return false }
        switch (prayer, adhanPrayer) {
        case (.fajr, .fajr): return true
        case (.sunrise, .sunrise): return true
        case (.dhuhr, .dhuhr): return true
        case (.asr, .asr): return true
        case (.sunset, .maghrib): return true
        case (.maghrib, .maghrib): return true
        case (.isha, .isha): return true
        default: return false
        }
    }

    private func updateNextPrayer(prayerTimes: PrayerTimes, now: Date) {
        guard let adhanNext = prayerTimes.nextPrayer(at: now) else {
            // All prayers passed today, calculate tomorrow's Fajr
            let cal = Calendar.current
            guard let tomorrow = cal.date(byAdding: .day, value: 1, to: now),
                  let coords = currentCoordinates,
                  let params = currentParams else {
                nextPrayer = nil
                return
            }
            let components = cal.dateComponents([.year, .month, .day], from: tomorrow)
            if let tomorrowTimes = PrayerTimes(coordinates: coords, date: components, calculationParameters: params) {
                let fajrTime = adjustedTime(for: .fajr, from: tomorrowTimes)
                nextPrayer = PrayerCountdown(
                    prayer: .fajr,
                    time: fajrTime,
                    remaining: fajrTime.timeIntervalSince(now)
                )
            }
            return
        }

        let prayer = mapAdhanPrayer(adhanNext)
        let time = adjustedTime(for: prayer, from: prayerTimes)
        nextPrayer = PrayerCountdown(
            prayer: prayer,
            time: time,
            remaining: max(0, time.timeIntervalSince(now))
        )
    }

    private func mapAdhanPrayer(_ adhanPrayer: Adhan.Prayer) -> Prayer {
        switch adhanPrayer {
        case .fajr: .fajr
        case .sunrise: .sunrise
        case .dhuhr: .dhuhr
        case .asr: .asr
        case .maghrib: .maghrib
        case .isha: .isha
        }
    }

    private func updateRamadanInfo(prayerTimes: PrayerTimes) {
        let islamicCal = Calendar(identifier: .islamicUmmAlQura)
        let gregorianCal = Calendar.current
        let now = Date()
        let maghribTime = adjustedTime(for: .maghrib, from: prayerTimes)
        let fajrTime = adjustedTime(for: .fajr, from: prayerTimes)
        let isAfterMaghrib = now >= maghribTime

        // iOS uses midnight for Islamic day boundaries, but the Islamic day
        // actually starts at Maghrib. After Maghrib we check tomorrow's Hijri
        // date to match the religious reality.
        let hijriBase: Date
        if isAfterMaghrib, let tomorrow = gregorianCal.date(byAdding: .day, value: 1, to: now) {
            hijriBase = tomorrow
        } else {
            hijriBase = now
        }

        // Apply user's hijri date adjustment to match local moon sighting
        let hijriAdjustment = preferences?.hijriDateAdjustment ?? 0
        let hijriCheckDate = gregorianCal.date(byAdding: .day, value: hijriAdjustment, to: hijriBase) ?? hijriBase

        let hijriComponents = islamicCal.dateComponents([.month, .day, .year], from: hijriCheckDate)

        guard hijriComponents.month == 9 else {
            ramadanInfo = nil
            return
        }

        let daysInMonth = islamicCal.range(of: .day, in: .month, for: hijriCheckDate)?.count ?? 30

        ramadanInfo = RamadanInfo(
            isRamadan: true,
            day: hijriComponents.day ?? 1,
            totalDays: daysInMonth,
            suhoorTime: fajrTime,
            iftarTime: maghribTime,
            fastingDuration: maghribTime.timeIntervalSince(fajrTime)
        )
    }

    private func ramadanLabel(for prayer: Prayer) -> String? {
        guard ramadanInfo?.isRamadan == true else { return nil }
        switch prayer {
        case .fajr: return "Suhoor ends"
        case .maghrib: return "Iftar"
        default: return nil
        }
    }

    // MARK: - Timer

    private func startCountdownTimer() {
        countdownTimer?.invalidate()
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tickCountdown()
            }
        }
    }

    private func tickCountdown() {
        guard let current = nextPrayer else { return }
        let remaining = current.time.timeIntervalSince(Date())
        if remaining <= 0 {
            recalculate()
        } else {
            nextPrayer = PrayerCountdown(
                prayer: current.prayer,
                time: current.time,
                remaining: remaining
            )
        }
    }

    nonisolated deinit {
        // Timer is invalidated when the service is deallocated
        // MainActor-isolated property cannot be accessed in deinit
    }
}
