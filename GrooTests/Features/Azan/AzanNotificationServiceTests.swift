//
//  AzanNotificationServiceTests.swift
//  GrooTests
//
//  Authorization-state and scheduling logic over the NotificationScheduling
//  seam. The service compares prayer times against the real clock, so
//  scheduling tests assert INVARIANTS (azan_ ids, future triggers, count
//  bookkeeping, denied-auth preservation) — never absolute schedules.
//

import Foundation
import Testing
import UserNotifications
@testable import Groo

@MainActor
struct AzanNotificationServiceTests {
    static func request(id: String) -> UNNotificationRequest {
        UNNotificationRequest(identifier: id, content: UNMutableNotificationContent(), trigger: nil)
    }

    /// Real-clock Dubai prayer service: some times today are already past,
    /// some are future — exactly what the invariants need.
    static func prayerService() -> PrayerTimeService {
        PrayerTimeServiceTests.makeService(nowAt: Date())
    }

    @Test func requestAuthorizationGrantedSetsFlags() async {
        let center = FakeNotificationCenter()
        let service = AzanNotificationService(center: center)
        #expect(await service.requestAuthorization())
        #expect(service.isAuthorized)
        #expect(!service.authorizationDenied)
    }

    @Test func requestAuthorizationDeniedSetsDeniedFlag() async {
        let center = FakeNotificationCenter()
        center.authorizationResult = .success(false)
        let service = AzanNotificationService(center: center)
        #expect(!(await service.requestAuthorization()))
        #expect(!service.isAuthorized)
        #expect(service.authorizationDenied)
    }

    @Test func requestAuthorizationErrorIsNotADenial() async {
        struct Boom: Error {}
        let center = FakeNotificationCenter()
        center.authorizationResult = .failure(Boom())
        let service = AzanNotificationService(center: center)
        #expect(!(await service.requestAuthorization()))
        #expect(!service.authorizationDenied)   // errored ≠ user denied
    }

    @Test(arguments: [
        (UNAuthorizationStatus.authorized, true, false),
        (UNAuthorizationStatus.denied, false, true),
        (UNAuthorizationStatus.notDetermined, false, false),
    ])
    func checkAuthorizationMapsStatus(_ fixture: (UNAuthorizationStatus, Bool, Bool)) async {
        let center = FakeNotificationCenter()
        center.status = fixture.0
        let service = AzanNotificationService(center: center)
        await service.checkAuthorization()
        #expect(service.isAuthorized == fixture.1)
        #expect(service.authorizationDenied == fixture.2)
    }

    @Test func registerCategoryRegistersAzanPrayer() {
        let center = FakeNotificationCenter()
        let service = AzanNotificationService(center: center)
        service.registerCategory()
        #expect(center.categories.count == 1)
        #expect(center.categories.first?.contains { $0.identifier == "AZAN_PRAYER" } == true)
    }

    @Test func deniedAuthorizationSchedulesNothingAndWipesNothing() async {
        let center = FakeNotificationCenter()
        center.status = .denied
        center.authorizationResult = .success(false)
        center.seedPending([Self.request(id: "azan_fajr_123")])
        let service = AzanNotificationService(center: center)

        await service.scheduleNotifications(prayerService: Self.prayerService(),
                                            preferences: LocalAzanPreferences())

        #expect(center.added.isEmpty)
        #expect(center.removedIdentifiers.isEmpty, "a denied request must never wipe existing notifications")
        #expect(center.pending.map(\.identifier) == ["azan_fajr_123"])
    }

    @Test func schedulingInvariantsHold() async throws {
        let center = FakeNotificationCenter()
        center.seedPending([Self.request(id: "azan_stale_1"), Self.request(id: "other_app_id")])
        let service = AzanNotificationService(center: center)

        await service.scheduleNotifications(prayerService: Self.prayerService(),
                                            preferences: LocalAzanPreferences())

        #expect(!center.added.isEmpty, "12 days ahead always yields future prayers")
        for request in center.added {
            #expect(request.identifier.hasPrefix("azan_"), "foreign id scheduled: \(request.identifier)")
            let trigger = try #require(request.trigger as? UNCalendarNotificationTrigger)
            let fireDate = try #require(trigger.nextTriggerDate())
            #expect(fireDate > Date(), "past trigger scheduled: \(request.identifier)")
        }
        #expect(center.added.count <= 60, "maxNotifications cap violated")
        #expect(service.pendingCount == center.added.count)
        // The stale azan_ id was wiped, the foreign id preserved
        let removed = center.removedIdentifiers.flatMap { $0 }
        #expect(removed.contains("azan_stale_1"))
        #expect(!removed.contains("other_app_id"))
    }

    @Test func jumuahReminderScheduledWhenEnabled() async {
        let center = FakeNotificationCenter()
        let service = AzanNotificationService(center: center)

        // ishaNotification disabled so the 5 default-enabled regular prayers
        // (fajr/dhuhr/asr/maghrib/isha) drop to 4 × 12 days = 48, always
        // leaving headroom under maxNotifications (60) for the Jumu'ah
        // reminder — 5×12 == 60 exactly can otherwise saturate the cap
        // when the suite runs before today's Fajr (all 5 still future).
        await service.scheduleNotifications(
            prayerService: Self.prayerService(),
            preferences: LocalAzanPreferences(ishaNotification: false, jumuahReminderEnabled: true))

        #expect(center.added.contains { $0.identifier.hasPrefix("azan_jumuah_") },
                "there is always a future Friday inside the 12-day window")
    }

    @Test func updatePendingCountCountsOnlyAzanIds() async {
        let center = FakeNotificationCenter()
        center.seedPending([Self.request(id: "azan_a"), Self.request(id: "azan_b"),
                            Self.request(id: "other")])
        let service = AzanNotificationService(center: center)
        await service.updatePendingCount()
        #expect(service.pendingCount == 2)
        await service.removeAllAzanNotifications()
        #expect(service.pendingCount == 0)
        #expect(center.pending.map(\.identifier) == ["other"])
    }
}
