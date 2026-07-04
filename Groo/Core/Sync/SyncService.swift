//
//  SyncService.swift
//  Groo
//
//  Orchestrates offline-first sync between local storage and API.
//  Stores encrypted items directly (no decryption during sync).
//  Decryption happens on-demand in PadService.
//

import Foundation
import CryptoKit
import Network
import os

@MainActor
@Observable
class SyncService {
    private let api: APIClient
    private let store: LocalStore

    private(set) var state = SyncState()

    // Network monitor
    private let networkMonitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "dev.groo.ios.network")

    init(
        api: APIClient,
        store: LocalStore = .shared
    ) {
        self.api = api
        self.store = store

        setupNetworkMonitoring()
    }

    // MARK: - Network Monitoring

    private func setupNetworkMonitoring() {
        networkMonitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.state.isOnline = path.status == .satisfied
                if path.status == .satisfied {
                    // Trigger sync when coming back online
                    await self?.sync()
                }
            }
        }
        networkMonitor.start(queue: monitorQueue)
    }

    // MARK: - Sync

    /// Full sync: push pending operations, then pull latest from server
    /// No encryption key needed - stores encrypted items directly
    func sync() async {
        guard state.isOnline else { return }

        state.status = .syncing

        do {
            // Push pending operations first
            let pushSucceeded = await pushPendingOperations()

            // Pull latest from server (stores encrypted)
            try await pullFromServer()

            // Don't report a clean sync if any push operation failed
            state.status = pushSucceeded ? .idle : .error("Some changes couldn't be synced")
            state.lastSyncedAt = Date()
        } catch {
            state.status = .error(error.localizedDescription)
        }

        // Update pending count
        state.pendingOperationsCount = store.getAllPendingOperations().count
    }

    // MARK: - Push Operations

    /// Returns true if every pending operation was pushed successfully.
    private func pushPendingOperations() async -> Bool {
        let operations = store.getAllPendingOperations()
        Log.sync.debug("Pending operations: \(operations.count)")

        var allSucceeded = true

        for operation in operations {
            Log.sync.debug("Processing \(operation.operationType.rawValue, privacy: .public): \(operation.id, privacy: .public) (itemId: \(operation.itemId, privacy: .public))")
            do {
                switch operation.operationType {
                case .create:
                    guard let item = operation.getCreatePayload() else {
                        // Do NOT remove the operation — the user's offline-created
                        // item must survive for diagnosis. Skip it this pass.
                        Log.sync.error("CREATE operation \(operation.id, privacy: .public) has missing or undecodable payload; keeping for diagnosis")
                        allSucceeded = false
                        continue
                    }
                    let _: AddItemResponse = try await api.post(APIClient.Endpoint.list, body: item)

                case .delete:
                    do {
                        try await api.delete(APIClient.Endpoint.listItem(operation.itemId))
                    } catch APIError.httpError(statusCode: 404, _) {
                        Log.sync.debug("DELETE \(operation.itemId, privacy: .public): 404 - item already gone, treating as success")
                    }
                }

                // Remove successful operation
                try store.removePendingOperation(operation)
            } catch {
                // Keep failed operations for retry
                Log.sync.error("Failed to push operation \(operation.id, privacy: .public): \(String(describing: error), privacy: .public)")
                allSucceeded = false
            }
        }

        return allSucceeded
    }

    // MARK: - Pull from Server

    private func pullFromServer() async throws {
        let apiState: PadUserState = try await api.get(APIClient.Endpoint.state)

        // Store encrypted items directly (no decryption)
        store.upsertPadItems(apiState.list)

        // Store encrypted scratchpads
        store.upsertScratchpads(apiState.scratchpads)

        // Store active scratchpad ID
        activeId = apiState.activeId
    }

    /// Currently active scratchpad ID
    private(set) var activeId: String = ""

    // MARK: - Local Operations (Immediate + Queue)

    /// Add encrypted item locally and queue for sync
    func addItem(_ encryptedItem: PadListItem) async {
        // Save encrypted item locally
        store.savePadItem(from: encryptedItem)

        // Queue for sync
        guard let operation = PendingOperation.createItem(encryptedItem) else {
            Log.sync.error("Failed to queue create operation for item \(encryptedItem.id, privacy: .public): payload could not be encoded")
            state.status = .error("Couldn't queue item for sync")
            return
        }
        do {
            try store.addPendingOperation(operation)
        } catch {
            state.status = .error("Couldn't queue item for sync")
        }
        state.pendingOperationsCount = store.getAllPendingOperations().count

        // Try to sync immediately if online
        if state.isOnline {
            await sync()
        }
    }

    /// Delete item locally and queue for sync
    func deleteItem(id: String) async {
        // Remove from local storage immediately
        store.deletePadItem(id: id)

        // Queue for sync
        let operation = PendingOperation.deleteItem(id: id)
        do {
            try store.addPendingOperation(operation)
        } catch {
            state.status = .error("Couldn't queue deletion for sync")
        }
        state.pendingOperationsCount = store.getAllPendingOperations().count

        // Try to sync immediately if online
        if state.isOnline {
            await sync()
        }
    }

    // MARK: - Get Encrypted Items

    /// Get all encrypted items from local storage
    func getEncryptedItems() -> [LocalPadItem] {
        store.getAllPadItems()
    }

    /// Clear local storage (on sign out)
    func clearLocalStorage() {
        store.clearAllPadItems()
        store.clearAllScratchpads()
        store.clearPendingOperations()
    }

    // MARK: - Scratchpad Operations

    /// Get all encrypted scratchpads from local storage
    func getEncryptedScratchpads() -> [LocalScratchpad] {
        store.getAllScratchpads()
    }

    /// Get a single encrypted scratchpad by ID
    func getEncryptedScratchpad(id: String) -> LocalScratchpad? {
        store.getScratchpad(id: id)
    }

    /// Get active scratchpad from local storage
    func getActiveScratchpad() -> LocalScratchpad? {
        guard !activeId.isEmpty else { return nil }
        return store.getScratchpad(id: activeId)
    }

    /// Update scratchpad content on server
    func updateScratchpad(id: String, encryptedContent: PadEncryptedPayload) async throws {
        let body = ScratchpadUpdateBody(encryptedContent: encryptedContent)
        let _: ScratchpadUpdateResponse = try await api.put(APIClient.Endpoint.scratchpad(id), body: body)

        // Update local storage. Never write a placeholder payload — on encode
        // failure, keep the previous local copy and log.
        if let local = store.getScratchpad(id: id) {
            do {
                let data = try JSONEncoder().encode(encryptedContent)
                guard let encryptedJSON = String(data: data, encoding: .utf8) else {
                    Log.sync.error("Scratchpad \(id, privacy: .public) update: encoded payload is not valid UTF-8; skipping local cache update")
                    return
                }
                local.encryptedContentJSON = encryptedJSON
                local.updatedAt = Date()
                store.updateScratchpad(local)
            } catch {
                Log.sync.error("Scratchpad \(id, privacy: .public) update: failed to encode payload: \(String(describing: error), privacy: .public); skipping local cache update")
            }
        }
    }

    /// Create a new scratchpad on server
    func createScratchpad(encryptedContent: PadEncryptedPayload) async throws -> String {
        let body = ScratchpadCreateBody(encryptedContent: encryptedContent)
        let response: ScratchpadCreateResponse = try await api.post(APIClient.Endpoint.scratchpads, body: body)

        // Add to local storage. Never write a placeholder payload — on encode
        // failure, skip caching locally and log (the server copy is authoritative).
        let now = Date()
        do {
            let data = try JSONEncoder().encode(encryptedContent)
            if let encryptedJSON = String(data: data, encoding: .utf8) {
                let scratchpad = LocalScratchpad(
                    id: response.id,
                    encryptedContentJSON: encryptedJSON,
                    createdAt: now,
                    updatedAt: now
                )
                store.saveScratchpad(scratchpad)
            } else {
                Log.sync.error("Scratchpad \(response.id, privacy: .public) create: encoded payload is not valid UTF-8; skipping local cache")
            }
        } catch {
            Log.sync.error("Scratchpad \(response.id, privacy: .public) create: failed to encode payload: \(String(describing: error), privacy: .public); skipping local cache")
        }

        return response.id
    }

    /// Delete a scratchpad from server
    func deleteScratchpad(id: String) async throws {
        try await api.delete(APIClient.Endpoint.scratchpad(id))

        // Remove from local storage
        store.deleteScratchpad(id: id)
    }

    /// Add a file attachment to a scratchpad
    func addFileToScratchpad(id: String, file: PadFileAttachment) async throws {
        let body = ScratchpadAddFileBody(file: file)
        let _: ScratchpadUpdateResponse = try await api.post(APIClient.Endpoint.scratchpadFiles(id), body: body)

        // Update local storage
        if let local = store.getScratchpad(id: id) {
            var files = local.files
            files.append(file)
            local.files = files
            local.updatedAt = Date()
            store.updateScratchpad(local)
        }
    }

    /// Clear scratchpads from local storage
    func clearAllScratchpads() {
        store.clearAllScratchpads()
    }
}

// MARK: - Scratchpad API Types

struct ScratchpadUpdateBody: Encodable {
    let encryptedContent: PadEncryptedPayload
}

struct ScratchpadUpdateResponse: Decodable {
    let success: Bool
}

struct ScratchpadCreateBody: Encodable {
    let encryptedContent: PadEncryptedPayload
}

struct ScratchpadCreateResponse: Decodable {
    let id: String
}

struct ScratchpadAddFileBody: Encodable {
    let file: PadFileAttachment
}
