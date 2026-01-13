//
//  GrooApp.swift
//  Groo
//
//  Main app entry point with environment setup.
//

import SwiftUI
import SwiftData

@main
struct GrooApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    @State private var authService = AuthService()
    @State private var pushService = PushService()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(authService)
                .environment(pushService)
                .modelContainer(LocalStore.shared.container)
                .onAppear {
                    // Connect AppDelegate to PushService
                    appDelegate.pushService = pushService
                    // Request push notification permission
                    setupPushNotifications()
                }
        }
    }

    private func setupPushNotifications() {
        Task {
            do {
                let granted = try await pushService.requestAuthorization()
                if granted {
                    print("[GrooApp] Push notifications authorized")
                }
            } catch {
                print("[GrooApp] Push authorization failed: \(error)")
            }
        }
    }
}
