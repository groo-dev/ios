//
//  WidgetExtensionBundle.swift
//  WidgetExtension
//
//  Created by Groo on 12/01/2026.
//

import WidgetKit
import SwiftUI

@main
struct WidgetExtensionBundle: WidgetBundle {
    var body: some Widget {
        WidgetExtension()
        WidgetExtensionControl()
        WidgetExtensionLiveActivity()
    }
}
