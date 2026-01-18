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
    @State private var showingAddItem = false
    @State private var editingItem: PassVaultItem?
    @State private var showingTrash = false
    @State private var showingFolders = false
    @State private var showingHealth = false

    var body: some View {
        NavigationStack {
            Group {
                if passService.isUnlocked || isUnlocked {
                    PassItemListView(
                        passService: passService,
                        onSelectItem: { item in
                            selectedItem = item
                        },
                        onAddItem: {
                            showingAddItem = true
                        },
                        onEditItem: { item in
                            editingItem = item
                        }
                    )
                    .navigationTitle("Pass")
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Menu {
                                Button {
                                    showingFolders = true
                                } label: {
                                    Label("Folders", systemImage: "folder")
                                }

                                Button {
                                    showingTrash = true
                                } label: {
                                    Label("Trash", systemImage: "trash")
                                }

                                Divider()

                                Button {
                                    showingHealth = true
                                } label: {
                                    Label("Password Health", systemImage: "heart.text.square")
                                }

                                Button {
                                    passService.lock()
                                    isUnlocked = false
                                } label: {
                                    Label("Lock Vault", systemImage: "lock.fill")
                                }
                            } label: {
                                Image(systemName: "ellipsis.circle")
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
            .sheet(isPresented: $showingAddItem) {
                PassItemFormView(
                    passService: passService,
                    onSave: {
                        showingAddItem = false
                    },
                    onCancel: {
                        showingAddItem = false
                    }
                )
            }
            .sheet(item: $editingItem) { item in
                PassItemFormView(
                    passService: passService,
                    editingItem: item,
                    onSave: {
                        editingItem = nil
                    },
                    onCancel: {
                        editingItem = nil
                    }
                )
            }
            .sheet(isPresented: $showingTrash) {
                PassTrashView(
                    passService: passService,
                    onDismiss: {
                        showingTrash = false
                    }
                )
            }
            .sheet(isPresented: $showingFolders) {
                PassFolderListView(
                    passService: passService,
                    onDismiss: {
                        showingFolders = false
                    },
                    onSelectFolder: { folder in
                        // TODO: Filter items by folder
                        showingFolders = false
                    }
                )
            }
            .sheet(isPresented: $showingHealth) {
                PasswordHealthView(
                    passService: passService,
                    onDismiss: {
                        showingHealth = false
                    },
                    onSelectItem: { item in
                        showingHealth = false
                        selectedItem = item
                    }
                )
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
