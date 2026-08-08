//
//  CustomizeTabsEntry.swift
//  Groo
//
//  The one place tab customization branches on idiom. iPad keeps the system's
//  own tab customization (tabViewCustomization on MainTabView), so it gets the
//  informational list; iPhone gets the editor. Isolated to this file so no
//  feature view carries an idiom conditional.
//

import SwiftUI
import UIKit

struct CustomizeTabsEntry: View {
    var body: some View {
        if UIDevice.current.userInterfaceIdiom == .pad {
            CustomizeTabsView()
        } else {
            PhoneTabBarEditor()
        }
    }
}
