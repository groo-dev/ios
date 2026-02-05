//
//  CustomizeTabsView.swift
//  Groo
//
//  Drag-to-reorder tab customization.
//

import SwiftUI

struct CustomizeTabsView: View {
    @AppStorage("tabOrder") private var tabOrderRaw: String = TabID.defaultOrder

    @State private var tabs: [TabID] = []
    @State private var hasChanges = false

    private func loadTabs() {
        tabs = TabID.fromStoredOrder(tabOrderRaw)
    }

    private func saveTabs() {
        tabOrderRaw = tabs.map(\.rawValue).joined(separator: ",")
    }

    var body: some View {
        List {
            Section {
                ForEach(tabs, id: \.self) { tab in
                    HStack {
                        Image(systemName: tab.icon)
                            .foregroundStyle(Theme.Brand.primary)
                            .frame(width: 24)
                        Text(tab.title)
                    }
                }
                .onMove { source, destination in
                    tabs.move(fromOffsets: source, toOffset: destination)
                    saveTabs()
                    hasChanges = true
                }
            } header: {
                Text("Drag to reorder")
            }

            if hasChanges {
                Section {
                    Text("Restart app to see updated tab order")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .navigationTitle("Customize Tabs")
        .environment(\.editMode, .constant(.active))
        .onAppear { loadTabs() }
    }
}

#Preview {
    NavigationStack {
        CustomizeTabsView()
    }
}
