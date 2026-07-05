//
//  SyncServiceScratchpadTests.swift
//  GrooTests
//
//  Scratchpad CRUD passthroughs (deferred from Phase 3): server call + local
//  cache update semantics, including "server failure leaves the local copy
//  untouched".
//

import Foundation
import Testing
@testable import Groo

extension NetworkStubbedSuites {
@MainActor
@Suite(.serialized)
struct SyncServiceScratchpadTests {
    static let payload = PadEncryptedPayload(ciphertext: "Y2lwaGVy", iv: "aXZpdml2aXZpdg==", version: 1)
    static let newPayload = PadEncryptedPayload(ciphertext: "bmV3LWNpcGhlcg==", iv: "aXZpdml2aXZpdg==", version: 1)

    struct EncryptedContentBody: Decodable {
        let encryptedContent: PadEncryptedPayload
    }

    static func makeService() throws -> (service: SyncService, store: LocalStore) {
        let store = try InMemoryLocalStore.make()
        let api = APIClient(
            baseURL: URL(string: "https://pad.test")!,
            sessionConfiguration: StubURLProtocol.stubbedConfiguration(),
            tokenProvider: { "sync-token" }
        )
        return (SyncService(api: api, store: store, monitorsNetwork: false), store)
    }

    static func seedScratchpad(_ store: LocalStore, id: String) throws -> LocalScratchpad {
        let data = try JSONEncoder().encode(payload)
        let scratchpad = LocalScratchpad(
            id: id,
            encryptedContentJSON: try #require(String(data: data, encoding: .utf8)),
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        store.saveScratchpad(scratchpad)
        return scratchpad
    }

    @Test func createScratchpadPostsPayloadAndCachesLocally() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.enqueue(method: "POST", pathSuffix: "/v1/scratchpads", json: #"{"id":"sp-9"}"#)
        let (service, store) = try Self.makeService()

        let id = try await service.createScratchpad(encryptedContent: Self.payload)

        #expect(id == "sp-9")
        let requestBody = try #require(StubURLProtocol.recordedRequests.first?.bodyData)
        #expect(try JSONDecoder().decode(EncryptedContentBody.self, from: requestBody).encryptedContent == Self.payload)
        #expect(store.getScratchpad(id: "sp-9")?.encryptedContent == Self.payload)
    }

    @Test func updateScratchpadPutsAndRefreshesLocalCopy() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.enqueue(method: "PUT", pathSuffix: "/v1/scratchpads/sp-1", json: #"{"success":true}"#)
        let (service, store) = try Self.makeService()
        _ = try Self.seedScratchpad(store, id: "sp-1")

        try await service.updateScratchpad(id: "sp-1", encryptedContent: Self.newPayload)

        let local = try #require(store.getScratchpad(id: "sp-1"))
        #expect(local.encryptedContent == Self.newPayload)
        #expect(local.updatedAt > Date(timeIntervalSince1970: 1_700_000_000))
    }

    @Test func updateScratchpadServerFailureLeavesLocalCopyUntouched() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.enqueue(method: "PUT", pathSuffix: "/v1/scratchpads/sp-1", status: 500, json: #"{"error":"boom"}"#)
        let (service, store) = try Self.makeService()
        _ = try Self.seedScratchpad(store, id: "sp-1")

        await #expect {
            try await service.updateScratchpad(id: "sp-1", encryptedContent: Self.newPayload)
        } throws: { error in
            guard case APIError.httpError(let status, _) = error else { return false }
            return status == 500
        }

        // The local cache must still hold the pre-update content
        #expect(store.getScratchpad(id: "sp-1")?.encryptedContent == Self.payload)
    }

    @Test func deleteScratchpadRemovesLocalCopy() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.enqueue(method: "DELETE", pathSuffix: "/v1/scratchpads/sp-1", status: 204, json: "")
        let (service, store) = try Self.makeService()
        _ = try Self.seedScratchpad(store, id: "sp-1")

        try await service.deleteScratchpad(id: "sp-1")

        #expect(store.getScratchpad(id: "sp-1") == nil)
    }

    @Test func addFileToScratchpadAppendsToLocalFiles() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.enqueue(method: "POST", pathSuffix: "/v1/scratchpads/sp-1/files", json: #"{"success":true}"#)
        let (service, store) = try Self.makeService()
        _ = try Self.seedScratchpad(store, id: "sp-1")
        let file = PadFileAttachment(id: "f-1", encryptedName: Self.payload, size: 42, encryptedType: Self.payload, r2Key: "r2/f-1")

        try await service.addFileToScratchpad(id: "sp-1", file: file)

        #expect(store.getScratchpad(id: "sp-1")?.files == [file])
    }

    @Test func activeScratchpadIsNilWithoutActiveId() throws {
        StubURLProtocol.reset()
        let (service, store) = try Self.makeService()
        _ = try Self.seedScratchpad(store, id: "sp-1")

        // No pull has set activeId — must be nil, not an arbitrary scratchpad
        #expect(service.getActiveScratchpad() == nil)
        #expect(service.getEncryptedScratchpads().map(\.id) == ["sp-1"])
    }
}
}
