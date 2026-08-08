//
//  PushedDestinationEnvironment.swift
//  Groo
//
//  Lets a stack-free feature screen (see FeatureContent) tell whether it is
//  rendering as a tab root or as a destination MoreView pushed on top of an
//  existing NavigationStack. A couple of screens hide the navigation bar
//  they would otherwise inherit because they never had one as a tab root —
//  PadUnlockView, and ScratchpadView's regular-width branch — but hiding it
//  again when pushed from More removes the pushed screen's only visible
//  back-button affordance (edge-swipe still works, but nothing shows it).
//

import SwiftUI

private struct IsPushedDestinationKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// True when the current screen was pushed by `MoreView` rather than
    /// rendered as a tab root. Defaults to false so tab-root rendering is
    /// unchanged; `MoreView` sets it true on its `navigationDestination`
    /// content.
    var isPushedDestination: Bool {
        get { self[IsPushedDestinationKey.self] }
        set { self[IsPushedDestinationKey.self] = newValue }
    }
}
