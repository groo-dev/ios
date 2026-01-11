//
//  GrooApp.swift
//  Groo
//
//  Main app entry point with environment setup.
//

import SwiftUI
import SwiftData

@main
struct GrooApp: App {
    @State private var authService = AuthService()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(authService)
                .modelContainer(LocalStore.shared.container)
        }
    }
}
