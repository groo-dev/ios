//
//  AzanWidget.swift
//  WidgetExtension
//
//  Prayer times widget showing next prayer countdown,
//  today's prayer times, and current prayer deadline.
//

import Adhan
import SwiftUI
import WidgetKit

// MARK: - Widget Entry

struct AzanWidgetEntry: TimelineEntry {
    let date: Date
    let prayerTimes: [AzanWidgetPrayer]
    let nextPrayer: AzanWidgetPrayer?
    let currentDeadline: AzanWidgetDeadline?
    let isConfigured: Bool
}

struct AzanWidgetPrayer: Identifiable {
    let name: String
    let time: Date
    let isNext: Bool
    let icon: String

    var id: String { name }

    var formattedTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: time)
    }
}

struct AzanWidgetDeadline {
    let prayerName: String
    let deadline: Date

    func formattedRemaining(from now: Date) -> String {
        let remaining = max(0, deadline.timeIntervalSince(now))
        let hours = Int(remaining) / 3600
        let minutes = (Int(remaining) % 3600) / 60
        let seconds = Int(remaining) % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
}

// MARK: - Timeline Provider

struct AzanWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> AzanWidgetEntry {
        AzanWidgetEntry(
            date: Date(),
            prayerTimes: Self.placeholderPrayers(),
            nextPrayer: Self.placeholderPrayers().first,
            currentDeadline: nil,
            isConfigured: true
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (AzanWidgetEntry) -> Void) {
        let entry = buildEntry(at: Date())
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<AzanWidgetEntry>) -> Void) {
        let now = Date()
        let entry = buildEntry(at: now)

        // Refresh at the next prayer time or in 15 minutes
        let nextRefresh: Date
        if let nextPrayer = entry.nextPrayer {
            nextRefresh = nextPrayer.time
        } else {
            nextRefresh = Calendar.current.date(byAdding: .minute, value: 15, to: now)!
        }

        let timeline = Timeline(entries: [entry], policy: .after(nextRefresh))
        completion(timeline)
    }

    // MARK: - Build Entry

    private func buildEntry(at date: Date) -> AzanWidgetEntry {
        let prefs = loadPreferences()

        guard prefs.latitude != 0 || prefs.longitude != 0 else {
            return AzanWidgetEntry(
                date: date,
                prayerTimes: [],
                nextPrayer: nil,
                currentDeadline: nil,
                isConfigured: false
            )
        }

        let coords = Coordinates(latitude: prefs.latitude, longitude: prefs.longitude)
        let cal = Calendar.current
        let todayComponents = cal.dateComponents([.year, .month, .day], from: date)

        guard let prayerTimes = PrayerTimes(coordinates: coords, date: todayComponents, calculationParameters: prefs.params) else {
            return AzanWidgetEntry(date: date, prayerTimes: [], nextPrayer: nil, currentDeadline: nil, isConfigured: true)
        }

        let adhanNext = prayerTimes.nextPrayer(at: date)

        let prayerList: [(String, Date, String, Adhan.Prayer)] = [
            ("Fajr", adjusted(prayerTimes.fajr, by: prefs.fajrAdj), "sun.horizon", .fajr),
            ("Dhuhr", adjusted(prayerTimes.dhuhr, by: prefs.dhuhrAdj), "sun.max", .dhuhr),
            ("Asr", adjusted(prayerTimes.asr, by: prefs.asrAdj), "sun.min", .asr),
            ("Maghrib", adjusted(prayerTimes.maghrib, by: prefs.maghribAdj), "moon.haze", .maghrib),
            ("Isha", adjusted(prayerTimes.isha, by: prefs.ishaAdj), "moon.stars", .isha),
        ]

        var widgetPrayers: [AzanWidgetPrayer] = []
        var nextWidgetPrayer: AzanWidgetPrayer?

        for (name, time, icon, adhanPrayer) in prayerList {
            let isNext = adhanPrayer == adhanNext
            let wp = AzanWidgetPrayer(name: name, time: time, isNext: isNext, icon: icon)
            widgetPrayers.append(wp)
            if isNext {
                nextWidgetPrayer = wp
            }
        }

        // If no next prayer today, tomorrow's Fajr is next
        if nextWidgetPrayer == nil {
            if let tomorrow = cal.date(byAdding: .day, value: 1, to: date) {
                let tomorrowComponents = cal.dateComponents([.year, .month, .day], from: tomorrow)
                if let tomorrowTimes = PrayerTimes(coordinates: coords, date: tomorrowComponents, calculationParameters: prefs.params) {
                    let fajrTime = adjusted(tomorrowTimes.fajr, by: prefs.fajrAdj)
                    nextWidgetPrayer = AzanWidgetPrayer(name: "Fajr", time: fajrTime, isNext: true, icon: "sun.horizon")
                }
            }
        }

        // Current prayer deadline
        var currentDeadline: AzanWidgetDeadline?
        let cutoffMap: [(String, Date, Date)] = [
            ("Fajr", adjusted(prayerTimes.fajr, by: prefs.fajrAdj), prayerTimes.sunrise),
            ("Dhuhr", adjusted(prayerTimes.dhuhr, by: prefs.dhuhrAdj), adjusted(prayerTimes.asr, by: prefs.asrAdj)),
            ("Asr", adjusted(prayerTimes.asr, by: prefs.asrAdj), adjusted(prayerTimes.maghrib, by: prefs.maghribAdj)),
            ("Maghrib", adjusted(prayerTimes.maghrib, by: prefs.maghribAdj), adjusted(prayerTimes.isha, by: prefs.ishaAdj)),
        ]

        for (name, start, cutoff) in cutoffMap.reversed() {
            if date >= start && date < cutoff {
                currentDeadline = AzanWidgetDeadline(prayerName: name, deadline: cutoff)
                break
            }
        }

        // Isha: active after isha start, cutoff is tomorrow's fajr
        if currentDeadline == nil {
            let ishaStart = adjusted(prayerTimes.isha, by: prefs.ishaAdj)
            if date >= ishaStart {
                if let tomorrow = cal.date(byAdding: .day, value: 1, to: date) {
                    let tomorrowComponents = cal.dateComponents([.year, .month, .day], from: tomorrow)
                    if let tomorrowTimes = PrayerTimes(coordinates: coords, date: tomorrowComponents, calculationParameters: prefs.params) {
                        let cutoff = adjusted(tomorrowTimes.fajr, by: prefs.fajrAdj)
                        currentDeadline = AzanWidgetDeadline(prayerName: "Isha", deadline: cutoff)
                    }
                }
            }
        }

        return AzanWidgetEntry(
            date: date,
            prayerTimes: widgetPrayers,
            nextPrayer: nextWidgetPrayer,
            currentDeadline: currentDeadline,
            isConfigured: true
        )
    }

    // MARK: - Preferences

    private struct WidgetPrefs {
        let latitude: Double
        let longitude: Double
        let params: CalculationParameters
        let fajrAdj: Int
        let dhuhrAdj: Int
        let asrAdj: Int
        let maghribAdj: Int
        let ishaAdj: Int
    }

    private func loadPreferences() -> WidgetPrefs {
        let suiteName: String
        #if DEBUG
        suiteName = "group.dev.groo.ios.debug"
        #else
        suiteName = "group.dev.groo.ios"
        #endif

        let defaults = UserDefaults(suiteName: suiteName)

        let lat = defaults?.double(forKey: "azan_latitude") ?? 0
        let lon = defaults?.double(forKey: "azan_longitude") ?? 0
        let methodRaw = defaults?.string(forKey: "azan_calculationMethod") ?? "muslimWorldLeague"
        let madhabRaw = defaults?.string(forKey: "azan_madhab") ?? "hanafi"

        var params: CalculationParameters
        switch methodRaw {
        case "muslimWorldLeague": params = CalculationMethod.muslimWorldLeague.params
        case "egyptian": params = CalculationMethod.egyptian.params
        case "karachi": params = CalculationMethod.karachi.params
        case "ummAlQura": params = CalculationMethod.ummAlQura.params
        case "dubai": params = CalculationMethod.dubai.params
        case "moonsightingCommittee": params = CalculationMethod.moonsightingCommittee.params
        case "northAmerica": params = CalculationMethod.northAmerica.params
        case "kuwait": params = CalculationMethod.kuwait.params
        case "qatar": params = CalculationMethod.qatar.params
        case "singapore": params = CalculationMethod.singapore.params
        case "tehran": params = CalculationMethod.tehran.params
        case "turkey": params = CalculationMethod.turkey.params
        default: params = CalculationMethod.muslimWorldLeague.params
        }

        switch madhabRaw {
        case "hanafi": params.madhab = .hanafi
        default: params.madhab = .shafi
        }

        return WidgetPrefs(
            latitude: lat,
            longitude: lon,
            params: params,
            fajrAdj: defaults?.integer(forKey: "azan_fajrAdjustment") ?? 0,
            dhuhrAdj: defaults?.integer(forKey: "azan_dhuhrAdjustment") ?? 0,
            asrAdj: defaults?.integer(forKey: "azan_asrAdjustment") ?? 0,
            maghribAdj: defaults?.integer(forKey: "azan_maghribAdjustment") ?? 0,
            ishaAdj: defaults?.integer(forKey: "azan_ishaAdjustment") ?? 0
        )
    }

    // MARK: - Helpers

    private func adjusted(_ time: Date, by minutes: Int) -> Date {
        if minutes == 0 { return time }
        return Calendar.current.date(byAdding: .minute, value: minutes, to: time) ?? time
    }

    private static func placeholderPrayers() -> [AzanWidgetPrayer] {
        [
            AzanWidgetPrayer(name: "Fajr", time: Date(), isNext: false, icon: "sun.horizon"),
            AzanWidgetPrayer(name: "Dhuhr", time: Date(), isNext: true, icon: "sun.max"),
            AzanWidgetPrayer(name: "Asr", time: Date(), isNext: false, icon: "sun.min"),
            AzanWidgetPrayer(name: "Maghrib", time: Date(), isNext: false, icon: "moon.haze"),
            AzanWidgetPrayer(name: "Isha", time: Date(), isNext: false, icon: "moon.stars"),
        ]
    }
}

// MARK: - Widget Views

struct AzanWidgetView: View {
    @Environment(\.widgetFamily) var family
    var entry: AzanWidgetEntry

    var body: some View {
        if !entry.isConfigured {
            notConfiguredView
        } else {
            switch family {
            case .systemSmall:
                smallWidget
            case .systemMedium:
                mediumWidget
            case .systemLarge:
                largeWidget
            default:
                smallWidget
            }
        }
    }

    // MARK: - Not Configured

    private var notConfiguredView: some View {
        VStack(spacing: 8) {
            Image(systemName: "location.slash")
                .font(.title)
                .foregroundStyle(Color.brand)
            Text("Set Location")
                .font(.headline)
            Text("Open Groo to configure prayer times")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Small

    private var smallWidget: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "moon.stars.fill")
                    .foregroundStyle(Color.brand)
                Text("Prayer")
                    .font(.headline)
            }

            if let next = entry.nextPrayer {
                Spacer()

                Text(next.name)
                    .font(.title3.bold())

                Text(next.formattedTime)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(next.time, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(Color.brand)
            } else {
                Spacer()
                Text("No data")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    // MARK: - Medium

    private var mediumWidget: some View {
        HStack(spacing: 12) {
            // Next prayer (left)
            if let next = entry.nextPrayer {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Next")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    Text(next.name)
                        .font(.title3.bold())

                    Text(next.formattedTime)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(next.time, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(Color.brand)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()

            // All prayer times (right)
            VStack(alignment: .leading, spacing: 3) {
                ForEach(entry.prayerTimes) { prayer in
                    HStack {
                        Image(systemName: prayer.icon)
                            .font(.caption2)
                            .frame(width: 14)
                            .foregroundStyle(prayer.isNext ? Color.brand : .secondary)

                        Text(prayer.name)
                            .font(.caption2)
                            .fontWeight(prayer.isNext ? .bold : .regular)
                            .foregroundStyle(prayer.isNext ? .primary : .secondary)

                        Spacer()

                        Text(prayer.formattedTime)
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(prayer.isNext ? .primary : .secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding()
    }

    // MARK: - Large

    private var largeWidget: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Image(systemName: "moon.stars.fill")
                    .foregroundStyle(Color.brand)
                Text("Prayer Times")
                    .font(.headline)
                Spacer()
                Text(entry.date, style: .date)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Divider()

            // Prayer times list
            ForEach(entry.prayerTimes) { prayer in
                HStack {
                    Image(systemName: prayer.icon)
                        .font(.subheadline)
                        .frame(width: 20)
                        .foregroundStyle(prayer.isNext ? Color.brand : .secondary)

                    Text(prayer.name)
                        .font(.subheadline)
                        .fontWeight(prayer.isNext ? .semibold : .regular)

                    Spacer()

                    if prayer.isNext {
                        Text(prayer.time, style: .relative)
                            .font(.caption)
                            .foregroundStyle(Color.brand)
                    }

                    Text(prayer.formattedTime)
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(prayer.isNext ? .primary : .secondary)
                }
                .padding(.vertical, 2)

                if prayer.id != entry.prayerTimes.last?.id {
                    Divider()
                }
            }

            // Deadline
            if let deadline = entry.currentDeadline {
                Divider()

                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.circle")
                        .font(.caption2)
                    Text("\(deadline.prayerName) ends in")
                        .font(.caption)
                    Text(deadline.deadline, style: .relative)
                        .font(.caption)
                        .foregroundStyle(Color.brand)
                }
                .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding()
    }
}

// MARK: - Widget Configuration

struct AzanWidget: Widget {
    let kind: String = "AzanWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: AzanWidgetProvider()) { entry in
            AzanWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Prayer Times")
        .description("See upcoming prayer times and countdowns.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

#Preview(as: .systemSmall) {
    AzanWidget()
} timeline: {
    AzanWidgetEntry(
        date: .now,
        prayerTimes: [
            AzanWidgetPrayer(name: "Fajr", time: .now, isNext: false, icon: "sun.horizon"),
            AzanWidgetPrayer(name: "Dhuhr", time: .now.addingTimeInterval(3600), isNext: true, icon: "sun.max"),
        ],
        nextPrayer: AzanWidgetPrayer(name: "Dhuhr", time: .now.addingTimeInterval(3600), isNext: true, icon: "sun.max"),
        currentDeadline: nil,
        isConfigured: true
    )
}

#Preview(as: .systemMedium) {
    AzanWidget()
} timeline: {
    AzanWidgetEntry(
        date: .now,
        prayerTimes: [
            AzanWidgetPrayer(name: "Fajr", time: .now.addingTimeInterval(-7200), isNext: false, icon: "sun.horizon"),
            AzanWidgetPrayer(name: "Dhuhr", time: .now.addingTimeInterval(3600), isNext: true, icon: "sun.max"),
            AzanWidgetPrayer(name: "Asr", time: .now.addingTimeInterval(10800), isNext: false, icon: "sun.min"),
            AzanWidgetPrayer(name: "Maghrib", time: .now.addingTimeInterval(18000), isNext: false, icon: "moon.haze"),
            AzanWidgetPrayer(name: "Isha", time: .now.addingTimeInterval(25200), isNext: false, icon: "moon.stars"),
        ],
        nextPrayer: AzanWidgetPrayer(name: "Dhuhr", time: .now.addingTimeInterval(3600), isNext: true, icon: "sun.max"),
        currentDeadline: nil,
        isConfigured: true
    )
}
