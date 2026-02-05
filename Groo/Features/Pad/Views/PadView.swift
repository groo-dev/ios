//
//  PadView.swift
//  Groo
//
//  Main Pad tab view with unlock and list.
//

import SwiftUI

struct PadView: View {
    let padService: PadService
    let syncService: SyncService
    let onSignOut: () -> Void

    @State private var showAddItem = false
    @State private var isUnlocked = false
    @State private var listRefreshTrigger = UUID()

    var body: some View {
        Group {
            if isUnlocked {
                unlockedView
            } else {
                PadUnlockView(
                    padService: padService,
                    syncService: syncService,
                    onUnlock: {
                        isUnlocked = true
                    },
                    onSignOut: onSignOut
                )
            }
        }
        .onAppear {
            isUnlocked = padService.isUnlocked
        }
    }

    private var unlockedView: some View {
        NavigationStack {
            PadListView(
                padService: padService,
                syncService: syncService,
                refreshTrigger: listRefreshTrigger
            )
            .navigationTitle("Pad")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showAddItem = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showAddItem, onDismiss: {
                listRefreshTrigger = UUID()
            }) {
                AddItemSheet(padService: padService, syncService: syncService)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            PasteFAB(
                padService: padService,
                syncService: syncService,
                onItemAdded: { listRefreshTrigger = UUID() }
            )
        }
        .tint(Theme.Brand.primary)
    }
}

#Preview {
    PadView(
        padService: PadService(api: APIClient(baseURL: Config.padAPIBaseURL)),
        syncService: SyncService(api: APIClient(baseURL: Config.padAPIBaseURL)),
        onSignOut: {}
    )
    .environment(AuthService())
}
