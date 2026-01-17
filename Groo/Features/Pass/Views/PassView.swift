//
//  PassView.swift
//  Groo
//
//  Main Pass view that shows unlock screen or item list based on vault state.
//

import SwiftUI

struct PassView: View {
    let passService: PassService
    let onSignOut: () -> Void

    @State private var selectedItem: PassVaultItem?
    @State private var isUnlocked = false

    var body: some View {
        NavigationStack {
            Group {
                if passService.isUnlocked || isUnlocked {
                    PassItemListView(
                        passService: passService,
                        onSelectItem: { item in
                            selectedItem = item
                        }
                    )
                    .navigationTitle("Pass")
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button {
                                passService.lock()
                                isUnlocked = false
                            } label: {
                                Image(systemName: "lock.fill")
                            }
                        }
                    }
                } else {
                    PassUnlockView(
                        passService: passService,
                        onUnlock: {
                            isUnlocked = true
                        },
                        onSignOut: onSignOut
                    )
                }
            }
            .sheet(item: $selectedItem) { item in
                NavigationStack {
                    PassItemDetailView(
                        item: item,
                        passService: passService,
                        onDismiss: {
                            selectedItem = nil
                        }
                    )
                }
            }
        }
        .task {
            // Check vault setup on appear
            await passService.checkVaultSetup()
        }
    }
}

#Preview {
    PassView(
        passService: PassService(),
        onSignOut: {}
    )
}
