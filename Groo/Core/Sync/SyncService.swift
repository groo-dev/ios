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
            await pushPendingOperations()

            // Pull latest from server (stores encrypted)
            try await pullFromServer()

            state.status = .idle
            state.lastSyncedAt = Date()
        } catch {
            state.status = .error(error.localizedDescription)
        }

        // Update pending count
        state.pendingOperationsCount = store.getAllPendingOperations().count
    }

    // MARK: - Push Operations

    private func pushPendingOperations() async {
        let operations = store.getAllPendingOperations()
        print("[Sync] Pending operations: \(operations.count)")

        for operation in operations {
            print("[Sync] Processing \(operation.operationType): \(operation.id) (itemId: \(operation.itemId))")
            do {
                switch operation.operationType {
                case .create:
                    print("[Sync] CREATE: Posting item \(operation.itemId)")
                    if let item = operation.getCreatePayload() {
                        let _: AddItemResponse = try await api.post(APIClient.Endpoint.list, body: item)
                        print("[Sync] CREATE: Success")
                    } else {
                        print("[Sync] CREATE: No payload, removing stale operation")
                    }

                case .delete:
                    print("[Sync] DELETE: Deleting item \(operation.itemId)")
                    do {
                        try await api.delete(APIClient.Endpoint.listItem(operation.itemId))
                        print("[Sync] DELETE: Success")
                    } catch APIError.httpError(statusCode: 404, _) {
                        print("[Sync] DELETE: 404 - item already gone, treating as success")
                    }
                }

                // Remove successful operation
                print("[Sync] Removing operation \(operation.id)")
                store.removePendingOperation(operation)
            } catch {
                // Keep failed operations for retry
                print("[Sync] FAILED operation \(operation.id): \(error)")
            }
        }
    }

    // MARK: - Pull from Server

    private func pullFromServer() async throws {
        let apiState: PadUserState = try await api.get(APIClient.Endpoint.state)

        // Store encrypted items directly (no decryption)
        store.upsertPadItems(apiState.list)
    }

    // MARK: - Local Operations (Immediate + Queue)

    /// Add encrypted item locally and queue for sync
    func addItem(_ encryptedItem: PadListItem) async {
        // Save encrypted item locally
        store.savePadItem(from: encryptedItem)

        // Queue for sync
        let operation = PendingOperation.createItem(encryptedItem)
        store.addPendingOperation(operation)
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
        store.addPendingOperation(operation)
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
        store.clearPendingOperations()
    }
}
