//
//  PadListView.swift
//  Groo
//
//  List of Pad items with pull-to-refresh and swipe actions.
//

import SwiftUI

struct PadListView: View {
    let padService: PadService
    let syncService: SyncService

    @State private var items: [DecryptedListItem] = []
    @State private var isRefreshing = false

    var body: some View {
        Group {
            if items.isEmpty && !isRefreshing {
                emptyState
            } else {
                itemsList
            }
        }
        .onAppear {
            loadItems()
        }
        .task {
            // Trigger initial sync when view appears
            await syncService.sync()
            loadItems()
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Items", systemImage: "doc.on.clipboard")
        } description: {
            Text("Add your first item with the + button")
        }
    }

    private var itemsList: some View {
        List {
            ForEach(items) { item in
                ItemRow(item: item, padService: padService)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            deleteItem(item)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
            }
        }
        .listStyle(.plain)
        .refreshable {
            await refresh()
        }
    }

    private func loadItems() {
        // Decrypt items from local encrypted storage
        items = (try? padService.getDecryptedItems()) ?? []
    }

    private func refresh() async {
        isRefreshing = true
        await syncService.sync()
        loadItems()
        isRefreshing = false
    }

    private func deleteItem(_ item: DecryptedListItem) {
        Task {
            await syncService.deleteItem(id: item.id)
            loadItems()
        }
    }
}

#Preview {
    NavigationStack {
        PadListView(
            padService: PadService(api: APIClient(baseURL: Config.padAPIBaseURL)),
            syncService: SyncService(api: APIClient(baseURL: Config.padAPIBaseURL))
        )
    }
}
