//
//  LocalStore.swift
//  Groo
//
//  SwiftData container stored in App Group for extension access.
//

import Foundation
import SwiftData
import os

@MainActor
final class LocalStore {
    // Under --uitest every LocalStore.shared caller gets an in-memory store;
    // the real App Group store is never opened in that mode.
    static let shared: LocalStore = UITestMode.isActive
        ? LocalStore(container: UITestMode.makeInMemoryModelContainer())
        : LocalStore()

    let container: ModelContainer

    /// Full app schema — shared by the App Group store and test containers.
    static let schema = Schema([
        LocalPadItem.self,
        LocalScratchpad.self,
        PendingOperation.self,
        CachedTokenPrice.self,
        LocalStockHolding.self,
        LocalStockTransaction.self,
        LocalAzanPreferences.self,
        PrayerLog.self,
    ])

    /// Testing seam: wrap an injected container (e.g. in-memory). The
    /// `shared` App Group store is unaffected.
    init(container: ModelContainer) {
        self.container = container
    }

    private init() {
        let schema = Self.schema

        // Configure for App Group storage
        let config = ModelConfiguration(
            schema: schema,
            groupContainer: .identifier(Config.appGroupIdentifier)
        )

        do {
            container = try ModelContainer(for: schema, configurations: [config])
        } catch {
            // Container creation failed (e.g. schema migration). Move the store
            // aside so its data stays recoverable, then recreate a fresh one.
            Log.store.fault("ModelContainer creation failed, moving store aside and recreating: \(String(describing: error), privacy: .public)")

            let url = config.url
            let suffix = "corrupt-\(Int(Date().timeIntervalSince1970))"
            let files = [url, url.appendingPathExtension("wal"), url.appendingPathExtension("shm")]
            for file in files {
                guard FileManager.default.fileExists(atPath: file.path) else { continue }
                let backup = file.appendingPathExtension(suffix)
                do {
                    try FileManager.default.moveItem(at: file, to: backup)
                } catch {
                    Log.store.fault("Failed to move store file aside (\(file.lastPathComponent, privacy: .public)): \(String(describing: error), privacy: .public); deleting instead")
                    try? FileManager.default.removeItem(at: file)
                }
            }

            // Flag for UI to surface that local-only data was reset
            UserDefaults.standard.set(true, forKey: "localStoreWasReset")

            do {
                container = try ModelContainer(for: schema, configurations: [config])
            } catch {
                fatalError("Failed to create ModelContainer after reset: \(error)")
            }
        }
    }

    var context: ModelContext {
        container.mainContext
    }

    // MARK: - Save/Fetch Helpers

    /// Save the context, logging (but swallowing) any error.
    private func saveContext(_ operation: String) {
        do {
            try context.save()
        } catch {
            Log.store.error("\(operation, privacy: .public) save failed: \(String(describing: error), privacy: .public)")
        }
    }

    /// Save the context, logging and rethrowing any error.
    private func saveContextOrThrow(_ operation: String) throws {
        do {
            try context.save()
        } catch {
            Log.store.error("\(operation, privacy: .public) save failed: \(String(describing: error), privacy: .public)")
            throw error
        }
    }

    /// Fetch, logging any error before returning an empty result.
    private func fetchOrEmpty<T: PersistentModel>(_ descriptor: FetchDescriptor<T>, _ operation: String) -> [T] {
        do {
            return try context.fetch(descriptor)
        } catch {
            Log.store.error("\(operation, privacy: .public) fetch failed: \(String(describing: error), privacy: .public)")
            return []
        }
    }

    /// Fetch the first match, logging any error before returning nil.
    private func fetchFirst<T: PersistentModel>(_ descriptor: FetchDescriptor<T>, _ operation: String) -> T? {
        do {
            return try context.fetch(descriptor).first
        } catch {
            Log.store.error("\(operation, privacy: .public) fetch failed: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    // MARK: - Pad Items

    func getAllPadItems() -> [LocalPadItem] {
        let descriptor = FetchDescriptor<LocalPadItem>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        return fetchOrEmpty(descriptor, "getAllPadItems")
    }

    func getPadItem(id: String) -> LocalPadItem? {
        let descriptor = FetchDescriptor<LocalPadItem>(
            predicate: #Predicate { $0.id == id }
        )
        return fetchFirst(descriptor, "getPadItem")
    }

    func savePadItem(_ item: LocalPadItem) {
        context.insert(item)
        saveContext("savePadItem")
    }

    func deletePadItem(id: String) {
        if let item = getPadItem(id: id) {
            context.delete(item)
            saveContext("deletePadItem")
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
            if let local = LocalPadItem(from: item) {
                context.insert(local)
            }
        }

        saveContext("upsertPadItems")
    }

    /// Save a single encrypted item
    func savePadItem(from apiItem: PadListItem) {
        guard let local = LocalPadItem(from: apiItem) else { return }
        context.insert(local)
        saveContext("savePadItem(from:)")
    }

    func clearAllPadItems() {
        let items = getAllPadItems()
        for item in items {
            context.delete(item)
        }
        saveContext("clearAllPadItems")
    }

    // MARK: - Scratchpads

    func getAllScratchpads() -> [LocalScratchpad] {
        let descriptor = FetchDescriptor<LocalScratchpad>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        return fetchOrEmpty(descriptor, "getAllScratchpads")
    }

    func getScratchpad(id: String) -> LocalScratchpad? {
        let descriptor = FetchDescriptor<LocalScratchpad>(
            predicate: #Predicate { $0.id == id }
        )
        return fetchFirst(descriptor, "getScratchpad")
    }

    func saveScratchpad(_ scratchpad: LocalScratchpad) {
        context.insert(scratchpad)
        saveContext("saveScratchpad")
    }

    func deleteScratchpad(id: String) {
        if let scratchpad = getScratchpad(id: id) {
            context.delete(scratchpad)
            saveContext("deleteScratchpad")
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
            if let local = LocalScratchpad(from: scratchpad) {
                context.insert(local)
            }
        }

        saveContext("upsertScratchpads")
    }

    /// Update a single scratchpad
    func updateScratchpad(_ scratchpad: LocalScratchpad) {
        saveContext("updateScratchpad")
    }

    func clearAllScratchpads() {
        let scratchpads = getAllScratchpads()
        for scratchpad in scratchpads {
            context.delete(scratchpad)
        }
        saveContext("clearAllScratchpads")
    }

    // MARK: - Pending Operations

    func getAllPendingOperations() -> [PendingOperation] {
        let descriptor = FetchDescriptor<PendingOperation>(
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        return fetchOrEmpty(descriptor, "getAllPendingOperations")
    }

    func addPendingOperation(_ operation: PendingOperation) throws {
        context.insert(operation)
        try saveContextOrThrow("addPendingOperation")
    }

    func removePendingOperation(_ operation: PendingOperation) throws {
        context.delete(operation)
        try saveContextOrThrow("removePendingOperation")
    }

    func clearPendingOperations() {
        let operations = getAllPendingOperations()
        for op in operations {
            context.delete(op)
        }
        saveContext("clearPendingOperations")
    }

    // MARK: - Cached Portfolio

    func getCachedPortfolio(wallet: String) -> [CachedTokenPrice] {
        let lowered = wallet.lowercased()
        let descriptor = FetchDescriptor<CachedTokenPrice>(
            predicate: #Predicate { $0.walletAddress == lowered },
            sortBy: [SortDescriptor(\CachedTokenPrice.priceUSD, order: .reverse)]
        )
        return fetchOrEmpty(descriptor, "getCachedPortfolio")
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

        saveContext("upsertCachedPortfolio")
    }

    func clearCachedPortfolio(wallet: String) {
        let items = getCachedPortfolio(wallet: wallet)
        for item in items {
            context.delete(item)
        }
        saveContext("clearCachedPortfolio")
    }

    // MARK: - Stock Holdings

    func getAllStockHoldings() -> [LocalStockHolding] {
        let descriptor = FetchDescriptor<LocalStockHolding>()
        return fetchOrEmpty(descriptor, "getAllStockHoldings")
    }

    func getStockHolding(symbol: String) -> LocalStockHolding? {
        let descriptor = FetchDescriptor<LocalStockHolding>(
            predicate: #Predicate { $0.symbol == symbol }
        )
        return fetchFirst(descriptor, "getStockHolding")
    }

    func getStockTransaction(id: String) -> LocalStockTransaction? {
        let descriptor = FetchDescriptor<LocalStockTransaction>(
            predicate: #Predicate { $0.id == id }
        )
        return fetchFirst(descriptor, "getStockTransaction")
    }

    func saveStockHolding(_ holding: LocalStockHolding) {
        context.insert(holding)
        saveContext("saveStockHolding")
    }

    func deleteStockHolding(_ holding: LocalStockHolding) {
        context.delete(holding)
        saveContext("deleteStockHolding")
    }

    func deleteStockTransaction(_ transaction: LocalStockTransaction) {
        context.delete(transaction)
        saveContext("deleteStockTransaction")
    }

    func saveStockChanges() {
        saveContext("saveStockChanges")
    }

    // MARK: - Azan Preferences

    func getAzanPreferences() -> LocalAzanPreferences? {
        let id = "default"
        let descriptor = FetchDescriptor<LocalAzanPreferences>(
            predicate: #Predicate { $0.id == id }
        )
        return fetchFirst(descriptor, "getAzanPreferences")
    }

    func saveAzanPreferences(_ prefs: LocalAzanPreferences) {
        // Delete existing and insert fresh
        if let existing = getAzanPreferences() {
            context.delete(existing)
        }
        context.insert(prefs)
        saveContext("saveAzanPreferences")
    }

    func saveAzanChanges() {
        saveContext("saveAzanChanges")
    }

    // MARK: - Prayer Logs

    func getPrayerLogs(forDateString dateString: String) -> [PrayerLog] {
        let descriptor = FetchDescriptor<PrayerLog>(
            predicate: #Predicate { $0.dateString == dateString }
        )
        return fetchOrEmpty(descriptor, "getPrayerLogs(forDateString:)")
    }

    func getPrayerLogs(from startDate: String, to endDate: String) -> [PrayerLog] {
        let descriptor = FetchDescriptor<PrayerLog>(
            predicate: #Predicate { $0.dateString >= startDate && $0.dateString <= endDate }
        )
        return fetchOrEmpty(descriptor, "getPrayerLogs(from:to:)")
    }

    func savePrayerLog(_ log: PrayerLog) {
        // Upsert: delete existing log for same prayer+date, then insert
        let logId = log.id
        let descriptor = FetchDescriptor<PrayerLog>(
            predicate: #Predicate { $0.id == logId }
        )
        if let existing = fetchFirst(descriptor, "savePrayerLog") {
            context.delete(existing)
        }
        context.insert(log)
        saveContext("savePrayerLog")
    }

    func deletePrayerLog(dateString: String, prayer: Prayer) {
        let logId = "\(dateString)_\(prayer.rawValue)"
        let descriptor = FetchDescriptor<PrayerLog>(
            predicate: #Predicate { $0.id == logId }
        )
        if let existing = fetchFirst(descriptor, "deletePrayerLog") {
            context.delete(existing)
            saveContext("deletePrayerLog")
        }
    }
}
