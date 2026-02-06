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
            LocalScratchpad.self,
            PendingOperation.self,
            CachedTokenPrice.self,
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

    // MARK: - Scratchpads

    func getAllScratchpads() -> [LocalScratchpad] {
        let descriptor = FetchDescriptor<LocalScratchpad>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    func getScratchpad(id: String) -> LocalScratchpad? {
        let descriptor = FetchDescriptor<LocalScratchpad>(
            predicate: #Predicate { $0.id == id }
        )
        return try? context.fetch(descriptor).first
    }

    func saveScratchpad(_ scratchpad: LocalScratchpad) {
        context.insert(scratchpad)
        try? context.save()
    }

    func deleteScratchpad(id: String) {
        if let scratchpad = getScratchpad(id: id) {
            context.delete(scratchpad)
            try? context.save()
        }
    }

    /// Upsert encrypted scratchpads from API (no decryption needed)
    func upsertScratchpads(_ scratchpads: [String: PadScratchpad]) {
        // Delete all existing scratchpads
        let existing = getAllScratchpads()
        for scratchpad in existing {
            context.delete(scratchpad)
        }

        // Insert new scratchpads (stored encrypted)
        for (_, scratchpad) in scratchpads {
            context.insert(LocalScratchpad(from: scratchpad))
        }

        try? context.save()
    }

    /// Update a single scratchpad
    func updateScratchpad(_ scratchpad: LocalScratchpad) {
        try? context.save()
    }

    func clearAllScratchpads() {
        let scratchpads = getAllScratchpads()
        for scratchpad in scratchpads {
            context.delete(scratchpad)
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

    // MARK: - Cached Portfolio

    func getCachedPortfolio(wallet: String) -> [CachedTokenPrice] {
        let lowered = wallet.lowercased()
        let descriptor = FetchDescriptor<CachedTokenPrice>(
            predicate: #Predicate { $0.walletAddress == lowered },
            sortBy: [SortDescriptor(\CachedTokenPrice.priceUSD, order: .reverse)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    func upsertCachedPortfolio(_ assets: [CryptoAsset], wallet: String) {
        let lowered = wallet.lowercased()

        // Delete existing cache for this wallet
        let existing = getCachedPortfolio(wallet: lowered)
        for item in existing {
            context.delete(item)
        }

        // Insert fresh cache
        let now = Date()
        for asset in assets {
            context.insert(CachedTokenPrice(
                id: "\(lowered)_\(asset.id.lowercased())",
                walletAddress: lowered,
                symbol: asset.symbol,
                name: asset.name,
                balance: asset.balance,
                priceUSD: asset.price,
                priceChange24h: asset.priceChange24h,
                decimals: asset.decimals,
                contractAddress: asset.contractAddress,
                updatedAt: now
            ))
        }

        try? context.save()
    }

    func clearCachedPortfolio(wallet: String) {
        let items = getCachedPortfolio(wallet: wallet)
        for item in items {
            context.delete(item)
        }
        try? context.save()
    }
}
