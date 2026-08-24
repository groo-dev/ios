//
//  PasswordPublisherTests.swift
//  GrooTests
//

import CryptoKit
import Foundation
import Testing
@testable import Groo

struct PasswordPublisherTests {

    final class SpyPusher: PasswordRecordPushing, @unchecked Sendable {
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

    struct Boom: Error {}

    static func pending(id: String = "item-1") -> SharedPendingPasswordItem {
        SharedNewLoginDraft(name: "github.com", username: "me", password: "hunter2", site: "github.com")
            .pendingItem(id: id, now: 1_700_000_000_123)
    }

    private func makePublisher(pusher: SpyPusher = SpyPusher()) -> (PasswordPublisher, SpyPusher, SymmetricKey) {
        let key = SymmetricKey(size: .bits256)
        return (PasswordPublisher(pusher: pusher, vaultKey: key), pusher, key)
    }

    // The guard that caught the equivalent passkey bug: the payload must decode
    // as the app's REAL model, not the lossy Shared one it came from.
    @Test("payload decodes as PassPasswordItem, the shape every client expects")
    func payloadMatchesTheAppModel() throws {
        let (publisher, _, _) = makePublisher()

        let data = try publisher.payload(for: Self.pending())
        let decoded = try JSONDecoder().decode(PassPasswordItem.self, from: data)

        #expect(decoded.id == "item-1")
        #expect(decoded.type == .password)
        #expect(decoded.name == "github.com")
        #expect(decoded.username == "me")
        #expect(decoded.password == "hunter2")
        #expect(decoded.urls == ["https://github.com"])
        #expect(decoded.createdAt == 1_700_000_000_123)
        #expect(decoded.updatedAt == 1_700_000_000_123)
    }

    @Test("payload timestamps come from the envelope, not from the clock")
    func payloadUsesTheEnvelopeTimestamps() throws {
        let (publisher, _, _) = makePublisher()

        let object = try JSONSerialization.jsonObject(
            with: try publisher.payload(for: Self.pending())
        ) as? [String: Any]

        // Re-stamping here would make the app's drained copy differ from the
        // pushed record and rewrite a record that was already correct.
        #expect(object?["createdAt"] as? Int == 1_700_000_000_123)
        #expect(object?["updatedAt"] as? Int == 1_700_000_000_123)
    }

    @Test("payload omits absent optionals rather than sending null")
    func payloadOmitsAbsentOptionals() throws {
        let (publisher, _, _) = makePublisher()

        let object = try JSONSerialization.jsonObject(
            with: try publisher.payload(for: Self.pending())
        ) as? [String: Any]

        #expect(object?.keys.sorted() == [
            "createdAt", "id", "name", "password", "type", "updatedAt", "urls", "username",
        ])
    }

    @Test("the pushed record decrypts to something PassPasswordItem can decode")
    func pushedRecordIsDecodableEndToEnd() async throws {
        let (publisher, pusher, key) = makePublisher()

        _ = await publisher.publish(Self.pending())

        let sent = try #require(pusher.created.first)
        let decoded = try SharedRecordCrypto.decryptRecord(
            encryptedData: sent.encryptedData, iv: sent.iv,
            wrappedRecordKey: sent.wrappedRecordKey, wrapIv: sent.wrapIv,
            vaultKey: key
        )
        #expect(decoded.kind == .item)
        let item = try JSONDecoder().decode(PassPasswordItem.self, from: decoded.data)
        #expect(item.password == "hunter2")
    }

    @Test("a format-1 vault leaves the login queued and pushes nothing")
    func formatOneIsNotPushed() async throws {
        let pusher = SpyPusher()
        pusher.format = 1
        let (publisher, _, _) = makePublisher(pusher: pusher)

        let outcome = await publisher.publish(Self.pending())

        #expect(outcome == .queued(reason: "format 1"))
        #expect(pusher.created.isEmpty)
    }

    @Test("a failing push leaves the login queued and never throws")
    func pushFailureIsQueuedNotThrown() async throws {
        let pusher = SpyPusher()
        pusher.createError = Boom()
        let (publisher, _, _) = makePublisher(pusher: pusher)

        let outcome = await publisher.publish(Self.pending())

        guard case .queued = outcome else {
            Issue.record("expected .queued, got \(outcome)")
            return
        }
    }

    @Test("a failing format probe leaves the login queued and never throws")
    func formatProbeFailureIsQueued() async throws {
        let pusher = SpyPusher()
        pusher.formatError = Boom()
        let (publisher, _, _) = makePublisher(pusher: pusher)

        let outcome = await publisher.publish(Self.pending())

        guard case .queued = outcome else {
            Issue.record("expected .queued, got \(outcome)")
            return
        }
        #expect(pusher.created.isEmpty)
    }

    @Test("a successful push reports published")
    func successReportsPublished() async throws {
        let (publisher, pusher, _) = makePublisher()

        #expect(await publisher.publish(Self.pending()) == .published)
        #expect(pusher.created.count == 1)
    }
}
