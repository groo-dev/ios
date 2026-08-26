//
//  PassRecordSyncTests.swift
//  GrooTests
//

import CryptoKit
import Foundation
import Testing
@testable import Groo

struct PassRecordSyncTests {
    private let vaultKey = SymmetricKey(size: .bits256)

    private func serverRecord(
        id: String,
        seq: Int,
        kind: SharedRecordKind = .item,
        version: Int = 1,
        payload: String
    ) throws -> SharedServerRecord {
        let enc = try SharedRecordCrypto.encryptRecord(
            id: id, kind: kind, payload: Data(payload.utf8), vaultKey: vaultKey
        )
        return SharedServerRecord(
            id: id,
            encryptedData: enc.encryptedData,
            iv: enc.iv,
            wrappedRecordKey: enc.wrappedRecordKey,
            wrapIv: enc.wrapIv,
            version: version,
            seq: seq,
            isDeleted: false,
            createdAt: 1,
            updatedAt: 1
        )
    }

    private func tombstone(id: String, seq: Int) -> SharedServerRecord {
        SharedServerRecord(
            id: id, encryptedData: nil, iv: nil, wrappedRecordKey: nil, wrapIv: nil,
            version: 2, seq: seq, isDeleted: true, createdAt: 1, updatedAt: 1
        )
    }

    private func page(
        _ records: [SharedServerRecord],
        nextSeq: Int,
        hasMore: Bool = false
    ) -> SharedRecordsResponse {
        SharedRecordsResponse(
            records: records, nextSeq: nextSeq, hasMore: hasMore
        )
    }

    private func item(_ id: String, name: String, updatedAt: Int = 1) -> String {
        """
        {"id":"\(id)","type":"password","name":"\(name)","username":"u",\
        "password":"p","urls":[],"createdAt":1,"updatedAt":\(updatedAt)}
        """
    }

    // MARK: - apply

    @Test("adds records and advances the cursor")
    func addsRecords() throws {
        let state = try PassRecordSync.apply(
            .empty,
            page: page([try serverRecord(id: "a", seq: 1, payload: item("a", name: "A"))], nextSeq: 1),
            vaultKey: vaultKey
        )
        #expect(state.records.count == 1)
        #expect(state.cursor == 1)
    }

    @Test("removes tombstoned records")
    func removesTombstones() throws {
        var state = try PassRecordSync.apply(
            .empty,
            page: page([try serverRecord(id: "a", seq: 1, payload: item("a", name: "A"))], nextSeq: 1),
            vaultKey: vaultKey
        )
        state = try PassRecordSync.apply(
            state, page: page([tombstone(id: "a", seq: 2)], nextSeq: 2), vaultKey: vaultKey
        )
        #expect(state.records.isEmpty)
        #expect(state.cursor == 2)
    }

    @Test("never moves the cursor backwards")
    func cursorNeverRewinds() throws {
        var state = try PassRecordSync.apply(.empty, page: page([], nextSeq: 10), vaultKey: vaultKey)
        state = try PassRecordSync.apply(state, page: page([], nextSeq: 3), vaultKey: vaultKey)
        #expect(state.cursor == 10)
    }

    @Test("skips a record it cannot decrypt rather than failing the whole sync")
    func skipsUndecryptable() throws {
        let good = try serverRecord(id: "a", seq: 1, payload: item("a", name: "A"))
        let foreign = SharedServerRecord(
            id: "b",
            encryptedData: good.encryptedData,
            iv: good.iv,
            // Wrapped under a different vault key: unopenable here.
            wrappedRecordKey: try SharedRecordCrypto.encryptRecord(
                id: "b", kind: .item, payload: Data("{}".utf8),
                vaultKey: SymmetricKey(size: .bits256)
            ).wrappedRecordKey,
            wrapIv: good.wrapIv,
            version: 1, seq: 2, isDeleted: false, createdAt: 1, updatedAt: 1
        )

        let state = try PassRecordSync.apply(
            .empty, page: page([good, foreign], nextSeq: 2), vaultKey: vaultKey
        )
        // One bad row must not make the whole vault unopenable.
        #expect(state.records.count == 1)
        #expect(state.records["a"] != nil)
    }

    // MARK: - pull

    @Test("follows pagination until hasMore is false")
    func followsPagination() async throws {
        let pages = [
            page([try serverRecord(id: "a", seq: 1, payload: item("a", name: "A"))], nextSeq: 1, hasMore: true),
            page([try serverRecord(id: "b", seq: 2, payload: item("b", name: "B"))], nextSeq: 2),
        ]
        var seen: [Int] = []
        var index = 0

        let state = try await PassRecordSync.pull(from: .empty, vaultKey: vaultKey) { since in
            seen.append(since)
            defer { index += 1 }
            return pages[index]
        }

        #expect(seen == [0, 1])
        #expect(state.records.count == 2)
        #expect(state.cursor == 2)
    }

    @Test("discards local state and resyncs when the cursor is too old")
    func resyncsOnCursorTooOld() async throws {
        var stale = PassRecordState.empty
        stale.cursor = 99
        stale.records["ghost"] = PassDecodedRecord(
            id: "ghost", kind: .item, data: Data("{}".utf8), version: 1, seq: 1
        )

        var seen: [Int] = []
        var first = true
        let state = try await PassRecordSync.pull(from: stale, vaultKey: vaultKey) { since in
            seen.append(since)
            if first {
                first = false
                throw APIError.httpError(statusCode: 409, message: "CURSOR_TOO_OLD")
            }
            return page([try self.serverRecord(id: "a", seq: 1, payload: self.item("a", name: "A"))], nextSeq: 1)
        }

        #expect(seen == [99, 0])
        // A record deleted while we were away must not survive the resync.
        #expect(state.records["ghost"] == nil)
        #expect(state.records["a"] != nil)
    }

    @Test("does not loop forever if the server rejects a full resync")
    func rejectsCursorOnFullSync() async {
        await #expect(throws: PassRecordSyncError.self) {
            _ = try await PassRecordSync.pull(from: .empty, vaultKey: vaultKey) { _ in
                throw APIError.httpError(statusCode: 409, message: "CURSOR_TOO_OLD")
            }
        }
    }

    @Test("propagates a non-cursor error instead of silently resyncing")
    func propagatesOtherErrors() async {
        await #expect(throws: APIError.self) {
            _ = try await PassRecordSync.pull(from: .empty, vaultKey: self.vaultKey) { _ in
                throw APIError.unauthorized
            }
        }
    }

    // MARK: - buildVault

    @Test("assembles items and folders through the existing decoder")
    func buildsVault() async throws {
        let state = try await PassRecordSync.pull(from: .empty, vaultKey: vaultKey) { _ in
            page([
                try self.serverRecord(id: "a", seq: 1, payload: self.item("a", name: "GitHub", updatedAt: 30)),
                try self.serverRecord(
                    id: "f", seq: 2, kind: .folder,
                    payload: #"{"id":"f","name":"Work"}"#
                ),
            ], nextSeq: 2)
        }

        let vault = try PassRecordSync.buildVault(from: state)
        #expect(vault.items.count == 1)
        #expect(vault.folders.map(\.name) == ["Work"])
        #expect(vault.lastModified == 30)
    }

    @Test("carries the sharing private key through")
    func carriesPrivateKey() throws {
        let vault = try PassRecordSync.buildVault(from: .empty, rsaPrivateKey: "jwk-\"quoted\"")
        // Round-tripped through JSON encoding, so an embedded quote must survive.
        #expect(vault.rsaPrivateKey == "jwk-\"quoted\"")
    }

    @Test("an item this build cannot model decodes as corrupted, not as a failure")
    func unknownItemTypeBecomesCorrupted() async throws {
        let state = try await PassRecordSync.pull(from: .empty, vaultKey: vaultKey) { _ in
            page([
                try self.serverRecord(
                    id: "x", seq: 1,
                    payload: #"{"id":"x","type":"future_type","name":"Later"}"#
                )
            ], nextSeq: 1)
        }

        // The blob format already preserves unmodelled items as .corrupted so
        // they are never destroyed; records must behave identically.
        let vault = try PassRecordSync.buildVault(from: state)
        #expect(vault.items.count == 1)
    }

    @Test("builds an empty vault from no records")
    func emptyVault() throws {
        let vault = try PassRecordSync.buildVault(from: .empty)
        #expect(vault.items.isEmpty)
        #expect(vault.folders.isEmpty)
    }
}
