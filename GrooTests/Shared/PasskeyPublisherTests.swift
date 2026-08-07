//
//  PasskeyPublisherTests.swift
//  GrooTests
//

import CryptoKit
import Foundation
import Testing
@testable import Groo

struct PasskeyPublisherTests {

    final class SpyPusher: PasskeyRecordPushing, @unchecked Sendable {
        var format = 2
        var formatError: (any Error)?
        var createError: (any Error)?
        var created: [SharedRecordWriteRequest] = []

        func formatVersion() async throws -> Int {
            if let formatError { throw formatError }
            return format
        }

        func createRecord(_ request: SharedRecordWriteRequest) async throws -> SharedRecordWriteResponse {
            if let createError { throw createError }
            created.append(request)
            return SharedRecordWriteResponse(id: request.id, seq: 42, version: 1)
        }
    }

    final class SpyQueue: PendingPasskeyRemoving, @unchecked Sendable {
        var removed: [String] = []
        var removeError: (any Error)?

        func remove(credentialId: String, key: SymmetricKey) throws {
            if let removeError { throw removeError }
            removed.append(credentialId)
        }
    }

    struct Boom: Error {}

    private func passkey(credentialId: String = "cred-1") -> SharedPassPasskeyItem {
        SharedPassPasskeyItem(
            id: "pk-\(credentialId)",
            name: "example.com",
            rpId: "example.com",
            rpName: "Example",
            credentialId: credentialId,
            publicKey: "cHVi",
            privateKey: "cHJpdg==",
            userHandle: "dWg=",
            userName: "user@example.com",
            signCount: 0
        )
    }

    private func makePublisher(
        pusher: SpyPusher = SpyPusher(),
        queue: SpyQueue = SpyQueue()
    ) -> (PasskeyPublisher, SpyPusher, SpyQueue, SymmetricKey) {
        let key = SymmetricKey(size: .bits256)
        return (
            PasskeyPublisher(pusher: pusher, queue: queue, vaultKey: key),
            pusher, queue, key
        )
    }

    @Test("pushes one record and removes only that credential")
    func happyPath() async throws {
        let (publisher, pusher, queue, key) = makePublisher()

        let outcome = await publisher.publish(passkey())

        #expect(outcome == .published)
        #expect(pusher.created.count == 1)
        #expect(queue.removed == ["cred-1"])

        // What reaches the server must be ciphertext that opens to the passkey.
        let sent = try #require(pusher.created.first)
        let decoded = try SharedRecordCrypto.decryptRecord(
            encryptedData: sent.encryptedData, iv: sent.iv,
            wrappedRecordKey: sent.wrappedRecordKey, wrapIv: sent.wrapIv,
            vaultKey: key
        )
        #expect(decoded.kind == .item)
        let object = try #require(
            try JSONSerialization.jsonObject(with: decoded.data) as? [String: Any]
        )
        #expect(object["type"] as? String == "passkey")
        #expect(object["credentialId"] as? String == "cred-1")
    }

    @Test("creates rather than updates — a new id cannot conflict")
    func createNeverCarriesAVersion() async {
        let (publisher, pusher, _, _) = makePublisher()

        _ = await publisher.publish(passkey())

        // No expectedVersion means no optimistic lock to lose, which is why
        // there is no 409 path here at all.
        #expect(pusher.created.first?.expectedVersion == nil)
    }

    @Test("leaves the passkey queued when the vault is still on the blob format")
    func skipsAtFormatOne() async {
        let pusher = SpyPusher()
        pusher.format = 1
        let (publisher, _, queue, _) = makePublisher(pusher: pusher)

        let outcome = await publisher.publish(passkey())

        guard case .queued = outcome else {
            Issue.record("expected the passkey to stay queued")
            return
        }
        #expect(pusher.created.isEmpty)
        // Nothing removed: the app-side drain still owns it.
        #expect(queue.removed.isEmpty)
    }

    @Test("stays queued when the push fails, and never throws into the ceremony")
    func pushFailureIsSwallowed() async {
        let pusher = SpyPusher()
        pusher.createError = Boom()
        let (publisher, _, queue, _) = makePublisher(pusher: pusher)

        let outcome = await publisher.publish(passkey())

        guard case .queued = outcome else {
            Issue.record("expected the passkey to stay queued")
            return
        }
        #expect(queue.removed.isEmpty)
    }

    @Test("stays queued when the format check fails, e.g. offline")
    func offlineStaysQueued() async {
        let pusher = SpyPusher()
        pusher.formatError = Boom()
        let (publisher, _, queue, _) = makePublisher(pusher: pusher)

        let outcome = await publisher.publish(passkey())

        guard case .queued = outcome else {
            Issue.record("expected the passkey to stay queued")
            return
        }
        #expect(pusher.created.isEmpty)
        #expect(queue.removed.isEmpty)
    }

    @Test("a failed queue removal is harmless — the push already succeeded")
    func removalFailureStillCountsAsPublished() async {
        let queue = SpyQueue()
        queue.removeError = Boom()
        let (publisher, pusher, _, _) = makePublisher(queue: queue)

        let outcome = await publisher.publish(passkey())

        // The app's merge dedupes on credentialId, so a leftover queue entry is
        // a no-op rather than a duplicate.
        #expect(outcome == .published)
        #expect(pusher.created.count == 1)
    }
}

struct SharedPendingItemsStoreRemovalTests {

    private func passkey(_ credentialId: String) -> SharedPassPasskeyItem {
        SharedPassPasskeyItem(
            id: "pk-\(credentialId)", name: "example.com",
            rpId: "example.com", rpName: "Example", credentialId: credentialId,
            publicKey: "cHVi", privateKey: "cHJpdg==", userHandle: "dWg=",
            userName: "u", signCount: 0)
    }

    @Test("removing one queued passkey leaves the others intact")
    func targetedRemoval() throws {
        let key = SymmetricKey(size: .bits256)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("pending-\(UUID().uuidString).enc")
        defer { try? FileManager.default.removeItem(at: url) }

        try SharedPendingItemsStore.append(passkey("a"), key: key, fileURL: url)
        try SharedPendingItemsStore.append(passkey("b"), key: key, fileURL: url)

        try SharedPendingItemsStore.remove(credentialId: "a", key: key, fileURL: url)

        // The survivor holds a private key that exists nowhere else yet;
        // clear() would have destroyed it.
        let remaining = try SharedPendingItemsStore.load(key: key, fileURL: url)
        #expect(remaining.map(\.credentialId) == ["b"])
    }

    @Test("removing the last passkey clears the queue file")
    func removingLastClearsFile() throws {
        let key = SymmetricKey(size: .bits256)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("pending-\(UUID().uuidString).enc")
        defer { try? FileManager.default.removeItem(at: url) }

        try SharedPendingItemsStore.append(passkey("only"), key: key, fileURL: url)
        try SharedPendingItemsStore.remove(credentialId: "only", key: key, fileURL: url)

        #expect(try SharedPendingItemsStore.load(key: key, fileURL: url).isEmpty)
    }

    @Test("removing an unknown credential leaves the queue untouched")
    func unknownCredentialIsANoOp() throws {
        let key = SymmetricKey(size: .bits256)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("pending-\(UUID().uuidString).enc")
        defer { try? FileManager.default.removeItem(at: url) }

        try SharedPendingItemsStore.append(passkey("a"), key: key, fileURL: url)
        try SharedPendingItemsStore.remove(credentialId: "nope", key: key, fileURL: url)

        #expect(try SharedPendingItemsStore.load(key: key, fileURL: url).count == 1)
    }
}
