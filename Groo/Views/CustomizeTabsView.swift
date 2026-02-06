//
//  CustomizeTabsView.swift
//  Groo
//
//  Tab customization info view.
//

import SwiftUI

struct CustomizeTabsView: View {
    var body: some View {
        List {
            Section {
                ForEach(TabID.allCases, id: \.self) { tab in
                    HStack {
                        Image(systemName: tab.icon)
                            .foregroundStyle(Theme.Brand.primary)
                            .frame(width: 24)
                        Text(tab.title)
                    }
                }
            } header: {
                Text("Current tabs")
            } footer: {
                Text("Long-press the tab bar or use the sidebar to rearrange tabs.")
            }
        }
        .navigationTitle("Customize Tabs")
    }
}

#Preview {
    NavigationStack {
        CustomizeTabsView()
    }
}
