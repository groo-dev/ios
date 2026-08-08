//
//  ContentView.swift
//  Groo
//
//  Root view that manages app state and navigation flow.
//

import SwiftUI
import UIKit

struct ContentView: View {
    @Environment(AuthService.self) private var authService
    @Environment(PushService.self) private var pushService
    @Environment(\.scenePhase) private var scenePhase

    @State private var isLoggedIn = false
    @State private var padService: PadService?
    @State private var syncService: SyncService?
    @State private var passService: PassService?
    @State private var configStore: TabConfigurationStore?
    @State private var router: AppRouter?
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
                } else if let configStore, let router {
                    Group {
                        if UIDevice.current.userInterfaceIdiom == .pad {
                            MainTabView(
                                padService: padService,
                                syncService: syncService,
                                passService: passService,
                                onSignOut: { signOut() }
                            )
                        } else {
                            PhoneTabView(
                                padService: padService,
                                syncService: syncService,
                                passService: passService,
                                onSignOut: { signOut() }
                            )
                        }
                    }
                    .environment(configStore)
                    .environment(router)
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
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            // The AutoFill extension may have registered a passkey while we were
            // backgrounded. The app doesn't re-lock on background, so without
            // this the queue would wait for the next cold start. A locked vault
            // makes this a no-op — mergePendingPasskeys can't decrypt the queue
            // without the key, and the unlock paths already cover that case.
            Task { await passService?.mergePendingPasskeys() }
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

            let configuration = TabConfigurationStore()
            configStore = configuration
            router = AppRouter(store: configuration)
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

        let configuration = TabConfigurationStore()
        configStore = configuration
        router = AppRouter(store: configuration)
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
