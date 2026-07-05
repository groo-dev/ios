//
//  ContentView.swift
//  Groo
//
//  Root view that manages app state and navigation flow.
//

import SwiftUI

struct ContentView: View {
    @Environment(AuthService.self) private var authService
    @Environment(PushService.self) private var pushService

    @State private var isLoggedIn = false
    @State private var padService: PadService?
    @State private var syncService: SyncService?
    @State private var passService: PassService?
    @State private var isGloballyUnlocked = false
    @State private var needsGlobalUnlock = false

    // Under --uitest the global-lock check must consult the same fake
    // keychain the services write to, never the developer's real keychain.
    private let keychain: any KeychainServicing =
        UITestMode.isActive ? UITestMode.keychain : KeychainService()

    var body: some View {
        Group {
            if !isLoggedIn {
                LoginView()
            } else if let padService, let syncService, let passService {
                if needsGlobalUnlock && !isGloballyUnlocked {
                    GlobalLockView(
                        padService: padService,
                        passService: passService,
                        onUnlock: {
                            isGloballyUnlocked = true
                        },
                        onSignOut: {
                            signOut()
                        }
                    )
                } else {
                    MainTabView(
                        padService: padService,
                        syncService: syncService,
                        passService: passService,
                        onSignOut: {
                            signOut()
                        }
                    )
                }
            }
        }
        .onAppear {
            initializeServices()
            updateState()
        }
        .onChange(of: authService.isAuthenticated) {
            updateState()
        }
    }

    private func initializeServices() {
        if UITestMode.isActive {
            // Hermetic services: Pad/Sync API calls die at the token provider
            // (no network I/O ever starts); Pass talks to the in-process stub;
            // stores are in-memory (LocalStore.shared is uitest-aware).
            let api = APIClient(
                baseURL: Config.padAPIBaseURL,
                tokenProvider: { throw APIError.unauthorized },
                forceRefresh: { throw APIError.unauthorized }
            )
            padService = PadService(api: api, keychain: UITestMode.keychain)
            syncService = SyncService(api: api, monitorsNetwork: false)
            passService = UITestMode.makePassService()
            return
        }

        let api = APIClient(
            baseURL: Config.padAPIBaseURL,
            tokenProvider: { try await authService.accessToken() },
            forceRefresh: { try await authService.forceRefresh() }
        )
        padService = PadService(api: api)
        let sync = SyncService(api: api)
        syncService = sync
        passService = PassService(
            tokenProvider: { try await authService.accessToken() },
            forceRefresh: { try await authService.forceRefresh() }
        )

        // Wire up push notification sync callback
        pushService.onSyncRequested = { [weak sync] in
            Task { @MainActor in
                await sync?.sync()
            }
        }
    }

    private func updateState() {
        let wasLoggedIn = isLoggedIn
        // --uitest bypasses OAuth entirely; services never ask AuthService
        // for tokens in that mode (see initializeServices)
        isLoggedIn = authService.isAuthenticated || UITestMode.isActive

        // Check if global unlock is needed (biometric keys exist)
        if !wasLoggedIn && isLoggedIn {
            needsGlobalUnlock = keychain.biometricProtectedKeyExists(for: KeychainService.Key.passEncryptionKey)
                || keychain.biometricProtectedKeyExists(for: KeychainService.Key.padEncryptionKey)
            isGloballyUnlocked = false
        }
    }

    private func signOut() {
        padService?.lockAndClearKey()
        passService?.lockAndClearKey()
        syncService?.clearLocalStorage()
        isLoggedIn = false
        isGloballyUnlocked = false
        needsGlobalUnlock = false
        Task {
            await authService.logout()
        }
    }
}

#Preview {
    ContentView()
        .environment(AuthService())
        .environment(PushService())
}
