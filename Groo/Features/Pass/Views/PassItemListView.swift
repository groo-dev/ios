//
//  PassItemListView.swift
//  Groo
//
//  Main list view for displaying vault items with search and filtering.
//

import SwiftUI

struct PassItemListView: View {
    let passService: PassService
    let onSelectItem: (PassVaultItem) -> Void

    @State private var searchText = ""
    @State private var selectedType: PassVaultItemType?
    @State private var showingTypeFilter = false
    @State private var copiedItemId: String?

    private var items: [PassVaultItem] {
        if !searchText.isEmpty {
            return passService.searchItems(query: searchText)
        }
        return passService.getItems(type: selectedType)
    }

    private var favorites: [PassVaultItem] {
        passService.getFavorites()
    }

    var body: some View {
        List {
            // Favorites section (when not searching or filtering)
            if searchText.isEmpty && selectedType == nil && !favorites.isEmpty {
                Section {
                    ForEach(favorites) { item in
                        PassItemRow(
                            item: item,
                            onTap: { onSelectItem(item) },
                            onCopyPassword: passwordCopyAction(for: item)
                        )
                    }
                } header: {
                    Label("Favorites", systemImage: "star.fill")
                        .foregroundStyle(.yellow)
                }
            }

            // All items section
            Section {
                if items.isEmpty {
                    emptyState
                } else {
                    ForEach(items) { item in
                        PassItemRow(
                            item: item,
                            onTap: { onSelectItem(item) },
                            onCopyPassword: passwordCopyAction(for: item)
                        )
                    }
                }
            } header: {
                if selectedType != nil {
                    Text(selectedType!.label + "s")
                } else if !searchText.isEmpty {
                    Text("Search Results")
                } else {
                    Text("All Items")
                }
            }
        }
        .listStyle(.insetGrouped)
        .searchable(text: $searchText, prompt: "Search passwords...")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        selectedType = nil
                    } label: {
                        Label("All Types", systemImage: selectedType == nil ? "checkmark" : "")
                    }

                    Divider()

                    ForEach(PassVaultItemType.allCases, id: \.self) { type in
                        Button {
                            selectedType = type
                        } label: {
                            Label(type.label, systemImage: selectedType == type ? "checkmark" : type.icon)
                        }
                    }
                } label: {
                    Image(systemName: selectedType?.icon ?? "line.3.horizontal.decrease.circle")
                        .foregroundStyle(selectedType != nil ? Theme.Brand.primary : .secondary)
                }
            }
        }
        .overlay {
            if let itemId = copiedItemId {
                copiedToast
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            withAnimation {
                                if copiedItemId == itemId {
                                    copiedItemId = nil
                                }
                            }
                        }
                    }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: selectedType?.icon ?? "key.fill")
                .font(.largeTitle)
                .foregroundStyle(.tertiary)

            if !searchText.isEmpty {
                Text("No results for \"\(searchText)\"")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            } else if let type = selectedType {
                Text("No \(type.label.lowercased())s yet")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            } else {
                Text("No items in your vault")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                Text("Add passwords, cards, and notes to get started")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.xxl)
    }

    private var copiedToast: some View {
        VStack {
            Spacer()
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Password copied")
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.vertical, Theme.Spacing.md)
            .background(.regularMaterial)
            .clipShape(Capsule())
            .shadow(radius: 4)
            .padding(.bottom, Theme.Spacing.xl)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func passwordCopyAction(for item: PassVaultItem) -> (() -> Void)? {
        guard case .password(let passwordItem) = item else { return nil }
        return {
            passService.copyToClipboard(passwordItem.password)
            withAnimation {
                copiedItemId = item.id
            }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }
}

#Preview {
    NavigationStack {
        PassItemListView(
            passService: PassService(),
            onSelectItem: { _ in }
        )
        .navigationTitle("Pass")
    }
}
