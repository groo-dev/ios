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
import os

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
    private(set) var lastRegistrationError: String?

    private let keychain = KeychainService()

    /// Wired up by `GrooApp` after both services are constructed. Used to obtain
    /// the OAuth access token for device registration requests.
    weak var authService: AuthService?

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
        Log.push.debug("registerDeviceToken called")

        // Cache the token
        try keychain.save(tokenString, for: KeychainService.Key.deviceToken)
        deviceToken = tokenString

        guard let authService else {
            Log.push.error("No AuthService wired, can't register device")
            throw PushError.noAuthToken
        }

        // Determine environment
        #if DEBUG
        let environment = "development"
        #else
        let environment = "production"
        #endif

        // Register with accounts API
        let bundleId = Bundle.main.bundleIdentifier ?? "dev.groo.ios"
        let deviceName = UIDevice.current.name

        let registration = DeviceRegistration(
            token: tokenString,
            platform: "ios",
            environment: environment,
            bundleId: bundleId,
            name: deviceName
        )

        let url = Config.accountsAPIBaseURL.appendingPathComponent("v1/devices")
        Log.push.debug("Registering device (\(environment, privacy: .public)) at \(url.absoluteString, privacy: .public)")

        let body = try JSONEncoder().encode(registration)

        func send(_ accessToken: String) async throws -> (Data, HTTPURLResponse) {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            request.httpBody = body

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                Log.push.error("Device registration failed: invalid response type")
                throw PushError.registrationFailed
            }
            return (data, httpResponse)
        }

        var (data, httpResponse) = try await send(authService.accessToken())

        if httpResponse.statusCode == 401 {
            // Token looked valid but the server rejected it — force one refresh
            // and retry exactly once; a second 401 falls through and fails below.
            let refreshedToken = try await authService.forceRefresh()
            (data, httpResponse) = try await send(refreshedToken)
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let responseBody = String(data: data, encoding: .utf8) ?? "empty"
            Log.push.error("Device registration failed with status \(httpResponse.statusCode): \(responseBody, privacy: .public)")
            throw PushError.registrationFailed
        }

        isRegistered = true
        lastRegistrationError = nil
        Log.push.debug("Device registered successfully")
    }

    func unregisterDeviceToken() async throws {
        guard let token = deviceToken else { return }

        guard let authService else {
            // Just clear local state if no auth
            try? keychain.delete(for: KeychainService.Key.deviceToken)
            deviceToken = nil
            isRegistered = false
            return
        }

        let url = Config.accountsAPIBaseURL.appendingPathComponent("v1/devices/\(token)")

        func send(_ accessToken: String) async throws -> (Data, HTTPURLResponse?) {
            var request = URLRequest(url: url)
            request.httpMethod = "DELETE"
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            let (data, response) = try await URLSession.shared.data(for: request)
            return (data, response as? HTTPURLResponse)
        }

        do {
            let accessToken = try await authService.accessToken()
            var (data, httpResponse) = try await send(accessToken)

            if httpResponse?.statusCode == 401 {
                let refreshedToken = try await authService.forceRefresh()
                (data, httpResponse) = try await send(refreshedToken)
            }

            if let httpResponse, !(200...299).contains(httpResponse.statusCode) {
                let responseBody = String(data: data, encoding: .utf8) ?? "empty"
                Log.push.error("Device unregistration returned status \(httpResponse.statusCode): \(responseBody, privacy: .public)")
            }
        } catch {
            // Local state is still cleared, but the failure must be visible
            Log.push.error("Device unregistration request failed: \(String(describing: error), privacy: .public)")
        }

        try? keychain.delete(for: KeychainService.Key.deviceToken)
        deviceToken = nil
        isRegistered = false
    }

    // MARK: - Notification Handling

    func handleRemoteNotification(_ userInfo: [AnyHashable: Any]) {
        Log.push.debug("Received notification: \(String(describing: userInfo), privacy: .private)")

        // Check if this is a sync notification
        // The payload structure is: { "aps": {...}, "action": "sync" }
        if let action = userInfo["action"] as? String, action == "sync" {
            Log.push.debug("Triggering sync")
            onSyncRequested?()
        }
    }

    func handleRegistrationFailure(_ error: Error) {
        Log.push.error("Push registration failed: \(String(describing: error), privacy: .public)")
        lastRegistrationError = error.localizedDescription
        isRegistered = false
    }
}
