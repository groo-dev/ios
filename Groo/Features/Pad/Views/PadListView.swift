//
//  PadListView.swift
//  Groo
//
//  List of Pad items with search and context menus.
//

import SwiftUI

struct PadListView: View {
    let padService: PadService
    let syncService: SyncService
    let onAddItem: () -> Void
    var refreshTrigger: UUID = UUID()

    @State private var items: [DecryptedListItem] = []
    @State private var isRefreshing = false
    @State private var searchText = ""
    @State private var toastState = ToastState()

    private var filteredItems: [DecryptedListItem] {
        if searchText.isEmpty {
            return items
        }
        return items.filter { item in
            item.text.localizedCaseInsensitiveContains(searchText) ||
            item.files.contains { $0.name.localizedCaseInsensitiveContains(searchText) }
        }
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            // Items list
            Group {
                if items.isEmpty && !isRefreshing {
                    emptyState
                } else {
                    itemsList
                }
            }

            // FAB buttons
            PadFABButtons(
                padService: padService,
                syncService: syncService,
                onAddItem: onAddItem,
                onItemAdded: { loadItems(animated: true) }
            )
        }
        .searchable(text: $searchText, prompt: "Search items")
        .onAppear {
            loadItems()
        }
        .task {
            await syncService.sync()
            loadItems()
        }
        .toast(isPresented: $toastState.isPresented, message: toastState.message, style: toastState.style)
        .onChange(of: refreshTrigger) { _, _ in
            loadItems(animated: true)
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Items", systemImage: "doc.on.clipboard")
        } description: {
            Text("Tap + to add your first item")
        }
    }

    private var itemsList: some View {
        List {
            if filteredItems.isEmpty && !searchText.isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else {
                ForEach(filteredItems) { item in
                    ItemRow(
                        item: item,
                        padService: padService,
                        onCopy: {
                            copyItem(item)
                        },
                        onDelete: {
                            deleteItem(item)
                        }
                    )
                    .listRowInsets(EdgeInsets())
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            deleteItem(item)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .contentMargins(.bottom, 80, for: .scrollContent)
        .refreshable {
            await refresh()
        }
    }

    func loadItems(animated: Bool = false) {
        let newItems = (try? padService.getDecryptedItems()) ?? []
        if animated {
            withAnimation(.easeInOut(duration: 0.25)) {
                items = newItems
            }
        } else {
            items = newItems
        }
    }

    private func refresh() async {
        isRefreshing = true
        await syncService.sync()
        loadItems()
        isRefreshing = false
    }

    private func copyItem(_ item: DecryptedListItem) {
        padService.copyToClipboard(item.text)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        toastState.showCopied()
    }

    private func deleteItem(_ item: DecryptedListItem) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        Task {
            await syncService.deleteItem(id: item.id)
            loadItems(animated: true)
        }
    }
}

#Preview {
    NavigationStack {
        PadListView(
            padService: PadService(api: APIClient(baseURL: Config.padAPIBaseURL)),
            syncService: SyncService(api: APIClient(baseURL: Config.padAPIBaseURL)),
            onAddItem: {}
        )
    }
    .tint(Theme.Brand.primary)
}
