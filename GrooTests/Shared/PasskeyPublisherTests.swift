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
        var createError: (any Error)?
        var created: [SharedRecordWriteRequest] = []

        func createRecord(_ request: SharedRecordWriteRequest) async throws -> SharedRecordWriteResponse {
            if let createError { throw createError }
            created.append(request)
            return SharedRecordWriteResponse(id: request.id, seq: 42, version: 1)
        }
    }

    /// Records whether anything tried to touch the pending queue. Nothing
    /// should: the app owns that lifecycle.
    final class SpyQueue: @unchecked Sendable {
        var removed: [String] = []
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
            PasskeyPublisher(pusher: pusher, vaultKey: key),
            pusher, queue, key
        )
    }

    // The guard that would have caught the shipped bug: the payload must decode
    // as the app's REAL passkey model, not the lossy Shared one it came from.
    @Test("payload decodes as PassPasskeyItem, the shape every client expects")
    func payloadMatchesTheAppModel() throws {
        let (publisher, _, _, _) = makePublisher()

        let data = try publisher.payload(for: passkey())
        let decoded = try JSONDecoder().decode(PassPasskeyItem.self, from: data)

        #expect(decoded.id == "pk-cred-1")
        #expect(decoded.credentialId == "cred-1")
        #expect(decoded.type == .passkey)
        #expect(decoded.signCount == 0)
    }

    @Test("payload carries createdAt and updatedAt")
    func payloadHasTimestamps() throws {
        let key = SymmetricKey(size: .bits256)
        let publisher = PasskeyPublisher(
            pusher: SpyPusher(), vaultKey: key, now: { 1_700_000_000_123 }
        )

        let object = try JSONSerialization.jsonObject(
            with: try publisher.payload(for: passkey())
        ) as? [String: Any]

        // Their absence is exactly what made the record undecodable on every
        // client, and crashed the web detail view on `new Date(undefined)`.
        #expect(object?["createdAt"] as? Int == 1_700_000_000_123)
        #expect(object?["updatedAt"] as? Int == 1_700_000_000_123)
    }

    @Test("payload omits deletedAt rather than sending null")
    func payloadOmitsAbsentOptionals() throws {
        let (publisher, _, _, _) = makePublisher()

        let object = try JSONSerialization.jsonObject(
            with: try publisher.payload(for: passkey())
        ) as? [String: Any]

        #expect(object?["deletedAt"] == nil)
    }

    @Test("the pushed record decrypts to something PassPasskeyItem can decode")
    func pushedRecordIsDecodableEndToEnd() async throws {
        let (publisher, pusher, _, key) = makePublisher()

        _ = await publisher.publish(passkey())

        let sent = try #require(pusher.created.first)
        let decoded = try SharedRecordCrypto.decryptRecord(
            encryptedData: sent.encryptedData, iv: sent.iv,
            wrappedRecordKey: sent.wrappedRecordKey, wrapIv: sent.wrapIv,
            vaultKey: key
        )
        // Full round trip: what actually lands on the server must be readable
        // by the app, the web client and the extension.
        _ = try JSONDecoder().decode(PassPasskeyItem.self, from: decoded.data)
    }

    @Test("leaves the passkey queued so a fresh extension process can serve it")
    func stillQueuedAfterPush() async {
        let (publisher, _, queue, _) = makePublisher()

        _ = await publisher.publish(passkey())

        // AutoFill builds its passkey list from the App Group vault CACHE plus
        // the pending queue. The push does not update that cache — only the
        // app's sync does — so dropping the item from the queue here leaves it
        // in neither, and the very next assertion fails with
        // credentialIdentityNotFound until the user opens the main app.
        //
        // The queue means "not yet in the cache the extension reads", so the
        // app clears it when it merges AND refreshes the cache.
        #expect(queue.removed.isEmpty)
    }

    @Test("pushes exactly one record")
    func happyPath() async throws {
        let (publisher, pusher, _, key) = makePublisher()

        let outcome = await publisher.publish(passkey())

        #expect(outcome == .published)
        #expect(pusher.created.count == 1)

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

}
