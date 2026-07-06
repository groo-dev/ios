//
//  ScratchpadStoreTests.swift
//  GrooTests
//
//  Direct tests for the Phase 7 ScratchpadStore extraction: load/sort,
//  decrypt-failure warnings, selection, zero-debounce save (await the
//  task — no sleeps), CRUD, and remote WebSocket handlers.
//

import CryptoKit
import Foundation
import Testing
@testable import Groo

extension NetworkStubbedSuites {

@MainActor
@Suite(.serialized)
struct ScratchpadStoreTests {
    struct Env {
        let store: ScratchpadStore
        let pad: PadServiceTests.Env
        let sync: SyncService
        let factory: FakeConnectionFactory
        let editorPushes: () -> [String]
    }

    static func makeEnv(saveDebounce: Duration = .zero) throws -> Env {
        StubURLProtocol.reset()
        let padEnv = try PadServiceTests.makeUnlockedEnv()
        let sync = SyncService(
            api: APIClient(baseURL: URL(string: "https://pad.test")!,
                           sessionConfiguration: StubURLProtocol.stubbedConfiguration(),
                           tokenProvider: { "sync-token" }),
            store: padEnv.store, monitorsNetwork: false)
        let factory = FakeConnectionFactory()
        let tokens = FakeTokenProvider()
        let timers = TimerRecorder()
        let store = ScratchpadStore(
            padService: padEnv.service, syncService: sync,
            makeWebSocket: {
                WebSocketService(authService: tokens, makeConnection: factory.make,
                                 makeTimer: timers.make)
            },
            saveDebounce: saveDebounce)
        var pushes: [String] = []
        store.setEditorContent = { pushes.append($0) }
        return Env(store: store, pad: padEnv, sync: sync, factory: factory,
                   editorPushes: { pushes })
    }

    static func seed(_ env: Env, id: String, content: String, updatedAt: Int) throws {
        let scratchpad = LocalScratchpad(
            id: id,
            encryptedContentJSON: try PadViewSnapshotTests.encryptedJSON(content, key: env.pad.key),
            createdAt: Date(timeIntervalSince1970: 1_699_000_000),
            updatedAt: Date(timeIntervalSince1970: TimeInterval(updatedAt)))
        env.pad.store.context.insert(scratchpad)
        try env.pad.store.context.save()
    }

    static func decryptedContent(_ env: Env, id: String) throws -> String {
        let local = try #require(env.sync.getEncryptedScratchpad(id: id))
        return try env.pad.service.decryptScratchpad(local).content
    }

    // MARK: - Loading

    @Test func loadSortsNewestFirstAndClearsLoading() async throws {
        let env = try Self.makeEnv()
        try Self.seed(env, id: "p-old", content: "# Old", updatedAt: 1_700_000_000)
        try Self.seed(env, id: "p-new", content: "# New", updatedAt: 1_700_100_000)

        await env.store.loadAllScratchpads()

        #expect(env.store.allPads.map(\.id) == ["p-new", "p-old"])
        #expect(!env.store.isLoading)
        #expect(env.store.loadWarning == nil)
        #expect(env.store.error == nil)
    }

    @Test func decryptFailureCountsIntoLoadWarning() async throws {
        let env = try Self.makeEnv()
        try Self.seed(env, id: "p-good", content: "# Good", updatedAt: 1_700_100_000)
        // Valid payload JSON, garbage ciphertext → decryptScratchpad throws
        let garbage = LocalScratchpad(
            id: "p-bad",
            encryptedContentJSON: #"{"ciphertext":"Z2FyYmFnZQ==","iv":"AAAAAAAAAAAAAAAA","version":1}"#,
            createdAt: Date(timeIntervalSince1970: 1_699_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000))
        env.pad.store.context.insert(garbage)
        try env.pad.store.context.save()

        await env.store.loadAllScratchpads()

        #expect(env.store.allPads.map(\.id) == ["p-good"])
        #expect(env.store.loadWarning == "1 scratchpad couldn't be decrypted")
        env.store.dismissLoadWarning()
        #expect(env.store.loadWarning == nil)
    }

    // MARK: - Selection

    @Test func selectPadPushesEditorContentAndTracksSaved() async throws {
        let env = try Self.makeEnv()
        try Self.seed(env, id: "p-1", content: "# One", updatedAt: 1_700_000_000)
        await env.store.loadAllScratchpads()

        env.store.selectPad(try #require(env.store.allPads.first))

        #expect(env.store.selectedPad?.id == "p-1")
        #expect(env.store.lastSavedContent == "# One")
        #expect(env.editorPushes() == ["# One"])
    }

    // MARK: - Debounced save

    @Test func contentChangeSavesThroughTheDebounce() async throws {
        let env = try Self.makeEnv()
        try Self.seed(env, id: "p-1", content: "# One", updatedAt: 1_700_000_000)
        await env.store.loadAllScratchpads()
        env.store.selectPad(try #require(env.store.allPads.first))
        // SyncService.updateScratchpad has no offline-queue path (unlike
        // addItem/deleteItem) — it always posts to the network, so the
        // update must be stubbed here (mirrors SyncServiceScratchpadTests).
        StubURLProtocol.enqueue(method: "PUT", pathSuffix: "/v1/scratchpads/p-1", json: #"{"success":true}"#)

        env.store.handleContentChange("# One edited", padId: "p-1")
        await env.store.saveTask?.value

        #expect(env.store.lastSavedContent == "# One edited")
        #expect(!env.store.saveFailed)
        #expect(!env.store.isSaving)
        #expect(try Self.decryptedContent(env, id: "p-1") == "# One edited")
        #expect(env.store.selectedPad?.content == "# One edited")
    }

    @Test func unchangedContentDoesNotScheduleASave() async throws {
        let env = try Self.makeEnv()
        try Self.seed(env, id: "p-1", content: "# One", updatedAt: 1_700_000_000)
        await env.store.loadAllScratchpads()
        env.store.selectPad(try #require(env.store.allPads.first))

        env.store.handleContentChange("# One", padId: "p-1")

        #expect(env.store.saveTask == nil)
    }

    @Test func saveFailureSetsFlagAndPreservesLastSaved() async throws {
        let env = try Self.makeEnv()
        try Self.seed(env, id: "p-1", content: "# One", updatedAt: 1_700_000_000)
        await env.store.loadAllScratchpads()
        env.store.selectPad(try #require(env.store.allPads.first))

        env.pad.service.lock()   // encryptScratchpadContent now throws
        env.store.handleContentChange("# Doomed edit", padId: "p-1")
        await env.store.saveTask?.value

        #expect(env.store.saveFailed)
        #expect(env.store.lastSavedContent == "# One", "failed save must leave the retry marker untouched")
    }

    // MARK: - Create / delete

    @Test func createPadSelectsTheNewPad() async throws {
        let env = try Self.makeEnv()
        await env.store.loadAllScratchpads()
        // createScratchpad always posts to the network (no offline queue) —
        // stub the server id (mirrors SyncServiceScratchpadTests).
        StubURLProtocol.enqueue(method: "POST", pathSuffix: "/v1/scratchpads", json: #"{"id":"p-new"}"#)

        await env.store.createPad()

        #expect(env.store.allPads.count == 1)
        #expect(env.store.selectedPad != nil)
        #expect(env.store.selectedPad?.content == "# New Scratchpad\n")
        #expect(!env.store.isCreating)
        #expect(env.store.actionError == nil)
    }

    @Test func deleteSelectedPadReselectsFirstRemaining() async throws {
        let env = try Self.makeEnv()
        try Self.seed(env, id: "p-1", content: "# One", updatedAt: 1_700_100_000)
        try Self.seed(env, id: "p-2", content: "# Two", updatedAt: 1_700_000_000)
        await env.store.loadAllScratchpads()
        env.store.selectPad(try #require(env.store.allPads.first))   // p-1
        // deleteScratchpad always calls the network (no offline queue) —
        // stub it (mirrors SyncServiceScratchpadTests).
        StubURLProtocol.enqueue(method: "DELETE", pathSuffix: "/v1/scratchpads/p-1", status: 204, json: "")

        await env.store.deletePad(try #require(env.store.selectedPad))

        #expect(env.store.allPads.map(\.id) == ["p-2"])
        #expect(env.store.selectedPad?.id == "p-2")
        #expect(env.editorPushes().last == "# Two")
    }

    // MARK: - Remote events

    @Test func remoteUpdateRefreshesPadAndEditor() async throws {
        let env = try Self.makeEnv()
        try Self.seed(env, id: "p-1", content: "# One", updatedAt: 1_700_000_000)
        await env.store.loadAllScratchpads()
        env.store.selectPad(try #require(env.store.allPads.first))

        // Another device updated the encrypted content behind our back
        let local = try #require(env.sync.getEncryptedScratchpad(id: "p-1"))
        local.encryptedContentJSON = try PadViewSnapshotTests.encryptedJSON("# One (remote)", key: env.pad.key)
        try env.pad.store.context.save()

        await env.store.remoteScratchpadUpdated(id: "p-1")

        #expect(env.store.allPads.first?.content == "# One (remote)")
        #expect(env.store.selectedPad?.content == "# One (remote)")
        #expect(env.store.lastSavedContent == "# One (remote)")
        #expect(env.editorPushes().last == "# One (remote)")
    }

    @Test func remoteDeleteRemovesAndReselects() async throws {
        let env = try Self.makeEnv()
        try Self.seed(env, id: "p-1", content: "# One", updatedAt: 1_700_100_000)
        try Self.seed(env, id: "p-2", content: "# Two", updatedAt: 1_700_000_000)
        await env.store.loadAllScratchpads()
        env.store.selectPad(try #require(env.store.allPads.first))   // p-1

        env.store.remoteScratchpadDeleted(id: "p-1")

        #expect(env.store.allPads.map(\.id) == ["p-2"])
        #expect(env.store.selectedPad?.id == "p-2")
    }

    @Test func setupWebSocketConnectsThroughTheFactory() async throws {
        let env = try Self.makeEnv()

        await env.store.setupWebSocket()

        #expect(env.store.webSocketService != nil)
        #expect(env.factory.connections.count == 1)
        let connection = try #require(env.factory.connections.first)
        connection.open()
        for _ in 0..<4 { await Task.yield() }
        #expect(env.store.isWebSocketConnected)
        env.store.disconnect()
    }
}
}
