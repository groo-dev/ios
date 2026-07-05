//
//  ScratchpadViewSnapshotTests.swift
//  GrooTests
//
//  Phase 7: Scratchpad view coverage that does NOT need the Task 8 store
//  extraction — the pure list, the locked tab, the WKWebView-backed editor
//  surfaces (render-only), and the Coordinator's message handling driven
//  through a WKScriptMessage stub.
//

import SnapshotTesting
import SwiftUI
import Testing
import WebKit
@testable import Groo

extension NetworkStubbedSuites {

@MainActor
@Suite(.serialized, .snapshots(record: .missing))
struct ScratchpadViewSnapshotTests {
    static func pad(id: String, content: String, updatedAt: Int = 1_700_000_000_000) -> DecryptedScratchpad {
        DecryptedScratchpad(id: id, content: content, files: [],
                            createdAt: 1_699_000_000_000, updatedAt: updatedAt)
    }

    @Test func scratchpadListStates() {
        let pads = [
            Self.pad(id: "p-1", content: "# Shopping\nmilk, eggs"),
            Self.pad(id: "p-2", content: "# Ideas\n- render harness"),
            Self.pad(id: "p-3", content: ""),   // "Untitled" title branch
        ]
        assertViewSnapshot(
            of: NavigationStack {
                ScratchpadListView(pads: pads, selectedId: "p-2", onSelect: { _ in },
                                   onDelete: { _ in }, onCreate: {})
            },
            named: "populated")
        assertViewSnapshot(
            of: NavigationStack {
                ScratchpadListView(pads: [], selectedId: nil, onSelect: { _ in },
                                   onDelete: { _ in }, onCreate: {})
            },
            named: "empty")
    }

    @Test func scratchpadTabLocked() throws {
        StubURLProtocol.reset()
        let (service, store) = try PadViewSnapshotTests.lockedPadService()
        assertViewSnapshot(
            of: ScratchpadTabView(padService: service,
                                  syncService: PadViewSnapshotTests.offlineSync(store: store))
                .environment(AuthService()),
            named: "locked")
    }

    @Test func scratchpadEditorRendersOnly() {
        ViewRender.assertRenders(
            ScratchpadEditorView(scratchpad: Self.pad(id: "p-1", content: "# Hello"),
                                 onContentChange: { _ in }))
    }

    @Test func scratchpadWebViewRendersOnly() {
        ViewRender.assertRenders(
            ScratchpadWebView(initialContent: "# Hello", onContentChange: { _ in },
                              onReady: {}, onError: { _ in }, webView: .constant(nil)))
    }

    @Test func coordinatorRoutesScriptMessages() async {
        final class StubScriptMessage: WKScriptMessage {
            private let stubbedBody: Any
            init(body: Any) { self.stubbedBody = body; super.init() }
            override var body: Any { stubbedBody }
            override var name: String { "grooEditor" }
        }

        var readyCount = 0
        var contents: [String] = []
        var errors: [String] = []
        let view = ScratchpadWebView(
            initialContent: "seed",
            onContentChange: { contents.append($0) },
            onReady: { readyCount += 1 },
            onError: { errors.append($0) },
            webView: .constant(nil))
        let coordinator = view.makeCoordinator()
        let controller = WKUserContentController()

        coordinator.userContentController(controller, didReceive: StubScriptMessage(body: ["type": "ready"]))
        coordinator.userContentController(controller, didReceive: StubScriptMessage(body: ["type": "contentChanged", "content": "# Edited"]))
        coordinator.userContentController(controller, didReceive: StubScriptMessage(body: ["type": "error", "message": "editor exploded"]))
        coordinator.userContentController(controller, didReceive: StubScriptMessage(body: "not-a-dict"))
        await Task.yield()   // in case the coordinator hops to the main queue

        #expect(readyCount == 1)
        #expect(contents == ["# Edited"])
        #expect(errors == ["editor exploded"])
    }
}
}
