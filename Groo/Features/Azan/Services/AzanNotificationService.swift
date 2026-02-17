//
//  AzanNotificationService.swift
//  Groo
//
//  Schedules local notifications for prayer times.
//  Uses UNCalendarNotificationTrigger with Time Sensitive interruption level.
//

import Foundation
import UserNotifications

@MainActor
@Observable
class AzanNotificationService {
    private(set) var pendingCount: Int = 0
    private(set) var isAuthorized = false

    private let center = UNUserNotificationCenter.current()
    private let maxNotifications = 60
    private let daysAhead = 12

    // MARK: - Authorization

    func requestAuthorization() async -> Bool {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge, .timeSensitive])
            isAuthorized = granted
            return granted
        } catch {
            print("[AzanNotification] Authorization failed: \(error)")
            return false
        }
    }

    func checkAuthorization() async {
        let settings = await center.notificationSettings()
        isAuthorized = settings.authorizationStatus == .authorized
    }

    // MARK: - Registration

    func registerCategory() {
        let category = UNNotificationCategory(
            identifier: "AZAN_PRAYER",
            actions: [],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        center.setNotificationCategories([category])
    }

    // MARK: - Scheduling

    func scheduleNotifications(
        prayerService: PrayerTimeService,
        preferences: LocalAzanPreferences
    ) async {
        if !isAuthorized {
            let granted = await requestAuthorization()
            guard granted else { return }
        }

        // Remove existing azan notifications
        await removeAllAzanNotifications()

        let allDays = prayerService.calculatePrayerTimes(forDays: daysAhead)
        var scheduled = 0

        for dayEntry in allDays {
            for (prayer, time) in dayEntry.prayers {
                guard scheduled < maxNotifications else { break }
                guard time > Date() else { continue }
                guard preferences.isNotificationEnabled(for: prayer) else { continue }

                let content = buildContent(for: prayer, time: time, preferences: preferences, date: dayEntry.date)
                let trigger = buildTrigger(for: time)

                let id = "azan_\(prayer.rawValue)_\(Int(time.timeIntervalSince1970))"
                let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)

                do {
                    try await center.add(request)
                    scheduled += 1
                } catch {
                    print("[AzanNotification] Failed to schedule \(prayer.rawValue): \(error)")
                }
            }
        }

        // Schedule Jumu'ah reminder if enabled
        if preferences.jumuahReminderEnabled {
            if let reminderTime = prayerService.jumuahReminderTime(minutesBefore: preferences.jumuahReminderMinutes),
               reminderTime > Date(),
               scheduled < maxNotifications {
                let content = UNMutableNotificationContent()
                content.title = "Jumu'ah Reminder"
                content.body = "Friday prayer is in \(preferences.jumuahReminderMinutes) minutes"
                content.sound = .default
                content.categoryIdentifier = "AZAN_PRAYER"
                content.interruptionLevel = .timeSensitive
                content.userInfo = ["action": "azan", "prayer": "jumuah"]

                let trigger = buildTrigger(for: reminderTime)
                let id = "azan_jumuah_\(Int(reminderTime.timeIntervalSince1970))"
                let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
                try? await center.add(request)
                scheduled += 1
            }
        }

        // Schedule Suhoor reminders during Ramadan
        if preferences.suhoorReminderEnabled {
            for dayEntry in allDays {
                guard scheduled < maxNotifications else { break }

                // Suhoor is before Fajr, so check the Hijri date of the day itself.
                // Also check the previous evening (day - 1 after Maghrib → next Hijri day)
                // to catch the first Suhoor of Ramadan.
                let islamicCal = Calendar(identifier: .islamicUmmAlQura)
                let hijriMonth = islamicCal.component(.month, from: dayEntry.date)
                let prevDayHijriMonth: Int = {
                    guard let prev = Calendar.current.date(byAdding: .day, value: -1, to: dayEntry.date) else { return 0 }
                    return islamicCal.component(.month, from: prev)
                }()
                // Include if this day is Ramadan, or if yesterday was the last day
                // of Sha'ban (meaning tonight after Maghrib is Ramadan 1)
                guard hijriMonth == 9 || (prevDayHijriMonth == 8 && hijriMonth == 9) else { continue }

                if let suhoorTime = prayerService.suhoorReminderTime(
                    forDate: dayEntry.date,
                    minutesBefore: preferences.suhoorReminderMinutes
                ), suhoorTime > Date() {
                    let content = UNMutableNotificationContent()
                    content.title = "Suhoor Reminder"
                    content.body = "Suhoor ends in \(preferences.suhoorReminderMinutes) minutes"
                    content.sound = .default
                    content.categoryIdentifier = "AZAN_PRAYER"
                    content.interruptionLevel = .timeSensitive
                    content.userInfo = ["action": "azan", "prayer": "suhoor"]

                    let trigger = buildTrigger(for: suhoorTime)
                    let id = "azan_suhoor_\(Int(suhoorTime.timeIntervalSince1970))"
                    let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
                    try? await center.add(request)
                    scheduled += 1
                }
            }
        }

        pendingCount = scheduled
        print("[AzanNotification] Scheduled \(scheduled) notifications")
    }

    func removeAllAzanNotifications() async {
        let pending = await center.pendingNotificationRequests()
        let azanIds = pending.filter { $0.identifier.hasPrefix("azan_") }.map(\.identifier)
        center.removePendingNotificationRequests(withIdentifiers: azanIds)
        pendingCount = 0
    }

    func updatePendingCount() async {
        let pending = await center.pendingNotificationRequests()
        pendingCount = pending.filter { $0.identifier.hasPrefix("azan_") }.count
    }

    // MARK: - Private

    private func buildContent(
        for prayer: Prayer,
        time: Date,
        preferences: LocalAzanPreferences,
        date: Date
    ) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = prayer.displayName
        content.body = "It's time for \(prayer.displayName) prayer"
        content.categoryIdentifier = "AZAN_PRAYER"
        content.interruptionLevel = .timeSensitive
        content.userInfo = [
            "action": "azan",
            "prayer": prayer.rawValue,
            "timestamp": Int(time.timeIntervalSince1970),
        ]

        // Use custom sound if available (notification clips are named <sound>_clip.caf)
        let soundName = prayer == .fajr ? preferences.fajrAzanSound : preferences.azanSound
        if soundName != "default" {
            let clipFile = "\(soundName)_clip.caf"
            content.sound = UNNotificationSound(named: UNNotificationSoundName(rawValue: clipFile))
        } else {
            content.sound = .default
        }

        return content
    }

    private func buildTrigger(for date: Date) -> UNCalendarNotificationTrigger {
        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: date
        )
        return UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
    }
}
