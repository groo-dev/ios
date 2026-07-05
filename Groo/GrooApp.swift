//
//  GrooApp.swift
//  Groo
//
//  Main app entry point with environment setup.
//

import SwiftUI
import SwiftData
import os

@main
struct GrooApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    @State private var authService = AuthService()
    @State private var pushService = PushService()
    @State private var azanAudioService = AzanAudioService()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(authService)
                .environment(pushService)
                .environment(azanAudioService)
                .modelContainer(LocalStore.shared.container)
                .onAppear {
                    // Connect AppDelegate to PushService
                    appDelegate.pushService = pushService
                    appDelegate.azanAudioService = azanAudioService
                    // PushService needs the OAuth access token for device registration
                    pushService.authService = authService
                    // Request push notification permission
                    setupPushNotifications()
                    // Register Azan notification category
                    registerAzanNotificationCategory()
                }
        }
    }

    private func setupPushNotifications() {
        Task {
            do {
                let granted = try await pushService.requestAuthorization()
                if granted {
                    Log.push.debug("Push notifications authorized")
                } else {
                    Log.push.info("Push notification authorization declined by user")
                }
            } catch {
                Log.push.error("Push authorization failed: \(String(describing: error), privacy: .public)")
            }
        }
    }

    private func registerAzanNotificationCategory() {
        let notificationService = AzanNotificationService()
        notificationService.registerCategory()
    }
}
