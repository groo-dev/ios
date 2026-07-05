//
//  AzanViewSnapshotTests.swift
//  GrooTests
//
//  Phase 7: render/snapshot coverage for the Azan views. Guide content is
//  static data (PrayerGuideDataProvider); tracker views run over a
//  fixed-clock PrayerTrackingService on an in-memory store. AzanView and
//  PrayerLogView are render-only (wall-clock countdowns / month walks).
//

import SnapshotTesting
import SwiftUI
import Testing
@testable import Groo

extension NetworkStubbedSuites {

@MainActor
@Suite(.serialized, .snapshots(record: .missing))
struct AzanViewSnapshotTests {
    static let baseTime = Date(timeIntervalSince1970: 1_700_000_000)
    static let hanafiDefaults: [String: Any] = [
        "prayerGuideMadhab": FiqhMadhab.hanafi.rawValue,
        "prayerGuideRole": PrayerRole.munfarid.rawValue,
        "prayerGuideTraveling": false,
        "prayerGuideQaza": false,
    ]

    static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static func entry(
        _ prayer: Prayer, isNext: Bool = false, isPassed: Bool = false, isCurrent: Bool = false,
        urgency: PrayerDeadline.Urgency? = nil, notif: Bool = true, adjustment: Int = 0,
        friday: String? = nil, ramadan: String? = nil
    ) -> PrayerTimeEntry {
        PrayerTimeEntry(prayer: prayer, time: baseTime, isNext: isNext, isPassed: isPassed,
                        isCurrent: isCurrent, currentUrgency: urgency, notificationEnabled: notif,
                        adjustment: adjustment, fridayLabel: friday, ramadanLabel: ramadan)
    }

    /// Fixed-clock tracking service with 4 seeded days (alternating
    /// on-time/late) — every derived stat is deterministic.
    static func seededTracking() throws -> PrayerTrackingService {
        let store = try InMemoryLocalStore.make()
        let now = Date(timeIntervalSince1970: 1_751_700_000)   // 2025-07-05T07:20Z (P6 fixture)
        let service = PrayerTrackingService(store: store, now: { now })
        for daysAgo in 0...3 {
            let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: now)!
            for prayer in Prayer.notifiable {
                service.logPrayer(dateString: Self.dayFormatter.string(from: date), prayer: prayer,
                                  status: daysAgo.isMultiple(of: 2) ? .onTime : .late)
            }
        }
        service.recalculate()
        return service
    }

    /// Pin LocalStore.shared's Azan preferences to a fixed manual location
    /// (Dubai) so AzanView neither prompts CoreLocation nor varies by
    /// machine; restores previous values after.
    static func withFixedAzanLocation(_ body: () throws -> Void) rethrows {
        let store = LocalStore.shared
        let prefs = store.getAzanPreferences() ?? LocalAzanPreferences()
        let saved = (prefs.useDeviceLocation, prefs.latitude, prefs.longitude, prefs.locationName)
        prefs.useDeviceLocation = false
        prefs.latitude = 25.2048
        prefs.longitude = 55.2708
        prefs.locationName = "Dubai"
        store.saveAzanPreferences(prefs)
        defer {
            (prefs.useDeviceLocation, prefs.latitude, prefs.longitude, prefs.locationName) = saved
            store.saveAzanPreferences(prefs)
        }
        try body()
    }

    // MARK: - Pure drawing views

    @Test func prayerPostureIconAllPostures() {
        let grid = VStack(spacing: 12) {
            ForEach([PrayerPosture.standing, .handsRaised, .bowing, .standingBrief,
                     .prostrating, .sitting, .salam], id: \.self) { posture in
                HStack { PrayerPostureIcon(posture: posture, size: 32); Text(String(describing: posture)) }
            }
        }.padding()
        assertViewSnapshot(of: grid, named: "all", size: CGSize(width: 300, height: 420))
    }

    @Test func progressRingVariants() {
        let rings = HStack(spacing: 16) {
            ProgressRing(completed: 0, total: 5)
            ProgressRing(completed: 3, total: 5)
            ProgressRing(completed: 5, total: 5)
            ProgressRing(completed: 0, total: 0)
        }.padding()
        assertViewSnapshot(of: rings, named: "variants", size: CGSize(width: 320, height: 100))
    }

    @Test func weeklyGridFixedWeek() {
        let grid = (0..<7).map { day in
            DaySummary(dateString: "2023-11-0\(day + 1)", completedCount: day < 5 ? day + 1 : 0,
                       onTimeCount: day < 5 ? day : 0, lateCount: day < 5 ? 1 : 0)
        }
        assertViewSnapshot(of: WeeklyGridView(grid: grid).padding(), named: "week",
                           size: CGSize(width: 402, height: 160))
    }

    @Test func prayerBreakdownChartFixedStats() {
        let stats = Prayer.notifiable.enumerated().map { index, prayer in
            PrayerStat(prayer: prayer, onTimeCount: 10 - index, lateCount: index, totalDays: 14)
        }
        assertViewSnapshot(of: PrayerBreakdownChart(stats: stats).padding(), named: "stats",
                           size: CGSize(width: 402, height: 300))
    }

    @Test func prayerTimeRowVariants() {
        let rows = VStack(spacing: 0) {
            PrayerTimeRow(entry: Self.entry(.fajr, isPassed: true, ramadan: "Suhoor ends"),
                          onToggleNotification: { _ in }, onTapPrayer: { _ in })
            PrayerTimeRow(entry: Self.entry(.dhuhr, isNext: true, friday: "Jumu'ah"),
                          onToggleNotification: { _ in }, onTapPrayer: { _ in })
            PrayerTimeRow(entry: Self.entry(.asr, isCurrent: true, urgency: .urgent),
                          onToggleNotification: { _ in }, onTapPrayer: { _ in })
            PrayerTimeRow(entry: Self.entry(.maghrib, notif: false, adjustment: 15),
                          onToggleNotification: { _ in }, onTapPrayer: nil)
        }
        assertViewSnapshot(of: rows, named: "variants", size: CGSize(width: 402, height: 320))
    }

    // MARK: - Guide content (drives PrayerGuideDataProvider's 1,150 lines)

    @Test func rakatBreakdownFajr() throws {
        let guide = try #require(PrayerGuideDataProvider.guide(
            for: .fajr, madhab: .hanafi, role: .munfarid, isTraveling: false, isQaza: false))
        assertViewSnapshot(of: RakatBreakdownView(rakats: guide.rakatBreakdown, onTapGroup: { _ in }).padding(),
                           named: "fajr", size: CGSize(width: 402, height: 260))
    }

    @Test func rakatGroupSectionFajrFard() throws {
        let guide = try #require(PrayerGuideDataProvider.guide(
            for: .fajr, madhab: .hanafi, role: .munfarid, isTraveling: false, isQaza: false))
        let group = try #require(guide.groups.first)
        assertViewSnapshot(of: ScrollView { RakatGroupSectionView(group: group) }, named: "fajr-first")
    }

    @Test func prayerDetailHanafiAllPrayers() {
        withPinnedDefaults(Self.hanafiDefaults) {
            for prayer in Prayer.notifiable {
                assertViewSnapshot(of: NavigationStack { PrayerDetailView(prayer: prayer) },
                                   named: prayer.rawValue)
            }
        }
    }

    @Test func prayerDetailVariants() {
        withPinnedDefaults(Self.hanafiDefaults.merging(["prayerGuideQaza": true]) { _, new in new }) {
            assertViewSnapshot(of: NavigationStack { PrayerDetailView(prayer: .dhuhr) }, named: "qaza")
        }
        withPinnedDefaults(Self.hanafiDefaults.merging(["prayerGuideTraveling": true]) { _, new in new }) {
            assertViewSnapshot(of: NavigationStack { PrayerDetailView(prayer: .dhuhr) }, named: "traveling")
        }
        withPinnedDefaults(Self.hanafiDefaults.merging(["prayerGuideMadhab": FiqhMadhab.shafii.rawValue]) { _, new in new }) {
            assertViewSnapshot(of: NavigationStack { PrayerDetailView(prayer: .fajr) }, named: "madhab-unavailable")
        }
    }

    @Test func prayerDetailRepresentativeSet() {
        withPinnedDefaults(Self.hanafiDefaults) {
            let view = NavigationStack { PrayerDetailView(prayer: .fajr) }
            assertViewSnapshot(of: view, named: "dark", appearance: .dark)
            assertViewSnapshot(of: view.environment(\.dynamicTypeSize, .accessibility2), named: "a11y-xl")
        }
    }

    // MARK: - Recitations / surahs / duas

    @Test func shortSurahsCollapsedAndExpanded() throws {
        let surahs = PrayerGuideDataProvider.shortSurahs()
        let first = try #require(surahs.first)
        assertViewSnapshot(
            of: ScrollView { ShortSurahsView(surahs: surahs, expandedId: .constant(nil), audioService: .shared) },
            named: "collapsed")
        assertViewSnapshot(
            of: ScrollView { ShortSurahsView(surahs: surahs, expandedId: .constant(first.id), audioService: .shared) },
            named: "expanded")
    }

    @Test func essentialRecitationsCollapsedAndExpanded() throws {
        let recitations = PrayerGuideDataProvider.essentialRecitations()
        let first = try #require(recitations.first)
        assertViewSnapshot(
            of: ScrollView { EssentialRecitationsView(recitations: recitations, expandedId: .constant(nil), audioService: .shared) },
            named: "collapsed")
        assertViewSnapshot(
            of: ScrollView { EssentialRecitationsView(recitations: recitations, expandedId: .constant(first.id), audioService: .shared) },
            named: "expanded")
    }

    @Test func recitationSheets() {
        assertViewSnapshot(of: ShortSurahsSheet(), named: "surahs-sheet")
        assertViewSnapshot(of: EssentialRecitationsSheet(), named: "recitations-sheet")
        assertViewSnapshot(of: DailyDuasSheet(), named: "duas-sheet")
    }

    // MARK: - Tracking views (fixed-clock service)

    @Test func trackerSummaryCard() throws {
        let service = try Self.seededTracking()
        assertViewSnapshot(of: NavigationStack { TrackerSummaryCard(trackingService: service).padding() },
                           named: "seeded", size: CGSize(width: 402, height: 240))
    }

    @Test func prayerAnalyticsSeeded() async throws {
        let service = try Self.seededTracking()
        await assertSettledViewSnapshot(
            of: NavigationStack { PrayerAnalyticsView(trackingService: service) }, named: "seeded")
    }

    @Test func prayerLogRendersOnly() throws {
        // Month sections are built from Date() — render-only by rule.
        let service = try Self.seededTracking()
        ViewRender.assertRenders(NavigationStack { PrayerLogView(trackingService: service) })
    }

    // MARK: - Settings / search / main screen

    @Test func azanSettingsList() {
        assertViewSnapshot(
            of: NavigationStack {
                AzanSettingsView(preferences: LocalAzanPreferences(),
                                 locationService: AzanLocationService(), onSave: { _ in })
            },
            named: "defaults")
    }

    @Test func locationSearchEmpty() {
        assertViewSnapshot(of: NavigationStack { LocationSearchView(onSelect: { _, _, _ in }) },
                           named: "empty")
    }

    @Test func azanViewRendersOnly() {
        // Live countdown card + real-clock prayer list — render-only. The
        // pinned manual location keeps CoreLocation untouched.
        Self.withFixedAzanLocation {
            ViewRender.assertRenders(AzanView())
        }
    }
}
}
