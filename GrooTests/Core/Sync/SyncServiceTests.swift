//
//  SyncServiceTests.swift
//  GrooTests
//
//  Offline-first sync orchestration against a stubbed API and an in-memory
//  LocalStore: offline enqueue → reconnect → flush, partial failure keeps
//  the op (no silent drops), 404-delete dedupe, server-truth pull.
//

import Foundation
import Testing
@testable import Groo

extension NetworkStubbedSuites {
@MainActor
@Suite(.serialized)
struct SyncServiceTests {
    static let payload = PadEncryptedPayload(ciphertext: "Y2lwaGVy", iv: "aXZpdml2aXZpdg==", version: 1)

    static func makeItem(id: String) -> PadListItem {
        PadListItem(id: id, encryptedText: payload, files: [], createdAt: 1_700_000_000_000)
    }

    static func itemJSON(id: String) -> String {
        #"{"id":"\#(id)","encryptedText":{"ciphertext":"Y2lwaGVy","iv":"aXZpdml2aXZpdg==","version":1},"files":[],"createdAt":1700000000000}"#
    }

    static func scratchpadJSON(id: String) -> String {
        #"{"id":"\#(id)","encryptedContent":{"ciphertext":"Y2lwaGVy","iv":"aXZpdml2aXZpdg==","version":1},"files":[],"createdAt":1700000000000,"updatedAt":1700000000000}"#
    }

    /// Enqueues a GET /v1/state response (PadUserState shape).
    static func stubState(itemIds: [String] = [], activeId: String = "", scratchpadIds: [String] = []) {
        let list = itemIds.map { itemJSON(id: $0) }.joined(separator: ",")
        let pads = scratchpadIds.map { "\"\($0)\":\(scratchpadJSON(id: $0))" }.joined(separator: ",")
        StubURLProtocol.enqueue(
            method: "GET", pathSuffix: "/v1/state",
            json: #"{"activeId":"\#(activeId)","scratchpads":{\#(pads)},"list":[\#(list)]}"#
        )
    }

    static func makeService() throws -> (service: SyncService, store: LocalStore) {
        let store = try InMemoryLocalStore.make()
        let api = APIClient(
            baseURL: URL(string: "https://pad.test")!,
            sessionConfiguration: StubURLProtocol.stubbedConfiguration(),
            tokenProvider: { "sync-token" }
        )
        let service = SyncService(api: api, store: store, monitorsNetwork: false)
        return (service, store)
    }

    // MARK: - Offline queueing

    @Test func offlineAddQueuesLocallyWithoutNetwork() async throws {
        StubURLProtocol.reset()
        let (service, store) = try Self.makeService()
        service.state.isOnline = false

        await service.addItem(Self.makeItem(id: "item-1"))

        #expect(StubURLProtocol.recordedRequests.isEmpty)
        #expect(service.state.pendingOperationsCount == 1)
        #expect(store.getAllPadItems().map(\.id) == ["item-1"])   // local-first write
        #expect(service.state.status == .offline)
    }

    @Test func syncWhileOfflineMakesNoRequests() async throws {
        StubURLProtocol.reset()
        let (service, _) = try Self.makeService()
        service.state.isOnline = false

        await service.sync()

        #expect(StubURLProtocol.recordedRequests.isEmpty)
        #expect(service.state.status == .offline)
    }

    // MARK: - Reconnect → flush

    @Test func reconnectFlushesQueuedOperationsInOrder() async throws {
        StubURLProtocol.reset()
        let (service, store) = try Self.makeService()
        service.state.isOnline = false
        await service.addItem(Self.makeItem(id: "item-1"))
        await service.addItem(Self.makeItem(id: "item-2"))

        // Pin distinct timestamps so the FIFO assertion can't race on equal Dates
        let operations = store.getAllPendingOperations()
        try #require(operations.count == 2)
        operations.first { $0.itemId == "item-1" }?.createdAt = Date(timeIntervalSince1970: 100)
        operations.first { $0.itemId == "item-2" }?.createdAt = Date(timeIntervalSince1970: 200)

        StubURLProtocol.enqueue(method: "POST", pathSuffix: "/v1/list", json: #"{"success":true}"#)
        Self.stubState(itemIds: ["item-1", "item-2"])

        service.state.isOnline = true
        await service.sync()

        #expect(service.state.status == .idle)
        #expect(service.state.pendingOperationsCount == 0)
        #expect(service.state.lastSyncedAt != nil)
        #expect(StubURLProtocol.recordedRequests.map(\.httpMethod) == ["POST", "POST", "GET"])

        var pushedIds: [String] = []
        for request in StubURLProtocol.recordedRequests where request.httpMethod == "POST" {
            let data = try #require(request.bodyData)
            pushedIds.append(try JSONDecoder().decode(PadListItem.self, from: data).id)
        }
        #expect(pushedIds == ["item-1", "item-2"])
        #expect(Set(store.getAllPadItems().map(\.id)) == ["item-1", "item-2"])
    }

    @Test func onlineAddItemSyncsImmediately() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.enqueue(method: "POST", pathSuffix: "/v1/list", json: #"{"success":true}"#)
        Self.stubState(itemIds: ["item-1"])
        let (service, _) = try Self.makeService()

        await service.addItem(Self.makeItem(id: "item-1"))

        #expect(service.state.status == .idle)
        #expect(service.state.pendingOperationsCount == 0)
        #expect(StubURLProtocol.recordedRequests.map(\.httpMethod) == ["POST", "GET"])
    }

    // MARK: - Partial failure (no silent drops)

    @Test func partialFailureKeepsFailedOperationAndSurfacesError() async throws {
        StubURLProtocol.reset()
        let (service, store) = try Self.makeService()
        service.state.isOnline = false
        await service.addItem(Self.makeItem(id: "item-1"))     // POST will 500
        await service.deleteItem(id: "item-0")                 // DELETE will succeed

        let operations = store.getAllPendingOperations()
        try #require(operations.count == 2)
        operations.first { $0.itemId == "item-1" }?.createdAt = Date(timeIntervalSince1970: 100)
        operations.first { $0.itemId == "item-0" }?.createdAt = Date(timeIntervalSince1970: 200)

        StubURLProtocol.enqueue(method: "POST", pathSuffix: "/v1/list", status: 500, json: #"{"error":"boom"}"#)
        StubURLProtocol.enqueue(method: "DELETE", pathSuffix: "/v1/list/item-0", json: "{}")
        Self.stubState()   // server truth: empty list

        service.state.isOnline = true
        await service.sync()

        // Failed create is retained (no silent drop); the delete was flushed
        #expect(service.state.status == .error("Some changes couldn't be synced"))
        #expect(store.getAllPendingOperations().map(\.itemId) == ["item-1"])
        // Conflict semantics: server truth (empty) wiped the local row, but the
        // queued payload still carries the item — nothing is silently lost
        #expect(store.getAllPadItems().isEmpty)

        // Recovery: the next sync trigger re-pushes the survivor
        StubURLProtocol.reset()
        StubURLProtocol.enqueue(method: "POST", pathSuffix: "/v1/list", json: #"{"success":true}"#)
        Self.stubState(itemIds: ["item-1"])
        await service.sync()

        #expect(service.state.status == .idle)
        #expect(service.state.pendingOperationsCount == 0)
        #expect(store.getAllPadItems().map(\.id) == ["item-1"])
    }

    @Test func corruptCreatePayloadIsKeptForDiagnosisAndFlagged() async throws {
        StubURLProtocol.reset()
        let (service, store) = try Self.makeService()
        try store.addPendingOperation(
            PendingOperation(type: .create, itemId: "bad", payload: Data("garbage".utf8))
        )
        Self.stubState()

        await service.sync()

        // The undecodable operation is skipped, never dropped, and the sync is dirty
        #expect(service.state.status == .error("Some changes couldn't be synced"))
        #expect(store.getAllPendingOperations().map(\.itemId) == ["bad"])
        #expect(StubURLProtocol.recordedRequests.map(\.httpMethod) == ["GET"])
    }

    // MARK: - Dedupe

    @Test func delete404IsTreatedAsAlreadyGone() async throws {
        StubURLProtocol.reset()
        let (service, store) = try Self.makeService()
        service.state.isOnline = false
        await service.deleteItem(id: "ghost")

        StubURLProtocol.enqueue(method: "DELETE", pathSuffix: "/v1/list/ghost", status: 404, json: #"{"error":"not found"}"#)
        Self.stubState()

        service.state.isOnline = true
        await service.sync()

        // 404 = the item is already gone server-side — success, op removed
        #expect(service.state.status == .idle)
        #expect(store.getAllPendingOperations().isEmpty)
    }

    // MARK: - Pull

    @Test func pullReplacesLocalItemsWithServerTruth() async throws {
        StubURLProtocol.reset()
        let (service, store) = try Self.makeService()
        store.savePadItem(from: Self.makeItem(id: "stale-local"))

        Self.stubState(itemIds: ["server-1", "server-2"])
        await service.sync()

        #expect(service.state.status == .idle)
        #expect(Set(store.getAllPadItems().map(\.id)) == ["server-1", "server-2"])
    }

    @Test func pullStoresScratchpadsAndActiveId() async throws {
        StubURLProtocol.reset()
        Self.stubState(activeId: "sp-1", scratchpadIds: ["sp-1", "sp-2"])
        let (service, _) = try Self.makeService()

        await service.sync()

        #expect(Set(service.getEncryptedScratchpads().map(\.id)) == ["sp-1", "sp-2"])
        #expect(service.getActiveScratchpad()?.id == "sp-1")
    }

    @Test func pullFailureSurfacesAsErrorStatus() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.enqueue(method: "GET", pathSuffix: "/v1/state", status: 500, json: #"{"error":"boom"}"#)
        let (service, _) = try Self.makeService()

        await service.sync()

        #expect(service.state.hasError)
        #expect(service.state.lastSyncedAt == nil)
    }
}
}
