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

    private let keychain = KeychainService()

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
        let api = APIClient(baseURL: Config.padAPIBaseURL)
        padService = PadService(api: api)
        let sync = SyncService(api: api)
        syncService = sync
        passService = PassService()

        // Wire up push notification sync callback
        pushService.onSyncRequested = { [weak sync] in
            Task { @MainActor in
                await sync?.sync()
            }
        }
    }

    private func updateState() {
        let wasLoggedIn = isLoggedIn
        isLoggedIn = authService.isAuthenticated

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
        try? authService.logout()
        isLoggedIn = false
        isGloballyUnlocked = false
        needsGlobalUnlock = false
    }
}

#Preview {
    ContentView()
        .environment(AuthService())
        .environment(PushService())
}
