//
//  InMemoryLocalStore.swift
//  GrooTests
//
//  Fresh LocalStore instances over isolated in-memory SwiftData containers.
//  Tests never touch LocalStore.shared (App Group store).
//

import Foundation
import SwiftData
@testable import Groo

@MainActor
enum InMemoryLocalStore {
    /// A fresh LocalStore backed by an isolated in-memory container.
    static func make() throws -> LocalStore {
        let config = ModelConfiguration(schema: LocalStore.schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: LocalStore.schema, configurations: [config])
        return LocalStore(container: container)
    }
}
