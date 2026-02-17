//
//  AppDelegate.swift
//  Groo
//
//  UIApplicationDelegate for handling APNs callbacks.
//  Used via @UIApplicationDelegateAdaptor in GrooApp.
//

import UIKit
import UserNotifications

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    var pushService: PushService?
    var azanAudioService: AzanAudioService?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Set notification delegate for foreground handling
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    // MARK: - APNs Registration

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Task {
            try? await pushService?.registerDeviceToken(deviceToken)
        }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        pushService?.handleRegistrationFailure(error)
    }

    // MARK: - Remote Notification Handling

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        pushService?.handleRemoteNotification(userInfo)
        completionHandler(.newData)
    }

    // MARK: - UNUserNotificationCenterDelegate

    // Handle notification when app is in foreground
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Trigger sync when notification arrives in foreground
        let userInfo = notification.request.content.userInfo
        pushService?.handleRemoteNotification(userInfo)

        // Show banner even when app is in foreground
        completionHandler([.banner, .badge, .sound])
    }

    // Handle notification tap
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo

        // Route Azan notification taps to audio playback
        if let action = userInfo["action"] as? String, action == "azan" {
            let prayerRaw = userInfo["prayer"] as? String
            let prayer = prayerRaw.flatMap { Prayer(rawValue: $0) } ?? .dhuhr
            Task { @MainActor in
                azanAudioService?.playFullAzan(for: prayer)
            }
            completionHandler()
            return
        }

        pushService?.handleRemoteNotification(userInfo)
        completionHandler()
    }
}
