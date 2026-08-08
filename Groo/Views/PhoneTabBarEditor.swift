//
//  PhoneTabBarEditor.swift
//  Groo
//
//  Three zones: Home (toggle only, pinned first), the draggable features, and
//  Settings (frozen last). The cut marker shows where the tab bar ends and
//  More begins — it moves when Home is toggled, because Home occupies a bar
//  slot. No add/remove: every reachable permutation is valid, so no tap can
//  be rejected and there is no invalid intermediate state to explain.
//

import SwiftUI

struct PhoneTabBarEditor: View {
    @Environment(TabConfigurationStore.self) private var store

    /// Draggable rows that land in the tab bar. Home takes a slot when on.
    private var draggableBarSlots: Int {
        max(0, TabConfiguration.barSlots - (store.configuration.showsHome ? 1 : 0))
    }

    var body: some View {
        List {
            Section {
                Toggle(isOn: Binding(
                    get: { store.configuration.showsHome },
                    set: { newValue in
                        var config = store.configuration
                        config.setShowsHome(newValue)
                        store.configuration = config
                    }
                )) {
                    Label {
                        Text(TabID.home.title)
                    } icon: {
                        Image(systemName: TabID.home.icon)
                            .environment(\.symbolVariants, .none)
                    }
                }
                .accessibilityIdentifier("tabeditor.home.toggle")
            } header: {
                Text("Home")
            } footer: {
                Text("Home is always the first tab when enabled.")
            }

            Section {
                ForEach(Array(store.configuration.order.enumerated()), id: \.element) { index, tab in
                    HStack {
                        Label {
                            Text(tab.title)
                        } icon: {
                            Image(systemName: tab.icon)
                                .environment(\.symbolVariants, .none)
                        }
                        Spacer()
                        Text(index < draggableBarSlots ? "Tab Bar" : "More")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityIdentifier("tabeditor.row.\(tab.rawValue)")
                }
                .onMove { source, destination in
                    var config = store.configuration
                    config.move(fromOffsets: source, toOffset: destination)
                    store.configuration = config
                }
            } header: {
                Text("Order")
            } footer: {
                Text("The first \(TabConfiguration.barSlots) entries appear in the tab bar. Everything below moves into More.")
            }

            Section {
                Label {
                    Text(TabID.settings.title)
                } icon: {
                    Image(systemName: TabID.settings.icon)
                        .environment(\.symbolVariants, .none)
                }
                .foregroundStyle(.secondary)
            } footer: {
                Text("Settings is always the last item in More.")
            }
        }
        .environment(\.editMode, .constant(.active))
        .navigationTitle("Customize Tabs")
    }
}
