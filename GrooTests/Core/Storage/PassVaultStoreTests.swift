//
//  PassVaultStoreTests.swift
//  GrooTests
//
//  File-based vault storage against a temp directory (never the real App Group).
//

import Foundation
import Testing
@testable import Groo

struct PassVaultStoreTests {
    /// Fresh store rooted in a unique temp dir per test.
    static func makeStore() -> (store: PassVaultStore, dir: URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PassVaultStoreTests-\(UUID().uuidString)", isDirectory: true)
        return (PassVaultStore(directoryURL: dir), dir)
    }

    static let metadata = PassVaultMetadata(version: 3, iv: "aXYtZml4dHVyZQ==", updatedAt: 1_700_000_000, lastSyncedAt: 1_700_000_100)

    @Test func loadReturnsNilWhenNothingStored() async throws {
        let (store, dir) = Self.makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(try await store.loadVault() == nil)
        #expect(try await store.loadMetadata() == nil)
        #expect(await store.vaultExists() == false)
    }

    @Test func saveThenLoadRoundtrips() async throws {
        let (store, dir) = Self.makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let blob = Data("encrypted-vault-bytes".utf8)

        try await store.saveVault(encryptedData: blob, metadata: Self.metadata)

        let loaded = try #require(await store.loadVault())
        #expect(loaded.data == blob)
        #expect(loaded.metadata.version == 3)
        #expect(loaded.metadata.iv == Self.metadata.iv)
        #expect(await store.vaultExists())
    }

    @Test func updateMetadataLeavesDataIntact() async throws {
        let (store, dir) = Self.makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let blob = Data("blob".utf8)
        try await store.saveVault(encryptedData: blob, metadata: Self.metadata)

        try await store.updateMetadata(PassVaultMetadata(version: 4, iv: Self.metadata.iv, updatedAt: 1_700_000_500, lastSyncedAt: 1_700_000_999))

        let loaded = try #require(await store.loadVault())
        #expect(loaded.data == blob)
        #expect(loaded.metadata.version == 4)
    }

    @Test func overwriteReplacesPreviousVault() async throws {
        let (store, dir) = Self.makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        try await store.saveVault(encryptedData: Data("v1".utf8), metadata: Self.metadata)
        try await store.saveVault(encryptedData: Data("v2".utf8), metadata: Self.metadata)
        let loaded = try #require(await store.loadVault())
        #expect(loaded.data == Data("v2".utf8))
    }

    @Test func clearRemovesEverything() async throws {
        let (store, dir) = Self.makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        try await store.saveVault(encryptedData: Data("v".utf8), metadata: Self.metadata)
        try await store.clear()
        #expect(await store.vaultExists() == false)
        #expect(try await store.loadVault() == nil)
    }

    @Test func corruptMetadataThrowsInsteadOfGarbage() async throws {
        let (store, dir) = Self.makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        try await store.saveVault(encryptedData: Data("v".utf8), metadata: Self.metadata)
        // Corrupt the metadata file on disk
        let metaURL = dir.appendingPathComponent("pass/vault.meta.json")
        try Data("not json".utf8).write(to: metaURL)
        await #expect(throws: (any Error).self) { try await store.loadVault() }
    }

    // MARK: - Concurrency sweep (Phase 6)

    /// saveVault writes the data blob then the metadata with no suspension
    /// point between them — actor isolation makes the pair atomic. 32 racing
    /// writers with interleaved readers must never observe a torn pair
    /// (blob from writer A, metadata from writer B). This is the invariant
    /// that breaks if PassVaultStore ever stops being an actor or saveVault
    /// gains an await between the two writes.
    @Test func concurrentSaveAndLoadNeverTearDataMetadataPairs() async throws {
        let (store, dir) = Self.makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        try await withThrowingTaskGroup(of: Void.self) { group in
            for i in 0..<32 {
                group.addTask {
                    try await store.saveVault(
                        encryptedData: Data("payload-\(i)".utf8),
                        metadata: PassVaultMetadata(version: i, iv: "iv", updatedAt: i, lastSyncedAt: i)
                    )
                }
                group.addTask {
                    // Reads race the writes; nil (nothing written yet) is
                    // fine — a mismatched pair is the failure being hunted
                    if let loaded = try await store.loadVault() {
                        #expect(loaded.data == Data("payload-\(loaded.metadata.version)".utf8),
                                "torn pair: \(String(decoding: loaded.data, as: UTF8.self)) with metadata v\(loaded.metadata.version)")
                    }
                }
            }
            try await group.waitForAll()
        }

        // Terminal state is some writer's complete pair
        let final = try #require(await store.loadVault())
        #expect(final.data == Data("payload-\(final.metadata.version)".utf8))
    }

    @Test func concurrentClearAndSaveLeaveAConsistentTerminalState() async throws {
        let (store, dir) = Self.makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        try await withThrowingTaskGroup(of: Void.self) { group in
            for i in 0..<16 {
                group.addTask {
                    try await store.saveVault(
                        encryptedData: Data("payload-\(i)".utf8),
                        metadata: PassVaultMetadata(version: i, iv: "iv", updatedAt: i, lastSyncedAt: i)
                    )
                }
                if i.isMultiple(of: 4) {
                    group.addTask { try await store.clear() }
                }
            }
            try await group.waitForAll()
        }

        // Whichever interleaving won, the store must agree with itself:
        // fully present (a matched pair) or fully absent — never vaultExists
        // without loadable metadata (that state breaks unlock at launch)
        let exists = await store.vaultExists()
        let loaded = try await store.loadVault()
        #expect((loaded != nil) == exists)
        if let loaded {
            #expect(loaded.data == Data("payload-\(loaded.metadata.version)".utf8))
        }
    }
}

/// SharedVaultStore (extension-side reader) must agree with PassVaultStore
/// (app-side writer) on the on-disk layout — a mismatch means AutoFill
/// silently sees no vault. Serialized: overrideDirectoryURL is static state.
@Suite(.serialized)
struct SharedVaultStoreTests {
    @Test func readsWhatPassVaultStoreWrites() async throws {
        let (store, dir) = PassVaultStoreTests.makeStore()
        defer {
            SharedVaultStore.overrideDirectoryURL = nil
            try? FileManager.default.removeItem(at: dir)
        }
        let blob = Data("encrypted-vault-bytes".utf8)
        try await store.saveVault(encryptedData: blob, metadata: PassVaultStoreTests.metadata)

        SharedVaultStore.overrideDirectoryURL = dir

        #expect(SharedVaultStore.vaultExists())
        let loaded = try SharedVaultStore.loadVault()
        #expect(loaded.data == blob)
        #expect(loaded.metadata.version == PassVaultStoreTests.metadata.version)
        #expect(loaded.metadata.iv == PassVaultStoreTests.metadata.iv)
    }

    @Test func throwsVaultNotFoundWhenEmpty() {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SharedVaultStoreTests-\(UUID().uuidString)", isDirectory: true)
        defer { SharedVaultStore.overrideDirectoryURL = nil }
        SharedVaultStore.overrideDirectoryURL = dir

        #expect(!SharedVaultStore.vaultExists())
        #expect(throws: SharedVaultStoreError.vaultNotFound) { try SharedVaultStore.loadVault() }
    }
}
