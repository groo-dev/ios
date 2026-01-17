//
//  PassTrashView.swift
//  Groo
//
//  View for managing deleted vault items (restore or permanently delete).
//

import SwiftUI

struct PassTrashView: View {
    let passService: PassService
    let onDismiss: () -> Void

    @State private var showingEmptyConfirmation = false

    private var deletedItems: [PassVaultItem] {
        passService.getDeletedItems()
    }

    var body: some View {
        NavigationStack {
            Group {
                if deletedItems.isEmpty {
                    emptyState
                } else {
                    List {
                        Section {
                            ForEach(deletedItems) { item in
                                trashItemRow(item)
                            }
                        } footer: {
                            Text("Items in trash will be permanently deleted after 30 days.")
                                .font(.caption)
                        }
                    }
                }
            }
            .navigationTitle("Trash")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") {
                        onDismiss()
                    }
                }

                if !deletedItems.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Empty Trash", role: .destructive) {
                            showingEmptyConfirmation = true
                        }
                        .foregroundStyle(.red)
                    }
                }
            }
            .confirmationDialog(
                "Empty Trash",
                isPresented: $showingEmptyConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete All Items", role: .destructive) {
                    Task {
                        try? await passService.emptyTrash()
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will permanently delete all \(deletedItems.count) items in trash. This cannot be undone.")
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: "trash")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)

            Text("Trash is Empty")
                .font(.headline)
                .foregroundStyle(.secondary)

            Text("Deleted items will appear here")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func trashItemRow(_ item: PassVaultItem) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            // Type icon
            ZStack {
                Circle()
                    .fill(Color.secondary.opacity(0.1))
                    .frame(width: 40, height: 40)

                Image(systemName: item.type.icon)
                    .foregroundStyle(.secondary)
            }

            // Item details
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(item.name)
                    .font(.body)

                if let deletedAt = item.deletedAt {
                    Text("Deleted \(formatDeletedDate(deletedAt))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
        .swipeActions(edge: .leading) {
            Button {
                Task {
                    try? await passService.restoreItem(item)
                }
            } label: {
                Label("Restore", systemImage: "arrow.uturn.backward")
            }
            .tint(.green)
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                Task {
                    try? await passService.permanentlyDeleteItem(item)
                }
            } label: {
                Label("Delete", systemImage: "trash.fill")
            }
        }
        .contextMenu {
            Button {
                Task {
                    try? await passService.restoreItem(item)
                }
            } label: {
                Label("Restore", systemImage: "arrow.uturn.backward")
            }

            Divider()

            Button(role: .destructive) {
                Task {
                    try? await passService.permanentlyDeleteItem(item)
                }
            } label: {
                Label("Delete Permanently", systemImage: "trash.fill")
            }
        }
    }

    private func formatDeletedDate(_ timestamp: Int) -> String {
        let date = Date(timeIntervalSince1970: Double(timestamp) / 1000)
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

#Preview {
    PassTrashView(
        passService: PassService(),
        onDismiss: {}
    )
}
