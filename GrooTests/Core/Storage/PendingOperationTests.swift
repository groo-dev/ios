//
//  PendingOperationTests.swift
//  GrooTests
//
//  Payload encode/decode roundtrips and FIFO queue semantics against an
//  in-memory LocalStore.
//

import Foundation
import Testing
@testable import Groo

@MainActor
struct PendingOperationTests {
    static let payload = PadEncryptedPayload(ciphertext: "Y2lwaGVy", iv: "aXZpdml2aXZpdg==", version: 1)

    static func makeItem(id: String) -> PadListItem {
        PadListItem(id: id, encryptedText: payload, files: [], createdAt: 1_700_000_000_000)
    }

    @Test func createItemRoundtripsPayload() throws {
        let item = Self.makeItem(id: "item-1")
        let operation = try #require(PendingOperation.createItem(item))

        #expect(operation.operationType == .create)
        #expect(operation.itemId == "item-1")
        #expect(operation.getCreatePayload() == item)
    }

    @Test func deleteItemHasNoPayload() {
        let operation = PendingOperation.deleteItem(id: "item-9")

        #expect(operation.operationType == .delete)
        #expect(operation.itemId == "item-9")
        #expect(operation.payloadJSON == nil)
        #expect(operation.getCreatePayload() == nil)
    }

    @Test func corruptPayloadDecodesToNilNotGarbage() {
        let operation = PendingOperation(type: .create, itemId: "bad", payload: Data("not json".utf8))
        #expect(operation.getCreatePayload() == nil)
    }

    @Test func unknownStoredTypeFallsBackToCreate() {
        let operation = PendingOperation.deleteItem(id: "item-1")
        operation.type = "compact"   // a future/unknown operation type

        #expect(operation.operationType == .create)   // documents the fallback
    }

    @Test func queueIsOrderedByCreationTimeFIFO() throws {
        let store = try InMemoryLocalStore.make()

        let first = PendingOperation.deleteItem(id: "a")
        first.createdAt = Date(timeIntervalSince1970: 100)
        let second = PendingOperation.deleteItem(id: "b")
        second.createdAt = Date(timeIntervalSince1970: 200)
        let third = PendingOperation.deleteItem(id: "c")
        third.createdAt = Date(timeIntervalSince1970: 300)

        // Insert out of order — fetch must sort by createdAt ascending
        try store.addPendingOperation(second)
        try store.addPendingOperation(third)
        try store.addPendingOperation(first)

        #expect(store.getAllPendingOperations().map(\.itemId) == ["a", "b", "c"])
    }

    @Test func removeAndClearPendingOperations() throws {
        let store = try InMemoryLocalStore.make()
        let keep = PendingOperation.deleteItem(id: "keep")
        let drop = PendingOperation.deleteItem(id: "drop")
        try store.addPendingOperation(keep)
        try store.addPendingOperation(drop)

        try store.removePendingOperation(drop)
        #expect(store.getAllPendingOperations().map(\.itemId) == ["keep"])

        store.clearPendingOperations()
        #expect(store.getAllPendingOperations().isEmpty)
    }
}
