//
//  SharedPendingItemsStoreTests.swift
//  GrooTests
//
//  Pending-passkey queue semantics against a temp-directory file: roundtrips,
//  wrong-key rejection (never "empty"), corrupt-queue move-aside, clear.
//  The real App Group file is never touched (explicit fileURL every call).
//

import CryptoKit
import Foundation
import Testing
@testable import Groo

struct SharedPendingItemsStoreTests {
    static func tempQueueURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("pending-items-tests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("pending_passkeys.enc")
    }

    static func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }

    static func makePasskey(id: String = "pk-1", credentialId: String = "Y3JlZC1pZA") -> SharedPassPasskeyItem {
        SharedPassPasskeyItem(
            id: id, name: "example.com", rpId: "example.com", rpName: "example.com",
            credentialId: credentialId, publicKey: "cHVi", privateKey: "cHJpdg==",
            userHandle: "dXNlcg", userName: "user@example.com"
        )
    }

    @Test func missingQueueFileLoadsEmpty() throws {
        let url = Self.tempQueueURL()
        defer { Self.cleanup(url) }

        #expect(try SharedPendingItemsStore.load(key: SymmetricKey(size: .bits256), fileURL: url).isEmpty)
    }

    @Test func appendThenLoadRoundtripsAllFields() throws {
        let url = Self.tempQueueURL()
        defer { Self.cleanup(url) }
        let key = SymmetricKey(size: .bits256)

        try SharedPendingItemsStore.append(Self.makePasskey(), key: key, fileURL: url)
        let loaded = try SharedPendingItemsStore.load(key: key, fileURL: url)

        try #require(loaded.count == 1)
        #expect(loaded[0].id == "pk-1")
        #expect(loaded[0].rpId == "example.com")
        #expect(loaded[0].credentialId == "Y3JlZC1pZA")
        #expect(loaded[0].privateKey == "cHJpdg==")   // the unsynced private key survives
        #expect(loaded[0].signCount == 0)
    }

    @Test func appendAccumulatesInOrder() throws {
        let url = Self.tempQueueURL()
        defer { Self.cleanup(url) }
        let key = SymmetricKey(size: .bits256)

        try SharedPendingItemsStore.append(Self.makePasskey(id: "pk-1", credentialId: "aWQtMQ"), key: key, fileURL: url)
        try SharedPendingItemsStore.append(Self.makePasskey(id: "pk-2", credentialId: "aWQtMg"), key: key, fileURL: url)

        #expect(try SharedPendingItemsStore.load(key: key, fileURL: url).map(\.id) == ["pk-1", "pk-2"])
    }

    @Test func wrongKeyThrowsUnreadableNeverEmpty() throws {
        let url = Self.tempQueueURL()
        defer { Self.cleanup(url) }
        try SharedPendingItemsStore.append(Self.makePasskey(), key: SymmetricKey(size: .bits256), fileURL: url)

        // An unreadable queue must never be mistaken for an empty one — the
        // caller (PassService) keeps the file for a retry with the right key
        #expect {
            _ = try SharedPendingItemsStore.load(key: SymmetricKey(size: .bits256), fileURL: url)
        } throws: { error in
            guard case SharedPendingItemsStoreError.unreadable = error else { return false }
            return true
        }
    }

    @Test func appendMovesUnreadableQueueAsideAndStartsFresh() throws {
        let url = Self.tempQueueURL()
        defer { Self.cleanup(url) }
        let key = SymmetricKey(size: .bits256)
        let garbage = Data("not an AES-GCM box".utf8)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try garbage.write(to: url)

        try SharedPendingItemsStore.append(Self.makePasskey(), key: key, fileURL: url)

        // Fresh queue holds only the new item…
        #expect(try SharedPendingItemsStore.load(key: key, fileURL: url).map(\.id) == ["pk-1"])
        // …and the unreadable original (which may hold unsynced private keys)
        // was moved aside, not destroyed
        let backup = url.appendingPathExtension("corrupt")
        #expect(try Data(contentsOf: backup) == garbage)
    }

    @Test func clearRemovesQueue() throws {
        let url = Self.tempQueueURL()
        defer { Self.cleanup(url) }
        let key = SymmetricKey(size: .bits256)
        try SharedPendingItemsStore.append(Self.makePasskey(), key: key, fileURL: url)

        SharedPendingItemsStore.clear(fileURL: url)

        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(try SharedPendingItemsStore.load(key: key, fileURL: url).isEmpty)
    }

    @Test func nilFileURLThrowsContainerNotAvailable() {
        // Mirrors an extension running with a broken App Group entitlement
        #expect {
            _ = try SharedPendingItemsStore.load(key: SymmetricKey(size: .bits256), fileURL: nil)
        } throws: { error in
            guard case SharedPendingItemsStoreError.containerNotAvailable = error else { return false }
            return true
        }
    }
}
