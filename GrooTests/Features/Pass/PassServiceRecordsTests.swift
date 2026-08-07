//
//  PassServiceRecordsTests.swift
//  GrooTests
//
//  PassService against a stubbed server reporting formatVersion 2. Nested under
//  NetworkStubbedSuites because StubURLProtocol carries static state.
//

import CryptoKit
import Foundation
import Testing
@testable import Groo

extension NetworkStubbedSuites {

@MainActor
@Suite(.serialized)
struct PassServiceRecordsTests {

    static let crypto = CryptoService()
    static let password = "test-master-password"
    static let iterations: UInt32 = 1_000

    struct Env {
        let service: PassService
        let key: SymmetricKey
        let tempDir: URL
    }

    /// Stub key-info at formatVersion 2 plus one page of records.
    static func makeEnv(
        records: [(id: String, kind: String, payload: String, seq: Int, version: Int)],
        privateKeyStored: Bool = false
    ) throws -> Env {
        StubURLProtocol.reset()

        let salt = Data("records-salt".utf8)
        let wrappingKey = try crypto.deriveKey(password: password, salt: salt, iterations: iterations)
        let key = crypto.generateContentKey()
        let wrapped = try crypto.wrapKey(key, using: wrappingKey)

        StubURLProtocol.enqueue(
            method: "GET", pathSuffix: "/v1/vault/key-info",
            json: #"{"keySalt":"\#(salt.base64EncodedString())","kdfIterations":\#(iterations),"wrappedVaultKey":"\#(wrapped.ciphertext)","wrapIv":"\#(wrapped.iv)","formatVersion":2}"#)

        let encoded = try records.map { record -> String in
            let kind = SharedRecordKind(rawValue: record.kind) ?? .item
            let enc = try SharedRecordCrypto.encryptRecord(
                id: record.id, kind: kind, payload: Data(record.payload.utf8), vaultKey: key
            )
            return #"{"id":"\#(record.id)","encryptedData":"\#(enc.encryptedData)","iv":"\#(enc.iv)","wrappedRecordKey":"\#(enc.wrappedRecordKey)","wrapIv":"\#(enc.wrapIv)","version":\#(record.version),"seq":\#(record.seq),"isDeleted":false,"createdAt":1,"updatedAt":1}"#
        }.joined(separator: ",")

        let maxSeq = records.map(\.seq).max() ?? 0
        StubURLProtocol.enqueue(
            method: "GET", pathSuffix: "/v1/vault/records",
            json: #"{"records":[\#(encoded)],"nextSeq":\#(maxSeq),"hasMore":false,"formatVersion":2}"#)

        if privateKeyStored {
            let sealed = try crypto.encrypt("private-jwk", using: key)
            StubURLProtocol.enqueue(
                method: "GET", pathSuffix: "/v1/vault/private-key",
                json: #"{"encryptedPrivateKey":"\#(sealed.ciphertext)","privateKeyIv":"\#(sealed.iv)"}"#)
        } else {
            StubURLProtocol.enqueue(
                method: "GET", pathSuffix: "/v1/vault/private-key",
                status: 404,
                json: #"{"error":"No private key stored","code":"PRIVATE_KEY_NOT_SET"}"#)
        }

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PassRecordsTests-\(UUID().uuidString)", isDirectory: true)

        let service = PassService(
            api: PassAPIClient(
                tokenProvider: { "test-token" },
                forceRefresh: { "test-token-2" },
                sessionConfiguration: StubURLProtocol.stubbedConfiguration()),
            crypto: crypto,
            keychain: InMemoryKeychain(),
            vaultStore: PassVaultStore(directoryURL: tempDir),
            credentialService: RecordingCredentialService(),
            pendingPasskeys: InMemoryPendingPasskeyStore())

        return Env(service: service, key: key, tempDir: tempDir)
    }

    static func passwordItem(_ id: String, name: String) -> String {
        """
        {"id":"\(id)","type":"password","name":"\(name)","username":"u",\
        "password":"p","urls":[],"createdAt":1,"updatedAt":1}
        """
    }

    static func requests(_ method: String, containing fragment: String) -> [URLRequest] {
        StubURLProtocol.recordedRequests.filter {
            $0.httpMethod == method && ($0.url?.path.contains(fragment) ?? false)
        }
    }

    // MARK: - Unlock

    @Test func unlockSyncsRecordsAndNeverFetchesTheBlob() async throws {
        let env = try Self.makeEnv(records: [
            (id: "a", kind: "item", payload: Self.passwordItem("a", name: "GitHub"), seq: 1, version: 1),
            (id: "f", kind: "folder", payload: #"{"id":"f","name":"Work"}"#, seq: 2, version: 1),
        ])
        defer { try? FileManager.default.removeItem(at: env.tempDir) }

        let unlocked = try await env.service.unlock(password: Self.password)

        #expect(unlocked)
        #expect(env.service.formatVersion == 2)
        #expect(env.service.getItems().map(\.id) == ["a"])
        // The blob endpoint 410s once converted; touching it at all is the bug.
        let blobGets = Self.requests("GET", containing: "/v1/vault").filter {
            $0.url?.path.hasSuffix("/v1/vault") ?? false
        }
        #expect(blobGets.isEmpty)
    }

    @Test func unlockToleratesAnAbsentSharingPrivateKey() async throws {
        let env = try Self.makeEnv(records: [
            (id: "a", kind: "item", payload: Self.passwordItem("a", name: "GitHub"), seq: 1, version: 1)
        ])
        defer { try? FileManager.default.removeItem(at: env.tempDir) }

        // 404 is a normal state for an account that has never shared.
        #expect(try await env.service.unlock(password: Self.password))
        #expect(env.service.getItems().count == 1)
    }

    // MARK: - Writes

    @Test func addingAnItemWritesOneRecordNotAWholeVault() async throws {
        let env = try Self.makeEnv(records: [
            (id: "a", kind: "item", payload: Self.passwordItem("a", name: "GitHub"), seq: 1, version: 1)
        ])
        defer { try? FileManager.default.removeItem(at: env.tempDir) }
        _ = try await env.service.unlock(password: Self.password)

        StubURLProtocol.enqueue(
            method: "POST", pathSuffix: "/v1/vault/records",
            json: #"{"id":"new-1","seq":2,"version":1}"#)

        let item = VaultItemFixtures.samplePasswordItem(id: "new-1")
        try await env.service.addItem(.password(item))

        #expect(Self.requests("POST", containing: "/v1/vault/records").count == 1)
        // A whole-vault PUT would 410 after the cutover.
        #expect(Self.requests("PUT", containing: "/v1/vault").isEmpty)
    }

    @Test func anUnchangedItemIsNotRewritten() async throws {
        let env = try Self.makeEnv(records: [
            (id: "a", kind: "item", payload: Self.passwordItem("a", name: "GitHub"), seq: 1, version: 1),
            (id: "b", kind: "item", payload: Self.passwordItem("b", name: "Fastmail"), seq: 2, version: 1),
        ])
        defer { try? FileManager.default.removeItem(at: env.tempDir) }
        _ = try await env.service.unlock(password: Self.password)

        StubURLProtocol.enqueue(
            method: "POST", pathSuffix: "/v1/vault/records",
            json: #"{"id":"new-1","seq":3,"version":1}"#)

        let item = VaultItemFixtures.samplePasswordItem(id: "new-1")
        try await env.service.addItem(.password(item))

        // Only the new record is written; the two untouched ones are not
        // rewritten, which is the whole point of per-item storage.
        #expect(Self.requests("POST", containing: "/v1/vault/records").count == 1)
        #expect(Self.requests("PUT", containing: "/v1/vault/records").isEmpty)
    }

    @Test func trashUpdatesThePayloadAndNeverTombstones() async throws {
        let env = try Self.makeEnv(records: [
            (id: "a", kind: "item", payload: Self.passwordItem("a", name: "GitHub"), seq: 1, version: 1)
        ])
        defer { try? FileManager.default.removeItem(at: env.tempDir) }
        _ = try await env.service.unlock(password: Self.password)

        StubURLProtocol.enqueue(
            method: "PUT", pathSuffix: "/v1/vault/records/a",
            json: #"{"id":"a","seq":2,"version":2}"#)

        let item = try #require(env.service.getItems().first)
        try await env.service.deleteItem(item)

        // The server must never learn what was thrown away.
        #expect(Self.requests("PUT", containing: "/v1/vault/records/a").count == 1)
        #expect(Self.requests("DELETE", containing: "/v1/vault/records").isEmpty)
    }

    @Test func updateSendsTheLastSyncedVersionAsTheOptimisticLock() async throws {
        let env = try Self.makeEnv(records: [
            (id: "a", kind: "item", payload: Self.passwordItem("a", name: "GitHub"), seq: 1, version: 7)
        ])
        defer { try? FileManager.default.removeItem(at: env.tempDir) }
        _ = try await env.service.unlock(password: Self.password)

        StubURLProtocol.enqueue(
            method: "PUT", pathSuffix: "/v1/vault/records/a",
            json: #"{"id":"a","seq":2,"version":8}"#)

        let item = VaultItemFixtures.samplePasswordItem(id: "a", name: "Renamed")
        try await env.service.updateItem(.password(item))

        let put = try #require(Self.requests("PUT", containing: "/v1/vault/records/a").last)
        let body = try #require(put.bodyData)
        let sent = try JSONDecoder().decode(SharedRecordWriteRequest.self, from: body)
        #expect(sent.expectedVersion == 7)
    }

    @Test func aConflictRetriesOnceAgainstTheServersVersion() async throws {
        let env = try Self.makeEnv(records: [
            (id: "a", kind: "item", payload: Self.passwordItem("a", name: "GitHub"), seq: 1, version: 1)
        ])
        defer { try? FileManager.default.removeItem(at: env.tempDir) }
        _ = try await env.service.unlock(password: Self.password)

        let conflicting = try SharedRecordCrypto.encryptRecord(
            id: "a", kind: .item,
            payload: Data(Self.passwordItem("a", name: "ServerWins").utf8),
            vaultKey: env.key)

        StubURLProtocol.enqueue(
            method: "PUT", pathSuffix: "/v1/vault/records/a",
            status: 409,
            json: #"{"error":"Record was modified","code":"RECORD_CONFLICT","current":{"id":"a","encryptedData":"\#(conflicting.encryptedData)","iv":"\#(conflicting.iv)","wrappedRecordKey":"\#(conflicting.wrappedRecordKey)","wrapIv":"\#(conflicting.wrapIv)","version":9,"seq":5,"isDeleted":false,"createdAt":1,"updatedAt":1}}"#)
        StubURLProtocol.enqueue(
            method: "PUT", pathSuffix: "/v1/vault/records/a",
            json: #"{"id":"a","seq":6,"version":10}"#)

        let item = VaultItemFixtures.samplePasswordItem(id: "a", name: "LocalWins")
        try await env.service.updateItem(.password(item))

        let puts = Self.requests("PUT", containing: "/v1/vault/records/a")
        #expect(puts.count == 2)
        // The retry must carry the version the server reported, not the stale one.
        let retry = try JSONDecoder().decode(
            SharedRecordWriteRequest.self, from: try #require(puts.last?.bodyData))
        #expect(retry.expectedVersion == 9)
    }

    // MARK: - Recovering from a conversion that happened elsewhere

    /// key-info still says 1 (stale), but the blob endpoint has already 410'd.
    static func makeConvertedMidFlightEnv() throws -> Env {
        StubURLProtocol.reset()

        let salt = Data("records-salt".utf8)
        let wrappingKey = try crypto.deriveKey(password: password, salt: salt, iterations: iterations)
        let key = crypto.generateContentKey()
        let wrapped = try crypto.wrapKey(key, using: wrappingKey)

        StubURLProtocol.enqueue(
            method: "GET", pathSuffix: "/v1/vault/key-info",
            json: #"{"keySalt":"\#(salt.base64EncodedString())","kdfIterations":\#(iterations),"wrappedVaultKey":"\#(wrapped.ciphertext)","wrapIv":"\#(wrapped.iv)","formatVersion":1}"#)

        StubURLProtocol.enqueue(
            method: "GET", pathSuffix: "/v1/vault",
            status: 410,
            json: #"{"error":"This vault now uses per-item records; update your client","code":"FORMAT_MIGRATED"}"#)

        let enc = try SharedRecordCrypto.encryptRecord(
            id: "a", kind: .item,
            payload: Data(passwordItem("a", name: "GitHub").utf8), vaultKey: key)
        StubURLProtocol.enqueue(
            method: "GET", pathSuffix: "/v1/vault/records",
            json: #"{"records":[{"id":"a","encryptedData":"\#(enc.encryptedData)","iv":"\#(enc.iv)","wrappedRecordKey":"\#(enc.wrappedRecordKey)","wrapIv":"\#(enc.wrapIv)","version":1,"seq":1,"isDeleted":false,"createdAt":1,"updatedAt":1}],"nextSeq":1,"hasMore":false,"formatVersion":2}"#)
        StubURLProtocol.enqueue(
            method: "GET", pathSuffix: "/v1/vault/private-key",
            status: 404, json: #"{"error":"none","code":"PRIVATE_KEY_NOT_SET"}"#)

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PassRecordsTests-\(UUID().uuidString)", isDirectory: true)

        let service = PassService(
            api: PassAPIClient(
                tokenProvider: { "test-token" },
                forceRefresh: { "test-token-2" },
                sessionConfiguration: StubURLProtocol.stubbedConfiguration()),
            crypto: crypto,
            keychain: InMemoryKeychain(),
            vaultStore: PassVaultStore(directoryURL: tempDir),
            credentialService: RecordingCredentialService(),
            pendingPasskeys: InMemoryPendingPasskeyStore())

        return Env(service: service, key: key, tempDir: tempDir)
    }

    @Test func unlockRecoversWhenTheVaultConvertedMidFlight() async throws {
        let env = try Self.makeConvertedMidFlightEnv()
        defer { try? FileManager.default.removeItem(at: env.tempDir) }

        // A 410 here means the web app converted between our key-info read and
        // this fetch. This build speaks records, so it must switch rather than
        // fail — "update required" is for builds that predate record support.
        let unlocked = try await env.service.unlock(password: Self.password)

        #expect(unlocked)
        #expect(env.service.formatVersion == 2)
        #expect(env.service.getItems().map(\.id) == ["a"])
    }
}

}
