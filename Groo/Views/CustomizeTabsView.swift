//
//  CustomizeTabsView.swift
//  Groo
//
//  Drag-and-drop tab reordering and tab bar count configuration.
//

import SwiftUI

struct CustomizeTabsView: View {
    @AppStorage("tabOrder") private var tabOrderRaw: String = "pad,pass,scratchpad,drive,crypto,settings"
    @AppStorage("mainTabCount") private var mainTabCount: Int = 2

    @State private var tabs: [TabID] = []

    private func loadTabs() {
        let ids = tabOrderRaw.split(separator: ",").compactMap { TabID(rawValue: String($0)) }
        let missing = TabID.allCases.filter { !ids.contains($0) }
        tabs = ids + missing
    }

    private func saveTabs() {
        tabOrderRaw = tabs.map(\.rawValue).joined(separator: ",")
    }

    var body: some View {
        List {
            Section {
                Picker("Tabs in tab bar", selection: $mainTabCount) {
                    Text("2").tag(2)
                    Text("3").tag(3)
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Tab bar count")
            }

            Section {
                ForEach(Array(tabs.enumerated()), id: \.element) { index, tab in
                    HStack {
                        Image(systemName: tab.icon)
                            .foregroundStyle(index < mainTabCount ? Theme.Brand.primary : .secondary)
                            .frame(width: 24)
                        Text(tab.title)
                        Spacer()
                        if index < mainTabCount {
                            Text("Tab Bar")
                                .font(.caption)
                                .foregroundStyle(Theme.Brand.primary)
                        }
                    }
                }
                .onMove { source, destination in
                    tabs.move(fromOffsets: source, toOffset: destination)
                    saveTabs()
                }
            } header: {
                Text("Drag to reorder")
            } footer: {
                Text("The top \(mainTabCount) items appear in the tab bar. The rest appear in More.")
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
