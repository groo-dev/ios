//
//  LocalStore.swift
//  Groo
//
//  SwiftData container stored in App Group for extension access.
//

import Foundation
import SwiftData

@MainActor
final class LocalStore {
    static let shared = LocalStore()

    let container: ModelContainer

    private init() {
        let schema = Schema([
            LocalPadItem.self,
            PendingOperation.self,
        ])

        // Configure for App Group storage
        let config = ModelConfiguration(
            schema: schema,
            groupContainer: .identifier(Config.appGroupIdentifier)
        )

        do {
            container = try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    var context: ModelContext {
        container.mainContext
    }

    // MARK: - Pad Items

    func getAllPadItems() -> [LocalPadItem] {
        let descriptor = FetchDescriptor<LocalPadItem>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    func getPadItem(id: String) -> LocalPadItem? {
        let descriptor = FetchDescriptor<LocalPadItem>(
            predicate: #Predicate { $0.id == id }
        )
        return try? context.fetch(descriptor).first
    }

    func savePadItem(_ item: LocalPadItem) {
        context.insert(item)
        try? context.save()
    }

    func deletePadItem(id: String) {
        if let item = getPadItem(id: id) {
            context.delete(item)
            try? context.save()
        }
    }

    /// Upsert encrypted items from API (no decryption needed)
    func upsertPadItems(_ items: [PadListItem]) {
        // Delete all existing items
        let existing = getAllPadItems()
        for item in existing {
            context.delete(item)
        }

        // Insert new items (stored encrypted)
        for item in items {
            context.insert(LocalPadItem(from: item))
        }

        try? context.save()
    }

    /// Save a single encrypted item
    func savePadItem(from apiItem: PadListItem) {
        context.insert(LocalPadItem(from: apiItem))
        try? context.save()
    }

    func clearAllPadItems() {
        let items = getAllPadItems()
        for item in items {
            context.delete(item)
        }
        try? context.save()
    }

    // MARK: - Pending Operations

    func getAllPendingOperations() -> [PendingOperation] {
        let descriptor = FetchDescriptor<PendingOperation>(
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    func addPendingOperation(_ operation: PendingOperation) {
        context.insert(operation)
        try? context.save()
    }

    func removePendingOperation(_ operation: PendingOperation) {
        context.delete(operation)
        try? context.save()
    }

    func clearPendingOperations() {
        let operations = getAllPendingOperations()
        for op in operations {
            context.delete(op)
        }
        try? context.save()
    }
}
