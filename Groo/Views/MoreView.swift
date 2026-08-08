//
//  MoreView.swift
//  Groo
//
//  The iPhone overflow screen: an index of every feature past the tab-bar cut,
//  with Settings pinned last. Its single job is to be a list of destinations —
//  every row pushes through one navigationDestination, which works no matter
//  how many features fall past the cut, because FeatureContent is stack-free.
//

import SwiftUI

struct MoreView: View {
    let configuration: TabConfiguration
    let content: FeatureContent
    @Binding var path: [TabID]

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if !configuration.moreTabs.isEmpty {
                    Section {
                        ForEach(configuration.moreTabs, id: \.self) { tab in
                            NavigationLink(value: tab) { row(for: tab) }
                        }
                    }
                }

                Section {
                    NavigationLink(value: TabID.settings) { row(for: .settings) }
                }
            }
            .navigationTitle("More")
            .navigationDestination(for: TabID.self) { tab in
                content.view(for: tab)
                    .environment(\.isPushedDestination, true)
            }
        }
    }

    private func row(for tab: TabID) -> some View {
        Label {
            Text(tab.title)
        } icon: {
            Image(systemName: tab.icon)
                .environment(\.symbolVariants, .none)
                .foregroundStyle(Theme.Brand.primary)
        }
        .accessibilityIdentifier("more.row.\(tab.rawValue)")
    }
}
