//
//  PadServiceTests.swift
//  GrooTests
//
//  Pad crypto lifecycle over an in-memory keychain + store: biometric-unlock
//  seam, encrypt→persist→decrypt roundtrips, loud decrypt-failure counting,
//  encrypted file upload/download over a stubbed API.
//

import CryptoKit
import Foundation
import Testing
@testable import Groo

extension NetworkStubbedSuites {
@MainActor
@Suite(.serialized)
struct PadServiceTests {
    struct Env {
        let service: PadService
        let store: LocalStore
        let keychain: InMemoryKeychain
        let key: SymmetricKey
    }

    static func makeUnlockedEnv() throws -> Env {
        let store = try InMemoryLocalStore.make()
        let keychain = InMemoryKeychain()
        let key = SymmetricKey(size: .bits256)
        try keychain.saveBiometricProtected(key.withUnsafeBytes { Data($0) }, for: KeychainService.Key.padEncryptionKey)
        let api = APIClient(
            baseURL: URL(string: "https://pad.test")!,
            sessionConfiguration: StubURLProtocol.stubbedConfiguration(),
            tokenProvider: { "pad-token" }
        )
        let service = PadService(api: api, keychain: keychain, store: store)
        #expect(try service.unlockWithBiometric())
        return Env(service: service, store: store, keychain: keychain, key: key)
    }

    @Test func biometricUnlockLoadsKeyFromKeychain() throws {
        StubURLProtocol.reset()
        let env = try Self.makeUnlockedEnv()

        #expect(env.service.isUnlocked)
        #expect(env.service.canUnlockWithBiometric)
    }

    @Test func lockKeepsBiometricKeyButClearRemovesIt() throws {
        StubURLProtocol.reset()
        let env = try Self.makeUnlockedEnv()

        env.service.lock()
        #expect(!env.service.isUnlocked)
        #expect(env.service.canUnlockWithBiometric)   // key stays for re-unlock

        env.service.lockAndClearKey()
        #expect(!env.service.canUnlockWithBiometric)  // full sign-out wipes it
    }

    @Test func createEncryptedItemRoundtripsThroughLocalStore() throws {
        StubURLProtocol.reset()
        let env = try Self.makeUnlockedEnv()

        let item = try env.service.createEncryptedItem(text: "buy milk 🥛")
        #expect(item.id.count == 8)                        // short lowercase id
        #expect(item.encryptedText.ciphertext != "buy milk 🥛")
        env.store.savePadItem(from: item)

        let decrypted = try env.service.getDecryptedItems()
        #expect(decrypted.map(\.text) == ["buy milk 🥛"])
        #expect(env.service.decryptFailureCount == 0)
    }

    @Test func decryptFailuresAreCountedNotSilentlyDropped() throws {
        StubURLProtocol.reset()
        let env = try Self.makeUnlockedEnv()
        let good = try env.service.createEncryptedItem(text: "readable")
        env.store.savePadItem(from: good)
        // Undecodable payload JSON and undecryptable-but-well-formed payload
        env.store.savePadItem(LocalPadItem(id: "bad-json", encryptedTextJSON: "garbage", createdAt: Date(timeIntervalSince1970: 100)))
        env.store.savePadItem(LocalPadItem(
            id: "bad-crypto",
            encryptedTextJSON: #"{"ciphertext":"AAAAAAAAAAAAAAAAAAAAAAAAAAAA","iv":"AAAAAAAAAAAAAAAA","version":1}"#,
            createdAt: Date(timeIntervalSince1970: 200)
        ))

        let decrypted = try env.service.getDecryptedItems()

        #expect(decrypted.map(\.text) == ["readable"])
        #expect(env.service.decryptFailureCount == 2)   // surfaced, not swallowed
    }

    @Test func lockedServiceThrowsNoEncryptionKey() throws {
        StubURLProtocol.reset()
        let store = try InMemoryLocalStore.make()
        let api = APIClient(
            baseURL: URL(string: "https://pad.test")!,
            sessionConfiguration: StubURLProtocol.stubbedConfiguration(),
            tokenProvider: { "pad-token" }
        )
        let service = PadService(api: api, keychain: InMemoryKeychain(), store: store)

        // do/catch instead of #expect(performing:throws:) — the sync performing
        // closure is not MainActor-isolated, but these methods are
        do {
            _ = try service.getDecryptedItems()
            Issue.record("getDecryptedItems must throw when locked")
        } catch PadError.noEncryptionKey {
            // expected: locked reads fail loudly
        } catch {
            Issue.record("expected PadError.noEncryptionKey, got \(error)")
        }
        do {
            _ = try service.createEncryptedItem(text: "x")
            Issue.record("createEncryptedItem must throw when locked")
        } catch PadError.noEncryptionKey {
            // expected: locked writes fail loudly
        } catch {
            Issue.record("expected PadError.noEncryptionKey, got \(error)")
        }
    }

    @Test func uploadFileEncryptsBytesAndMetadata() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.enqueue(method: "POST", pathSuffix: "/v1/files", json: #"{"id":"file-1","size":123,"r2Key":"r2/file-1"}"#)
        let env = try Self.makeUnlockedEnv()
        let plainBytes = Data("very secret document bytes".utf8)

        let attachment = try await env.service.uploadFile(name: "report.pdf", type: "application/pdf", data: plainBytes)

        #expect(attachment.id == "file-1")
        #expect(attachment.r2Key == "r2/file-1")
        // The wire body must never contain the plaintext bytes
        let body = try #require(StubURLProtocol.recordedRequests.first?.bodyData)
        #expect(body.range(of: plainBytes) == nil)
        // Metadata is encrypted but recoverable with the vault key
        let crypto = CryptoService()
        #expect(try crypto.decrypt(attachment.encryptedName.toEncryptedPayload(), using: env.key) == "report.pdf")
        #expect(try crypto.decrypt(attachment.encryptedType.toEncryptedPayload(), using: env.key) == "application/pdf")
    }

    @Test func downloadFileDecryptsServerBytes() async throws {
        StubURLProtocol.reset()
        let env = try Self.makeUnlockedEnv()
        let original = Data("downloaded content 📄".utf8)
        let encrypted = try CryptoService().encryptData(original, using: env.key)
        StubURLProtocol.enqueue(method: "GET", pathSuffix: "/v1/files/abc123", data: encrypted)

        let file = DecryptedFileAttachment(id: "file-1", name: "doc", type: "text/plain", size: original.count, r2Key: "abc123")
        let downloaded = try await env.service.downloadFile(file)

        #expect(downloaded == original)
    }
}
}
