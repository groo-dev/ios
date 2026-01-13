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

    var body: some View {
        Group {
            if !isLoggedIn {
                LoginView()
            } else if let padService, let syncService {
                MainTabView(
                    padService: padService,
                    syncService: syncService,
                    onSignOut: {
                        signOut()
                    }
                )
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

        // Wire up push notification sync callback
        pushService.onSyncRequested = { [weak sync] in
            Task { @MainActor in
                await sync?.sync()
            }
        }
    }

    private func updateState() {
        isLoggedIn = authService.isAuthenticated
    }

    private func signOut() {
        padService?.lockAndClearKey()
        syncService?.clearLocalStorage()
        try? authService.logout()
        isLoggedIn = false
    }
}

#Preview {
    ContentView()
        .environment(AuthService())
        .environment(PushService())
}
