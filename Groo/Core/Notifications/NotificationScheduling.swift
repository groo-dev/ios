//
//  NotificationScheduling.swift
//  Groo
//
//  Phase 7 seam over UNUserNotificationCenter (the KeychainServicing
//  pattern): AzanNotificationService and PushService talk to this protocol;
//  production injects the real center, tests inject a recording fake.
//  UNNotificationSettings has no public initializer, so the protocol
//  exposes the one scalar the services actually read (authorizationStatus).
//

import UserNotifications

protocol NotificationScheduling: AnyObject {
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool
    func authorizationStatus() async -> UNAuthorizationStatus
    func setNotificationCategories(_ categories: Set<UNNotificationCategory>)
    func add(_ request: UNNotificationRequest) async throws
    func pendingNotificationRequests() async -> [UNNotificationRequest]
    func removePendingNotificationRequests(withIdentifiers identifiers: [String])
}

extension UNUserNotificationCenter: NotificationScheduling {
    func authorizationStatus() async -> UNAuthorizationStatus {
        await notificationSettings().authorizationStatus
    }
}
