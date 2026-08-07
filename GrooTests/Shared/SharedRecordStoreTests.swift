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
