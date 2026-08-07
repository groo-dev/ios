//
//  SharedRecordStoreTests.swift
//  GrooTests
//

import CryptoKit
import Foundation
import Testing
@testable import Groo

struct SharedRecordStoreTests {
    private let key = SymmetricKey(size: .bits256)

    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("records-\(UUID().uuidString).enc")
    }

    private func record(
        _ id: String,
        seq: Int,
        deleted: Bool = false
    ) -> SharedServerRecord {
        SharedServerRecord(
            id: id,
            encryptedData: deleted ? nil : "data-\(id)",
            iv: deleted ? nil : "iv",
            wrappedRecordKey: deleted ? nil : "wk",
            wrapIv: deleted ? nil : "wiv",
            version: 1,
            seq: seq,
            isDeleted: deleted,
            createdAt: 1,
            updatedAt: 1
        )
    }

    private func page(
        _ records: [SharedServerRecord],
        nextSeq: Int,
        hasMore: Bool = false
    ) -> SharedRecordsResponse {
        SharedRecordsResponse(
            records: records, nextSeq: nextSeq, hasMore: hasMore, formatVersion: 2
        )
    }

    // MARK: - Persistence

    @Test("returns nil when nothing has been cached")
    func loadEmpty() throws {
        #expect(try SharedRecordStore.load(key: key, fileURL: tempURL()) == nil)
    }

    @Test("round-trips records and cursor")
    func roundTrip() throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let cached = SharedRecordStore.Cached(records: [record("a", seq: 1)], cursor: 7)
        try SharedRecordStore.save(cached, key: key, fileURL: url)

        #expect(try SharedRecordStore.load(key: key, fileURL: url) == cached)
    }

    @Test("the file is not readable with a different key")
    func wrongKeyFails() throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }

        try SharedRecordStore.save(
            SharedRecordStore.Cached(records: [record("a", seq: 1)], cursor: 1),
            key: key, fileURL: url
        )

        #expect(throws: (any Error).self) {
            try SharedRecordStore.load(key: SymmetricKey(size: .bits256), fileURL: url)
        }
    }

    @Test("an unreadable cache throws instead of reading as empty")
    func corruptThrows() throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("not encrypted".utf8).write(to: url)

        // Treating this as empty would silently reset the cursor and force a
        // full resync of every record.
        #expect(throws: (any Error).self) {
            try SharedRecordStore.load(key: key, fileURL: url)
        }
    }

    @Test("clear removes the cache")
    func clearRemoves() throws {
        let url = tempURL()
        try SharedRecordStore.save(
            SharedRecordStore.Cached(records: [record("a", seq: 1)], cursor: 1),
            key: key, fileURL: url
        )

        SharedRecordStore.clear(fileURL: url)

        #expect(try SharedRecordStore.load(key: key, fileURL: url) == nil)
    }

    // MARK: - Delta application

    @Test("adds new records and advances the cursor")
    func appliesAdditions() {
        let result = SharedRecordStore.apply(
            .empty, page: page([record("a", seq: 1)], nextSeq: 1)
        )

        #expect(result.records.map(\.id) == ["a"])
        #expect(result.cursor == 1)
    }

    @Test("replaces an updated record rather than duplicating it")
    func appliesUpdates() {
        var cached = SharedRecordStore.apply(.empty, page: page([record("a", seq: 1)], nextSeq: 1))
        cached = SharedRecordStore.apply(cached, page: page([record("a", seq: 5)], nextSeq: 5))

        #expect(cached.records.count == 1)
        #expect(cached.records.first?.seq == 5)
    }

    @Test("removes tombstoned records")
    func appliesTombstones() {
        var cached = SharedRecordStore.apply(.empty, page: page([record("a", seq: 1)], nextSeq: 1))
        cached = SharedRecordStore.apply(
            cached, page: page([record("a", seq: 2, deleted: true)], nextSeq: 2)
        )

        #expect(cached.records.isEmpty)
        #expect(cached.cursor == 2)
    }

    @Test("never moves the cursor backwards")
    func cursorNeverRewinds() {
        var cached = SharedRecordStore.apply(.empty, page: page([], nextSeq: 10))
        cached = SharedRecordStore.apply(cached, page: page([], nextSeq: 3))

        #expect(cached.cursor == 10)
    }
}

/// The record cache is only useful if the READ path consults it.
///
/// A background refresh persisted records, but `loadCredentials` rebuilt state
/// from the blob cache on every fresh AutoFill process — so a passkey synced
/// from another client was suggested by QuickType (that identity lives in the
/// OS store) yet could not be resolved by `findPasskey`, and the sheet
/// dismissed with credentialIdentityNotFound.
struct AutoFillRecordDecodingTests {
    private let key = SymmetricKey(size: .bits256)

    private func record(id: String, seq: Int, payload: String) throws -> SharedServerRecord {
        let enc = try SharedRecordCrypto.encryptRecord(
            id: id, kind: .item, payload: Data(payload.utf8), vaultKey: key
        )
        return SharedServerRecord(
            id: id, encryptedData: enc.encryptedData, iv: enc.iv,
            wrappedRecordKey: enc.wrappedRecordKey, wrapIv: enc.wrapIv,
            version: 1, seq: seq, isDeleted: false, createdAt: 1, updatedAt: 1
        )
    }

    @Test("decodes a passkey record into something findPasskey can resolve")
    func decodesPasskey() throws {
        let payload = """
        {"id":"pk-1","type":"passkey","name":"webauthn.io","rpId":"webauthn.io",\
        "rpName":"webauthn.io","credentialId":"Y3JlZA","publicKey":"cHVi",\
        "privateKey":"cHJpdg","userHandle":"dWg","userName":"test","signCount":0,\
        "createdAt":1,"updatedAt":1}
        """
        let decoded = SharedRecordDecoder.decodeItems(
            [try record(id: "pk-1", seq: 1, payload: payload)], key: key
        )

        #expect(decoded.passkeys.count == 1)
        #expect(decoded.passkeys.first?.credentialId == "Y3JlZA")
        #expect(decoded.passwords.isEmpty)
    }

    @Test("decodes a password record")
    func decodesPassword() throws {
        let payload = """
        {"id":"pw-1","type":"password","name":"Example","username":"u",\
        "password":"p","urls":["https://example.com"],"createdAt":1,"updatedAt":1}
        """
        let decoded = SharedRecordDecoder.decodeItems(
            [try record(id: "pw-1", seq: 1, payload: payload)], key: key
        )

        #expect(decoded.passwords.count == 1)
        #expect(decoded.passwords.first?.username == "u")
    }

    @Test("skips an unreadable record rather than losing every other credential")
    func skipsUnreadable() throws {
        let good = try record(
            id: "pw-1", seq: 1,
            payload: #"{"id":"pw-1","type":"password","name":"E","username":"u","password":"p","urls":[],"createdAt":1,"updatedAt":1}"#
        )
        let foreign = try SharedRecordCrypto.encryptRecord(
            id: "x", kind: .item, payload: Data("{}".utf8), vaultKey: SymmetricKey(size: .bits256)
        )
        let unreadable = SharedServerRecord(
            id: "x", encryptedData: foreign.encryptedData, iv: foreign.iv,
            wrappedRecordKey: foreign.wrappedRecordKey, wrapIv: foreign.wrapIv,
            version: 1, seq: 2, isDeleted: false, createdAt: 1, updatedAt: 1
        )

        let decoded = SharedRecordDecoder.decodeItems([good, unreadable], key: key)

        #expect(decoded.passwords.count == 1)
    }

    @Test("omits trashed items")
    func omitsTrashed() throws {
        let payload = """
        {"id":"pw-1","type":"password","name":"E","username":"u","password":"p",\
        "urls":[],"createdAt":1,"updatedAt":1,"deletedAt":99}
        """
        let decoded = SharedRecordDecoder.decodeItems(
            [try record(id: "pw-1", seq: 1, payload: payload)], key: key
        )

        #expect(decoded.passwords.isEmpty)
    }
}
