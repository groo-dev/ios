//
//  SignInScreen.swift
//  Groo
//
//  Groo's branding, applied to GrooAuthUI's sign-in view.
//

import GrooAuthUI
import SwiftUI

/// The signed-out state.
///
/// Replaces a hand-written 144-line `LoginView` that `bt/space` had a near-twin
/// of. Everything it did — anchor resolution, error rendering, treating a closed
/// sheet as not-an-error — is now `GrooSignInView`'s. What is left is the part
/// that genuinely differs between the two apps: what this app is called and what
/// it looks like.
///
/// It is a named view rather than an expression inside `ContentView` so that the
/// snapshot test renders the same thing that ships, instead of a copy of these
/// arguments that can drift from them.
struct SignInScreen: View {
    @Environment(AuthService.self) private var authService

    var body: some View {
        GrooSignInView(
            appName: "Groo",
            tagline: "Secure notes, passwords & files",
            icon: Image(systemName: "lock.shield.fill"),
            controller: authService.controller
        )
        .environment(\.grooAuthTheme, .grooApp)
    }
}

#Preview {
    SignInScreen()
        .environment(AuthService())
}
