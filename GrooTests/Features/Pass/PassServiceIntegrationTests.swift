//
//  PassServiceIntegrationTests.swift
//  GrooTests
//
//  Full vault lifecycle against stubbed network, fake keychain, temp-dir
//  storage. Serialized: StubURLProtocol uses static state.
//

import CryptoKit
import Foundation
import Testing
@testable import Groo

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
    }

    static let crypto = CryptoService()
    static let password = "test-master-password"
    static let iterations: UInt32 = 1_000

    /// Build a PassService wired entirely to fakes, and stub key-info + vault
    /// GET endpoints so `unlock(password:)` succeeds with `items` inside.
    static func makeEnv(items: [PassVaultItem], vaultVersion: Int = 3) throws -> Env {
        StubURLProtocol.reset()

        let salt = Data("integration-salt".utf8)
        let key = try crypto.deriveKey(password: password, salt: salt, iterations: iterations)

        let vault = PassVault(version: 1, items: items, folders: [], lastModified: 1_700_000_000_000)
        let combined = try crypto.encryptData(try JSONEncoder().encode(vault), using: key)
        let iv = combined.prefix(12)
        let ciphertext = combined.dropFirst(12)

        StubURLProtocol.enqueue(
            method: "GET", pathSuffix: "/v1/vault/key-info",
            json: #"{"keySalt":"\#(salt.base64EncodedString())","kdfIterations":\#(iterations)}"#)
        StubURLProtocol.enqueue(
            method: "GET", pathSuffix: "/v1/vault",
            json: #"{"encryptedData":"\#(ciphertext.base64EncodedString())","iv":"\#(iv.base64EncodedString())","version":\#(vaultVersion),"updatedAt":1700000000}"#)

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
            credentialService: credentials)

        return Env(service: service, keychain: keychain, credentials: credentials,
                   key: key, salt: salt, tempDir: tempDir)
    }

    /// Stub the PUT /v1/vault response `saveVault()` expects after a mutation.
    static func stubVaultPut(version: Int) {
        StubURLProtocol.enqueue(
            method: "PUT", pathSuffix: "/v1/vault",
            json: #"{"encryptedData":"","iv":"","version":\#(version),"updatedAt":1700000001}"#)
    }

    /// Decrypt the vault the service uploaded in its last PUT request.
    static func decodeUploadedVault(key: SymmetricKey) throws -> (vault: PassVault, request: PassVaultUpdateRequest) {
        let put = try #require(StubURLProtocol.recordedRequests.last {
            $0.httpMethod == "PUT" && ($0.url?.path.hasSuffix("/v1/vault") ?? false)
        })
        let body = try #require(put.bodyData)
        let update = try JSONDecoder().decode(PassVaultUpdateRequest.self, from: body)
        var combined = try #require(Data(base64Encoded: update.iv))
        combined.append(try #require(Data(base64Encoded: update.encryptedData)))
        let plaintext = try crypto.decryptData(combined, using: key)
        return (try JSONDecoder().decode(PassVault.self, from: plaintext), update)
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

    @Test func biometricUnlockUsesLocalCacheWithoutNetwork() async throws {
        let item = PassVaultItem.password(VaultItemFixtures.samplePasswordItem())
        let env = try Self.makeEnv(items: [item])
        defer { try? FileManager.default.removeItem(at: env.tempDir) }

        // First unlock populates keychain + vault cache
        _ = try await env.service.unlock(password: Self.password)
        env.service.lock()
        let requestsAfterUnlock = StubURLProtocol.recordedRequests.count

        let unlocked = try await env.service.unlockWithBiometric(context: nil)

        #expect(unlocked)
        #expect(env.service.getItems().map(\.id) == ["pw-1"])
        // Cache hit: no additional GETs needed before returning
        // (background sync may add requests afterwards; assert unlock preceded them)
        #expect(StubURLProtocol.recordedRequests.count >= requestsAfterUnlock)
    }

    // MARK: CRUD — every mutation must roundtrip through encryption

    @Test func addItemUploadsReencryptedVaultWithOptimisticVersion() async throws {
        let env = try Self.makeEnv(items: [], vaultVersion: 3)
        defer { try? FileManager.default.removeItem(at: env.tempDir) }
        _ = try await env.service.unlock(password: Self.password)
        Self.stubVaultPut(version: 4)

        let newItem = PassVaultItem.password(VaultItemFixtures.samplePasswordItem(id: "pw-new", name: "New Login"))
        try await env.service.addItem(newItem)

        #expect(env.service.getItems().map(\.id) == ["pw-new"])
        let uploaded = try Self.decodeUploadedVault(key: env.key)
        #expect(uploaded.vault.items.map(\.id) == ["pw-new"])
        #expect(uploaded.request.expectedVersion == 3)
    }

    @Test func updateItemPersistsChanges() async throws {
        let env = try Self.makeEnv(items: [.password(VaultItemFixtures.samplePasswordItem())])
        defer { try? FileManager.default.removeItem(at: env.tempDir) }
        _ = try await env.service.unlock(password: Self.password)
        Self.stubVaultPut(version: 4)

        var edited = VaultItemFixtures.samplePasswordItem()
        edited.name = "Renamed"
        try await env.service.updateItem(.password(edited))

        #expect(env.service.getItem(id: "pw-1")?.name == "Renamed")
        let uploaded = try Self.decodeUploadedVault(key: env.key)
        #expect(uploaded.vault.items.first?.name == "Renamed")
    }

    @Test func deleteMovesToTrashAndRestoreRecovers() async throws {
        let item = PassVaultItem.password(VaultItemFixtures.samplePasswordItem())
        let env = try Self.makeEnv(items: [item])
        defer { try? FileManager.default.removeItem(at: env.tempDir) }
        _ = try await env.service.unlock(password: Self.password)

        Self.stubVaultPut(version: 4)
        try await env.service.deleteItem(item)
        #expect(env.service.getItems().isEmpty)
        #expect(env.service.getTrashItems().map(\.id) == ["pw-1"])

        Self.stubVaultPut(version: 5)
        let trashed = try #require(env.service.getTrashItems().first)
        try await env.service.restoreItem(trashed)
        #expect(env.service.getItems().map(\.id) == ["pw-1"])
        #expect(env.service.getTrashItems().isEmpty)
    }

    @Test func versionConflictOnSaveSurfacesError() async throws {
        let env = try Self.makeEnv(items: [])
        defer { try? FileManager.default.removeItem(at: env.tempDir) }
        _ = try await env.service.unlock(password: Self.password)
        StubURLProtocol.enqueue(method: "PUT", pathSuffix: "/v1/vault", status: 409, json: "{}")

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
}
