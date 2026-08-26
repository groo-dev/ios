//
//  PassServiceIntegrationTests.swift
//  GrooTests
//
//  Full vault lifecycle against stubbed network, fake keychain, temp-dir
//  storage. Serialized: StubURLProtocol uses static state. Nested under
//  NetworkStubbedSuites so it also serializes relative to
//  PassAPIClientTests, which shares the same static stub state.
//

import CryptoKit
import Foundation
import Testing
@testable import Groo

extension NetworkStubbedSuites {

@MainActor
@Suite(.serialized)
struct PassServiceIntegrationTests {

    struct Env {
        let service: PassService
        let keychain: InMemoryKeychain
        let credentials: RecordingCredentialService
        let key: SymmetricKey
        let salt: Data
        let tempDir: URL
        let pending: InMemoryPendingPasskeyStore
        let pendingPasswords: InMemoryPendingPasswordStore
        let server: PassRecordTestServer
    }

    static let crypto = CryptoService()
    static let password = "test-master-password"
    static let iterations: UInt32 = 1_000

    /// Build a PassService wired entirely to fakes, backed by an in-memory
    /// record server seeded with `items`/`folders`, so `unlock(password:)`
    /// succeeds with them inside.
    static func makeEnv(
        items: [PassVaultItem],
        folders: [PassFolder] = [],
        pending: InMemoryPendingPasskeyStore = InMemoryPendingPasskeyStore(),
        pendingPasswords: InMemoryPendingPasswordStore = InMemoryPendingPasswordStore()
    ) throws -> Env {
        StubURLProtocol.reset()

        let salt = Data("integration-salt".utf8)
        // The passphrase-derived key only wraps the vault key — it never
        // encrypts vault content. `key` (below) is the vault key, exactly what
        // PassService ends up storing/using after unlock.
        let wrappingKey = try crypto.deriveKey(password: password, salt: salt, iterations: iterations)
        let key = crypto.generateContentKey()
        let wrapped = try crypto.wrapKey(key, using: wrappingKey)

        let server = PassRecordTestServer(
            keyInfoJSON: #"{"keySalt":"\#(salt.base64EncodedString())","kdfIterations":\#(iterations),"wrappedVaultKey":"\#(wrapped.ciphertext)","wrapIv":"\#(wrapped.iv)"}"#)
        for item in items {
            try server.seed(id: item.id, kind: .item,
                            payload: try JSONEncoder().encode(item), vaultKey: key)
        }
        for folder in folders {
            try server.seed(id: folder.id, kind: .folder,
                            payload: try JSONEncoder().encode(folder), vaultKey: key)
        }
        server.install()

        let keychain = InMemoryKeychain()
        let credentials = RecordingCredentialService()
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PassServiceTests-\(UUID().uuidString)", isDirectory: true)

        let api = PassAPIClient(
            tokenProvider: { "test-token" },
            forceRefresh: { "test-token-2" },
            sessionConfiguration: StubURLProtocol.stubbedConfiguration())

        let service = PassService(
            api: api,
            crypto: crypto,
            keychain: keychain,
            vaultStore: PassVaultStore(directoryURL: tempDir),
            credentialService: credentials,
            pendingPasskeys: pending,
            pendingPasswords: pendingPasswords)

        return Env(service: service, keychain: keychain, credentials: credentials,
                   key: key, salt: salt, tempDir: tempDir, pending: pending,
                   pendingPasswords: pendingPasswords, server: server)
    }

    // MARK: Unlock

    @Test func unlockWithCorrectPasswordLoadsVault() async throws {
        let item = PassVaultItem.password(VaultItemFixtures.samplePasswordItem())
        let env = try Self.makeEnv(items: [item])
        defer { try? FileManager.default.removeItem(at: env.tempDir) }

        let unlocked = try await env.service.unlock(password: Self.password)

        #expect(unlocked)
        #expect(env.service.isUnlocked)
        #expect(env.service.getItems().map(\.id) == ["pw-1"])
        // Key must be stored for future biometric unlock
        #expect(env.keychain.biometricProtectedKeyExists(for: KeychainService.Key.passEncryptionKey))
        #expect(env.service.canUnlockWithBiometric)
    }

    @Test func unlockWithWrongPasswordFailsLoudlyAndStaysLocked() async throws {
        let env = try Self.makeEnv(items: [])
        defer { try? FileManager.default.removeItem(at: env.tempDir) }

        await #expect(throws: (any Error).self) {
            _ = try await env.service.unlock(password: "wrong-password")
        }
        #expect(!env.service.isUnlocked)
        #expect(env.service.getItems().isEmpty)
    }

    @Test func lockClearsAccessButKeepsBiometricKey() async throws {
        let env = try Self.makeEnv(items: [.password(VaultItemFixtures.samplePasswordItem())])
        defer { try? FileManager.default.removeItem(at: env.tempDir) }
        _ = try await env.service.unlock(password: Self.password)

        env.service.lock()

        #expect(!env.service.isUnlocked)
        #expect(env.service.getItems().isEmpty)
        #expect(env.service.canUnlockWithBiometric)  // lock() ≠ lockAndClearKey()
    }

    @Test func biometricUnlockSucceedsWithZeroNetwork() async throws {
        let item = PassVaultItem.password(VaultItemFixtures.samplePasswordItem())
        let env = try Self.makeEnv(items: [item])
        defer { try? FileManager.default.removeItem(at: env.tempDir) }

        // First unlock populates keychain + vault cache
        _ = try await env.service.unlock(password: Self.password)
        env.service.lock()

        // Remove ALL stubs: any network dependency now fails loudly.
        // (Background sync will fail and log — by design; the unlock itself
        // must succeed purely from the local cache + keychain.)
        StubURLProtocol.reset()

        let unlocked = try await env.service.unlockWithBiometric(context: nil)

        #expect(unlocked)
        #expect(env.service.getItems().map(\.id) == ["pw-1"])
    }

    /// Seeds the Keychain and local cache directly — the way `storeKeyInKeychain`
    /// and the cache write would after a real password unlock — without ever
    /// calling `unlock(password:)`. Proves `unlockWithBiometric` relies solely
    /// on the raw key bytes already in the Keychain (the vault key, post-cutover)
    /// and never re-derives anything from a passphrase.
    @Test func keychainKeyRoundTripsIntoCacheUnlockWithoutPasswordDerivation() async throws {
        let item = PassVaultItem.password(VaultItemFixtures.samplePasswordItem())
        let env = try Self.makeEnv(items: [])
        defer { try? FileManager.default.removeItem(at: env.tempDir) }

        try env.keychain.saveBiometricProtected(
            env.key.withUnsafeBytes { Data($0) }, for: KeychainService.Key.passEncryptionKey)
        try env.keychain.save(env.salt, for: KeychainService.Key.passSalt)

        let vault = PassVault(version: 1, items: [item], folders: [], lastModified: 1_700_000_000_000)
        let combined = try Self.crypto.encryptData(try JSONEncoder().encode(vault), using: env.key)
        let iv = combined.prefix(12)
        let ciphertext = combined.dropFirst(12)
        try await PassVaultStore(directoryURL: env.tempDir).saveVault(
            encryptedData: ciphertext,
            metadata: PassVaultMetadata(
                version: 7, iv: iv.base64EncodedString(), updatedAt: 1_700_000_000, lastSyncedAt: 1_700_000_000))

        // No stubs at all: any network dependency fails loudly. Unlock must
        // succeed purely from the Keychain key + local cache.
        StubURLProtocol.reset()

        let unlocked = try await env.service.unlockWithBiometric(context: nil)

        #expect(unlocked)
        #expect(env.service.getItems().map(\.id) == ["pw-1"])
    }

    // MARK: CRUD — every mutation must roundtrip through encryption

    @Test func addItemWritesItAsARecord() async throws {
        let env = try Self.makeEnv(items: [])
        defer { try? FileManager.default.removeItem(at: env.tempDir) }
        _ = try await env.service.unlock(password: Self.password)

        let newItem = PassVaultItem.password(VaultItemFixtures.samplePasswordItem(id: "pw-new", name: "New Login"))
        try await env.service.addItem(newItem)

        #expect(env.service.getItems().map(\.id) == ["pw-new"])
        let uploaded = try env.server.assembledVault(vaultKey: env.key)
        #expect(uploaded.items.map(\.id) == ["pw-new"])
        // A create, not a whole-vault rewrite: the server saw exactly one write.
        let writes = StubURLProtocol.recordedRequests.filter {
            $0.httpMethod == "POST" && ($0.url?.path.hasSuffix("/v1/vault/records") ?? false)
        }
        #expect(writes.count == 1)
    }

    @Test func updateItemPersistsChanges() async throws {
        let env = try Self.makeEnv(items: [.password(VaultItemFixtures.samplePasswordItem())])
        defer { try? FileManager.default.removeItem(at: env.tempDir) }
        _ = try await env.service.unlock(password: Self.password)

        var edited = VaultItemFixtures.samplePasswordItem()
        edited.name = "Renamed"
        try await env.service.updateItem(.password(edited))

        #expect(env.service.getItem(id: "pw-1")?.name == "Renamed")
        let uploaded = try env.server.assembledVault(vaultKey: env.key)
        #expect(uploaded.items.first?.name == "Renamed")
    }

    @Test func deleteMovesToTrashAndRestoreRecovers() async throws {
        let item = PassVaultItem.password(VaultItemFixtures.samplePasswordItem())
        let env = try Self.makeEnv(items: [item])
        defer { try? FileManager.default.removeItem(at: env.tempDir) }
        _ = try await env.service.unlock(password: Self.password)

        try await env.service.deleteItem(item)
        #expect(env.service.getItems().isEmpty)
        #expect(env.service.getTrashItems().map(\.id) == ["pw-1"])
        // The uploaded vault must tombstone the item, not remove it.
        let afterDelete = try env.server.assembledVault(vaultKey: env.key)
        let deletedUploaded = try #require(afterDelete.items.first { $0.id == "pw-1" })
        #expect(deletedUploaded.deletedAt != nil)

        let trashed = try #require(env.service.getTrashItems().first)
        try await env.service.restoreItem(trashed)
        #expect(env.service.getItems().map(\.id) == ["pw-1"])
        #expect(env.service.getTrashItems().isEmpty)
        // The restored upload must clear the tombstone.
        let afterRestore = try env.server.assembledVault(vaultKey: env.key)
        let restoredUploaded = try #require(afterRestore.items.first { $0.id == "pw-1" })
        #expect(restoredUploaded.deletedAt == nil)
    }

    @Test func aRejectedRecordWriteSurfacesAsAnError() async throws {
        let env = try Self.makeEnv(items: [])
        defer { try? FileManager.default.removeItem(at: env.tempDir) }
        _ = try await env.service.unlock(password: Self.password)
        env.server.failNextWrite = (status: 409, code: "RECORD_EXISTS")

        await #expect(throws: (any Error).self) {
            try await env.service.addItem(.password(VaultItemFixtures.samplePasswordItem(id: "pw-x")))
        }
    }

    // MARK: Queries

    @Test func searchFindsByNameCaseInsensitively() async throws {
        let env = try Self.makeEnv(items: [
            .password(VaultItemFixtures.samplePasswordItem(id: "a", name: "GitHub")),
            .password(VaultItemFixtures.samplePasswordItem(id: "b", name: "GitLab")),
            .password(VaultItemFixtures.samplePasswordItem(id: "c", name: "Bank")),
        ])
        defer { try? FileManager.default.removeItem(at: env.tempDir) }
        _ = try await env.service.unlock(password: Self.password)

        #expect(env.service.searchItems(query: "git").map(\.id).sorted() == ["a", "b"])
        #expect(env.service.searchItems(query: "BANK").map(\.id) == ["c"])
    }

    @Test func credentialIdentitiesAreUpdatedOnUnlock() async throws {
        let env = try Self.makeEnv(items: [.password(VaultItemFixtures.samplePasswordItem())])
        defer { try? FileManager.default.removeItem(at: env.tempDir) }
        _ = try await env.service.unlock(password: Self.password)
        #expect(env.credentials.updates.isEmpty == false)
    }

    // MARK: - Folders

    @Test func folderLifecycleRoundtripsThroughEncryption() async throws {
        let env = try Self.makeEnv(items: [])
        defer { try? FileManager.default.removeItem(at: env.tempDir) }
        _ = try await env.service.unlock(password: Self.password)

        try await env.service.addFolder(PassFolder(id: "f-1", name: "Work"))
        #expect(env.service.getFolders().map(\.name) == ["Work"])
        var uploaded = try env.server.assembledVault(vaultKey: env.key)
        #expect(uploaded.folders.map(\.id) == ["f-1"])

        try await env.service.updateFolder(PassFolder(id: "f-1", name: "Work Renamed"))
        uploaded = try env.server.assembledVault(vaultKey: env.key)
        #expect(uploaded.folders.map(\.name) == ["Work Renamed"])
    }

    @Test func deleteFolderMovesItemsToRoot() async throws {
        var item = VaultItemFixtures.samplePasswordItem()
        item.folderId = "f-1"
        let env = try Self.makeEnv(items: [.password(item)], folders: [PassFolder(id: "f-1", name: "Work")])
        defer { try? FileManager.default.removeItem(at: env.tempDir) }
        _ = try await env.service.unlock(password: Self.password)
        #expect(env.service.getItemsInFolder("f-1").map(\.id) == ["pw-1"])

        try await env.service.deleteFolder(PassFolder(id: "f-1", name: "Work"))

        #expect(env.service.getFolders().isEmpty)
        #expect(env.service.getItemsInFolder("f-1").isEmpty)
        let uploaded = try env.server.assembledVault(vaultKey: env.key)
        #expect(uploaded.folders.isEmpty)
        guard case .password(let survivor) = uploaded.items.first else {
            Issue.record("expected surviving password item"); return
        }
        #expect(survivor.folderId == nil)   // item moved to root, not deleted
    }

    // MARK: - Favorites

    @Test func toggleFavoriteRoundtripsThroughEncryption() async throws {
        let env = try Self.makeEnv(items: [.password(VaultItemFixtures.samplePasswordItem())])
        defer { try? FileManager.default.removeItem(at: env.tempDir) }
        _ = try await env.service.unlock(password: Self.password)
        let item = try #require(env.service.getItem(id: "pw-1"))

        try await env.service.toggleFavorite(item)
        #expect(env.service.getFavorites().map(\.id) == ["pw-1"])
        var uploaded = try env.server.assembledVault(vaultKey: env.key)
        guard case .password(let fav) = uploaded.items.first else {
            Issue.record("expected password item"); return
        }
        #expect(fav.favorite == true)

        try await env.service.toggleFavorite(try #require(env.service.getItem(id: "pw-1")))
        #expect(env.service.getFavorites().isEmpty)
    }

    // MARK: - Per-type lifecycle (guards the multi-file type switches)

    @Test func everyItemTypeSurvivesAddDeleteRestore() async throws {
        let env = try Self.makeEnv(items: [])
        defer { try? FileManager.default.removeItem(at: env.tempDir) }
        _ = try await env.service.unlock(password: Self.password)

        let decoder = JSONDecoder()
        let allItems = try VaultItemFixtures.allItemJSONs.map {
            try decoder.decode(PassVaultItem.self, from: Data($0.utf8))
        }

        // Add one of each type
        for item in allItems {
            try await env.service.addItem(item)
        }
        #expect(env.service.getItems().count == allItems.count)
        var uploaded = try env.server.assembledVault(vaultKey: env.key)
        #expect(Set(uploaded.items.map(\.type)) == Set(PassVaultItemType.allCases))

        // Tombstone every type (exercises the per-type deletedAt switch)
        for item in env.service.getItems() {
            try await env.service.deleteItem(item)
        }
        #expect(env.service.getItems().isEmpty)
        #expect(env.service.getTrashItems().count == allItems.count)
        uploaded = try env.server.assembledVault(vaultKey: env.key)
        #expect(uploaded.items.allSatisfy { $0.deletedAt != nil })

        // Restore every type
        for item in env.service.getTrashItems() {
            try await env.service.restoreItem(item)
        }
        #expect(env.service.getItems().count == allItems.count)
        #expect(env.service.getTrashItems().isEmpty)
        uploaded = try env.server.assembledVault(vaultKey: env.key)
        #expect(uploaded.items.allSatisfy { $0.deletedAt == nil })
    }

    // MARK: - AutoFill pending-passkey drain

    static func makeSharedPasskey(
        id: String = "pk-af-1",
        credentialId: String = "Y3JlZC1hZg"
    ) -> SharedPassPasskeyItem {
        SharedPassPasskeyItem(
            id: id, name: "example.com", rpId: "example.com", rpName: "example.com",
            credentialId: credentialId, publicKey: "cHVi", privateKey: "cHJpdg==",
            userHandle: "dXNlcg", userName: "user@example.com"
        )
    }

    /// A passkey registered by the AutoFill extension while the app is already
    /// unlocked must reach the server on the next sync. Before this, the merge
    /// only ran on unlock paths, so it waited for a cold start.
    @Test func syncDrainsPasskeysQueuedByAutoFill() async throws {
        let env = try Self.makeEnv(items: [])
        _ = try await env.service.unlock(password: Self.password)

        // The extension registers a passkey *after* unlock — so the unlock-path
        // merge has already run and cannot be what picks this up.
        env.pending.items = [Self.makeSharedPasskey()]

        try await env.service.sync()

        let uploaded = try env.server.assembledVault(vaultKey: env.key)
        let passkeys = uploaded.items.compactMap { item -> PassPasskeyItem? in
            guard case .passkey(let passkey) = item else { return nil }
            return passkey
        }
        #expect(passkeys.map(\.credentialId) == ["Y3JlZC1hZg"])
        #expect(env.pending.clearCount == 1)
        #expect(env.pending.items.isEmpty)
    }

    // MARK: Pending logins created in the AutoFill sheet

    static func makeSharedPassword(id: String = "item-1") -> SharedPendingPasswordItem {
        SharedNewLoginDraft(name: "github.com", username: "me", password: "hunter2", site: "github.com")
            .pendingItem(id: id, now: 1_700_000_000_123)
    }

    @Test func syncDrainsLoginsQueuedByAutoFill() async throws {
        let env = try Self.makeEnv(items: [])
        _ = try await env.service.unlock(password: Self.password)

        env.pendingPasswords.items = [Self.makeSharedPassword()]


        try await env.service.sync()

        let uploaded = try env.server.assembledVault(vaultKey: env.key)
        let passwords = uploaded.items.compactMap { item -> PassPasswordItem? in
            guard case .password(let password) = item else { return nil }
            return password
        }
        #expect(passwords.map(\.id) == ["item-1"])
        #expect(passwords.first?.password == "hunter2")
        // The queued timestamps survive the drain — see the payload-equality test.
        #expect(passwords.first?.createdAt == 1_700_000_000_123)
        #expect(env.pendingPasswords.clearCount == 1)
        #expect(env.pendingPasswords.items.isEmpty)
        #expect(env.service.pendingSyncCount == 0)
    }

    @Test func aLoginAlreadyInTheVaultIsNotMergedTwice() async throws {
        // The extension pushed the record and it came back on sync, but the
        // queue still holds it — only the app clears the queue.
        let existing = PassVaultItem.password(PassService.passwordItem(from: Self.makeSharedPassword()))
        let env = try Self.makeEnv(items: [existing])
        _ = try await env.service.unlock(password: Self.password)

        env.pendingPasswords.items = [Self.makeSharedPassword()]


        try await env.service.sync()

        // Nothing was added, so nothing needed uploading — but the queue is
        // still cleared, because its contents are already in the vault.
        #expect(env.pendingPasswords.clearCount == 1)
        #expect(env.service.pendingSyncCount == 0)
    }

    @Test func aFailedSaveKeepsBothQueuesAndReportsTheCount() async throws {
        let env = try Self.makeEnv(items: [])
        _ = try await env.service.unlock(password: Self.password)

        env.pending.items = [Self.makeSharedPasskey()]
        env.pendingPasswords.items = [Self.makeSharedPassword()]

        // The write fails. Clearing here would destroy the only copy of both
        // the passkey private key and the password.
        env.server.failNextWrite = (status: 500, code: "boom")

        _ = try? await env.service.sync()

        #expect(env.pending.clearCount == 0)
        #expect(env.pendingPasswords.clearCount == 0)
        #expect(env.pending.items.count == 1)
        #expect(env.pendingPasswords.items.count == 1)
        #expect(env.service.pendingSyncCount == 2)
    }
}

}