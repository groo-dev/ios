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
        // ScratchpadUnlockView (rendered here, service is locked) lost its own
        // NavigationStack when Scratchpad's stack was hoisted to the host, but
        // (unlike PadUnlockView) it did show a visible bar — its
        // navigationTitle("Scratchpad") — which now needs an ancestor stack
        // to render through. Wrapped here to mirror the host stack
        // MainTabView always supplies now, matching PadViewSnapshotTests'
        // convention for call sites that depended on a screen's own stack.
        assertViewSnapshot(
            of: NavigationStack {
                ScratchpadTabView(padService: service,
                                  syncService: PadViewSnapshotTests.offlineSync(store: store))
            }
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

    // MARK: - Store-injected view states (Phase 7 Task 8)

    @Test func scratchpadViewStoreStates() async throws {
        let env = try ScratchpadStoreTests.makeEnv()
        try ScratchpadStoreTests.seed(env, id: "p-1", content: "# Shopping\nmilk, eggs", updatedAt: 1_700_100_000)
        try ScratchpadStoreTests.seed(env, id: "p-2", content: "# Ideas", updatedAt: 1_700_000_000)
        await env.store.loadAllScratchpads()

        // Render-only, not a pixel snapshot: ScratchpadContentView's own
        // .task unconditionally re-invokes loadAllScratchpads() on appear
        // (matching the pre-refactor view, which always reloaded on
        // .task regardless of any pre-loaded store) and that reload
        // performs a real (if stubless-and-failing) SyncService.sync()
        // network round trip. Confirmed via diagnostic instrumentation:
        // the store's own state does converge (isLoading flips back to
        // false, allPads repopulates) once that task's await chain
        // resolves, but this harness's manual CALayer render
        // (ViewRender.draw, see ViewRenderHarness.swift) does not
        // reliably re-flush for a conditional branch switch driven by a
        // *post-appear* async Task mutation — only assertSettledRenders'
        // non-comparing check is meaningful here. Every existing
        // assertSettledViewSnapshot use elsewhere in this codebase
        // (PadListView, WalletListView, …) populates its state via a
        // *synchronous* onAppear, so it never exercises this path.
        await ViewRender.assertSettledRenders(
            ScratchpadView(padService: env.pad.service, syncService: env.sync, store: env.store)
                .environment(AuthService()))

        let emptyEnv = try ScratchpadStoreTests.makeEnv()
        await emptyEnv.store.loadAllScratchpads()
        await ViewRender.assertSettledRenders(
            ScratchpadView(padService: emptyEnv.pad.service, syncService: emptyEnv.sync,
                           store: emptyEnv.store)
                .environment(AuthService()))
    }

    @Test func scratchpadViewEditorStateRendersOnly() async throws {
        let env = try ScratchpadStoreTests.makeEnv()
        try ScratchpadStoreTests.seed(env, id: "p-1", content: "# Editing", updatedAt: 1_700_000_000)
        await env.store.loadAllScratchpads()
        env.store.selectPad(try #require(env.store.allPads.first))
        // Editor hosts a live WKWebView — render-only.
        await ViewRender.assertSettledRenders(
            ScratchpadView(padService: env.pad.service, syncService: env.sync, store: env.store)
                .environment(AuthService()))
    }

    // Gap-menu follow-on (P7 Task 9): the iPad side-by-side branch
    // (horizontalSizeClass == .regular) — never exercised by the iPhone
    // NavigationStack-based tests above. Both no-selection and
    // with-selection sub-states.
    @Test func scratchpadViewIPadSplitRendersOnly() async throws {
        let env = try ScratchpadStoreTests.makeEnv()
        try ScratchpadStoreTests.seed(env, id: "p-1", content: "# Shopping\nmilk, eggs", updatedAt: 1_700_000_000)
        await env.store.loadAllScratchpads()
        await ViewRender.assertSettledRenders(
            ScratchpadView(padService: env.pad.service, syncService: env.sync, store: env.store)
                .environment(AuthService())
                .environment(\.horizontalSizeClass, .regular))

        env.store.selectPad(try #require(env.store.allPads.first))
        await ViewRender.assertSettledRenders(
            ScratchpadView(padService: env.pad.service, syncService: env.sync, store: env.store)
                .environment(AuthService())
                .environment(\.horizontalSizeClass, .regular))
    }

    // Fix-wave finding 2: at the merge base, none of loading/error/empty/
    // content had a navigation bar on iPad — the whole regular-width host
    // never wrapped a NavigationStack around any of them. Now that
    // FeatureContent hosts always supply one, the suppression that used to
    // live only inside contentView's regular branch must cover every state,
    // not just the loaded one, since isLoading defaults to true and every
    // iPad visit hits loadingView first. Exercises the *loading* branch
    // specifically, via assertViewSnapshot's synchronous single-frame render
    // (the .task that would flip isLoading never runs).
    //
    // No structural (isNavigationBarHidden) counterpart here, unlike finding
    // 3 below: verified empirically (both in this harness, settled with
    // yields, and on a real iPad simulator with a throwaway QA build) that a
    // NavigationStack with no navigationTitle anywhere in its tree — true of
    // every one of this screen's four iPad states, loaded included — settles
    // isNavigationBarHidden to true on its own, with or without an explicit
    // .toolbar(.hidden,...). That default happens to mask the bug in
    // isolation, so a structural assertion here would pass identically
    // against the pre-fix code and prove nothing. The pixel snapshot is kept
    // as the regression net finding 2 asks for (and as documentation of the
    // correct state); the explicit suppression is still the right fix
    // because it does not rely on that undocumented default holding across
    // OS versions, dynamic type, or ambient navigation state elsewhere in
    // the same stack — which is exactly what finding 3's pushed case below
    // demonstrates going the other way.
    @Test func scratchpadViewIPadLoadingHidesNavigationBar() throws {
        let env = try ScratchpadStoreTests.makeEnv()
        assertViewSnapshot(
            of: NavigationStack {
                ScratchpadView(padService: env.pad.service, syncService: env.sync, store: env.store)
                    .environment(AuthService())
                    .environment(\.horizontalSizeClass, .regular)
            },
            named: "ipadLoading")
    }

    // Fix-wave finding 3: the same suppression must not fire when this
    // screen is pushed from More (isPushedDestination) even though it still
    // reports horizontalSizeClass == .regular — the case that hits on a
    // Max-size iPhone in landscape. Structural for the same reason as above.
    @Test func scratchpadViewPushedKeepsNavigationBarEvenAtRegularWidth() async throws {
        let env = try ScratchpadStoreTests.makeEnv()
        let nav = await ViewRender.settledNavigationController(
            hosting: NavigationStack {
                ScratchpadView(padService: env.pad.service, syncService: env.sync, store: env.store)
                    .environment(AuthService())
                    .environment(\.horizontalSizeClass, .regular)
                    .environment(\.isPushedDestination, true)
            })
        #expect(nav?.isNavigationBarHidden == false)
    }

    // Gap-menu follow-on (P7 Task 9): the safeAreaInset loadWarning banner —
    // a decrypt failure alongside a good pad (mirrors
    // ScratchpadStoreTests.decryptFailureCountsIntoLoadWarning).
    @Test func scratchpadViewLoadWarningRendersOnly() async throws {
        let env = try ScratchpadStoreTests.makeEnv()
        try ScratchpadStoreTests.seed(env, id: "p-good", content: "# Good", updatedAt: 1_700_100_000)
        let garbage = LocalScratchpad(
            id: "p-bad",
            encryptedContentJSON: #"{"ciphertext":"Z2FyYmFnZQ==","iv":"AAAAAAAAAAAAAAAA","version":1}"#,
            createdAt: Date(timeIntervalSince1970: 1_699_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000))
        env.pad.store.context.insert(garbage)
        try env.pad.store.context.save()
        await env.store.loadAllScratchpads()
        await ViewRender.assertSettledRenders(
            ScratchpadView(padService: env.pad.service, syncService: env.sync, store: env.store)
                .environment(AuthService()))
    }
}
}
