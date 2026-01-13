//
//  PushService.swift
//  Groo
//
//  APNs registration and push notification handling.
//  Device tokens are registered with accounts API.
//

import UIKit
import Foundation
import UserNotifications

// MARK: - Types

enum PushError: Error {
    case registrationFailed
    case notAuthorized
    case noAuthToken
    case apiError(Error)
}

struct DeviceRegistration: Encodable {
    let token: String
    let platform: String
    let environment: String
    let bundleId: String
    let name: String
}

// MARK: - PushService

@MainActor
@Observable
class PushService {
    private(set) var isRegistered = false
    private(set) var deviceToken: String?

    private let keychain = KeychainService()

    // Callback for when a sync notification is received
    var onSyncRequested: (() -> Void)?

    init() {
        // Load cached token
        deviceToken = try? keychain.loadString(for: KeychainService.Key.deviceToken)
        isRegistered = deviceToken != nil
    }

    // MARK: - Authorization

    func requestAuthorization() async throws -> Bool {
        let center = UNUserNotificationCenter.current()

        let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])

        if granted {
            // Register for remote notifications on main thread
            await MainActor.run {
                UIApplication.shared.registerForRemoteNotifications()
            }
        }

        return granted
    }

    // MARK: - Token Registration

    func registerDeviceToken(_ tokenData: Data) async throws {
        let tokenString = tokenData.map { String(format: "%02x", $0) }.joined()
        print("[PushService] registerDeviceToken called")
        print("[PushService] Token: \(tokenString.prefix(16))...")

        // Cache the token
        try keychain.save(tokenString, for: KeychainService.Key.deviceToken)
        deviceToken = tokenString

        // Get PAT for auth
        guard let patToken = try? keychain.loadString(for: KeychainService.Key.patToken) else {
            print("[PushService] ERROR: No PAT token in keychain")
            throw PushError.noAuthToken
        }
        print("[PushService] PAT token: \(patToken.prefix(20))...")

        // Determine environment
        #if DEBUG
        let environment = "development"
        #else
        let environment = "production"
        #endif
        print("[PushService] Environment: \(environment)")

        // Register with accounts API
        let bundleId = Bundle.main.bundleIdentifier ?? "dev.groo.ios"
        let deviceName = UIDevice.current.name
        print("[PushService] Bundle ID: \(bundleId)")
        print("[PushService] Device name: \(deviceName)")

        let registration = DeviceRegistration(
            token: tokenString,
            platform: "ios",
            environment: environment,
            bundleId: bundleId,
            name: deviceName
        )

        let url = Config.accountsAPIBaseURL.appendingPathComponent("v1/devices")
        print("[PushService] URL: \(url.absoluteString)")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(patToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(registration)

        print("[PushService] Sending registration request...")
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            print("[PushService] ERROR: Invalid response type")
            throw PushError.registrationFailed
        }

        let responseBody = String(data: data, encoding: .utf8) ?? "empty"
        print("[PushService] Response status: \(httpResponse.statusCode)")
        print("[PushService] Response body: \(responseBody)")

        guard (200...299).contains(httpResponse.statusCode) else {
            print("[PushService] Registration failed: \(responseBody)")
            throw PushError.registrationFailed
        }

        isRegistered = true
        print("[PushService] Device registered successfully")
    }

    func unregisterDeviceToken() async throws {
        guard let token = deviceToken else { return }

        guard let patToken = try? keychain.loadString(for: KeychainService.Key.patToken) else {
            // Just clear local state if no auth
            try? keychain.delete(for: KeychainService.Key.deviceToken)
            deviceToken = nil
            isRegistered = false
            return
        }

        let url = Config.accountsAPIBaseURL.appendingPathComponent("v1/devices/\(token)")
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(patToken)", forHTTPHeaderField: "Authorization")

        do {
            let _ = try await URLSession.shared.data(for: request)
        } catch {
            // Ignore errors during unregistration
        }

        try? keychain.delete(for: KeychainService.Key.deviceToken)
        deviceToken = nil
        isRegistered = false
    }

    // MARK: - Notification Handling

    func handleRemoteNotification(_ userInfo: [AnyHashable: Any]) {
        print("[PushService] Received notification: \(userInfo)")

        // Check if this is a sync notification
        // The payload structure is: { "aps": {...}, "action": "sync" }
        if let action = userInfo["action"] as? String, action == "sync" {
            print("[PushService] Triggering sync")
            onSyncRequested?()
        }
    }

    func handleRegistrationFailure(_ error: Error) {
        print("Push registration failed: \(error)")
        isRegistered = false
    }
}
