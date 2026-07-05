# iOS Test Suite — Phase 3 (Sync & Offline) + Phase 2 Fast-Follows Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Test the sync/offline layer (PendingOperation queue, SyncState transitions, SyncService offline-first orchestration, WebSocketService connect/drop/reconnect state machine, the generic Pad `APIClient`) and land two Phase 2 review fast-follows (APICache real-TTL expiry via injected clock; WalletManager EIP-155 chain-id pin).

**Architecture:** Same retrofit pattern as Phases 1–2, with three seam kinds:
1. **Default-parameter injections** — `APIClient(sessionConfiguration:)`, `APICache(now:)`, `SyncService(monitorsNetwork:)`, `LocalStore(container:)` — production call sites unchanged.
2. **The one sanctioned protocol extraction** (spec: "Socket layer behind a small protocol | Scriptable fake socket"): `WebSocketService`'s URLSession/task/delegate triple moves behind `WebSocketConnection`; the `URLSessionWebSocketDelegate` conformance relocates into a production wrapper (`URLSessionWebSocketConnection`) so tests drive the state machine with a scripted fake. Token access goes behind `WebSocketTokenProviding` (mirrors the `KeychainServicing` extraction). Reconnect/ping timers go through an injected `WebSocketTimerFactory` — the "injected clock" for this phase: tests record delays and fire timer blocks manually, never wait.
3. **SwiftData in memory** — `ModelConfiguration(schema: LocalStore.schema, isStoredInMemoryOnly: true)` via a shared `InMemoryLocalStore` test helper; `LocalStore.shared` (App Group store) is never touched by tests.

Async waits use `withCheckedContinuation` on the service's own callbacks (`onDisconnected`, `onScratchpadUpdated`, factory `onCreate`) — deterministic main-actor FIFO, no yields, no sleeps.

**Tech Stack:** Swift Testing; SwiftData (in-memory containers); `StubURLProtocol` for HTTP suites; scripted fake socket for WebSocket; `xcodebuild` via `scripts/test.sh`.

**Spec:** `docs/superpowers/specs/2026-07-05-ios-test-suite-design.md` (Phase 3 section) + the two fast-follows from the Phase 2 final review.

## Spec-coverage notes (read before implementing)

Three Phase 3 spec bullets describe behavior that **does not exist in production** — do not invent it, and do not test fiction:

- **"retry/backoff via injected clock" (sync queue):** `SyncService`/`PendingOperation` have no timed retry and no backoff. A failed operation is simply kept in the queue and re-pushed on the *next sync trigger* (reconnect, next mutation). The tests pin exactly that (partial-failure test retries on a second `sync()`). The spec's clock-driven backoff intent is real in **WebSocketService** (exponential 2s→30s reconnect), and that is where the injected-timer discipline is applied. Adding timed backoff to the sync queue would be a product change — flag in the final report, out of scope here.
- **"operation coalescing":** not implemented. An offline create followed by an offline delete of the same item enqueues (and later pushes) *both* operations. Flag as a product gap in the final report; no test asserts coalescing that doesn't exist.
- **"conflict cases":** production's conflict story is "server truth wins on pull" — `upsertPadItems` deletes all local rows and reinserts the server list, while unpushed payloads survive inside their `PendingOperation`. The partial-failure and pull-replacement tests document this exactly (including the eyebrow-raising-but-true intermediate state where the local row vanishes yet nothing is lost).

Also deliberately untested: the thin `URLSessionWebSocketConnection` production wrapper (pure delegate-forwarding adapter over `URLSession`; unit tests can't reach a real socket handshake — it is exercised by the existing manual smoke and later by Phase 5 UI runs).

## Global Constraints

- Working directory: `/Users/groo/work/gr/ios`. Test runner: `bash scripts/test.sh --unit` → `** TEST SUCCEEDED **`.
- GrooTests uses synchronized folders — new `.swift` files under `GrooTests/` compile automatically; **never edit the pbxproj**.
- Suites that use `StubURLProtocol` (here: `APIClientTests`, `SyncServiceTests`, plus the existing `APICacheTests`/`WalletManagerTests` being extended) MUST be declared inside `extension NetworkStubbedSuites { ... }` with `@Suite(.serialized)` and call `StubURLProtocol.reset()` first in each test. `SyncStateTests`, `PendingOperationTests`, and `WebSocketServiceTests` touch no shared static state and stay outside the umbrella (parallel-safe).
- **No sleeps, no `Task.yield` polling.** Time is injected (`APICache(now:)`, `WebSocketTimerFactory`); asynchronous effects are awaited via `withCheckedContinuation` on service callbacks.
- Every production change is behavior-preserving. Default-parameter seams keep byte-for-byte default behavior. The WebSocketService protocol extraction (Task 5) is the one structural refactor, pre-approved by the spec's seam table; its default path (`URLSessionWebSocketConnection` + `Timer.scheduledTimer`) must reproduce current behavior exactly, including the 401-retry-once rule and the "non-401 errored completions are ignored by the handshake handler" rule.
- SwiftData in tests: always `InMemoryLocalStore.make()` (in-memory container). Never `LocalStore.shared` — it lives in the App Group container of the host app.
- UserDefaults in tests: none needed this phase; never touch `UserDefaults.standard` (in particular never set the `padAPIBaseURL` override key).
- **Verification discipline:** baseline is **141 unit tests in 18 suites + 1 UI test**, all green. Before each commit: `bash scripts/test.sh --unit` green AND the app builds (`xcodebuild build -project Groo.xcodeproj -scheme Groo -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`). Running totals per task (verify the test count in the xcodebuild summary line matches; if it doesn't, find out why before committing):
  - After Task 1: **152** unit tests, 20 suites
  - After Task 2: **164** unit tests, 21 suites
  - After Task 3: **166** unit tests, 21 suites
  - After Task 4: **176** unit tests, 22 suites
  - After Task 5: **191** unit tests, 23 suites
- Test-failure messages that pin product semantics (e.g. the EIP-155 chain-id, the `"Some changes couldn't be synced"` user-facing message) are intentional couplings — if one fails, investigate the production change, don't silently update the string.

---

### Task 1: LocalStore container seam + PendingOperation & SyncState suites

**Files:**
- Modify: `Groo/Core/Storage/LocalStore.swift:14-34` (static schema + injected-container init)
- Test: `GrooTests/Support/InMemoryLocalStore.swift`
- Test: `GrooTests/Core/Storage/PendingOperationTests.swift`
- Test: `GrooTests/Core/Sync/SyncStateTests.swift`

**Interfaces:**
- Consumes: `PendingOperation` (`createItem`, `deleteItem(id:)`, `getCreatePayload()`, `operationType`), `LocalStore` pending-operation CRUD, `SyncState`/`SyncStatus`, `PadListItem`/`PadEncryptedPayload`.
- Produces: `LocalStore.schema` (static), `LocalStore.init(container:)`, `InMemoryLocalStore.make()` — Task 4 builds `SyncService` on these.

- [ ] **Step 1: Write the failing tests + helper**

`GrooTests/Support/InMemoryLocalStore.swift`:

```swift
//
//  InMemoryLocalStore.swift
//  GrooTests
//
//  Fresh LocalStore instances over isolated in-memory SwiftData containers.
//  Tests never touch LocalStore.shared (App Group store).
//

import Foundation
import SwiftData
@testable import Groo

@MainActor
enum InMemoryLocalStore {
    /// A fresh LocalStore backed by an isolated in-memory container.
    static func make() throws -> LocalStore {
        let config = ModelConfiguration(schema: LocalStore.schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: LocalStore.schema, configurations: [config])
        return LocalStore(container: container)
    }
}
```

`GrooTests/Core/Storage/PendingOperationTests.swift`:

```swift
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
```

`GrooTests/Core/Sync/SyncStateTests.swift`:

```swift
//
//  SyncStateTests.swift
//  GrooTests
//
//  Status transitions driven by isOnline — documents that going offline
//  overwrites any current status, and coming online only restores .idle
//  from .offline.
//

import Foundation
import Testing
@testable import Groo

@MainActor
struct SyncStateTests {
    @Test func goingOfflineSetsOfflineStatus() {
        let state = SyncState()
        state.isOnline = false
        #expect(state.status == .offline)
    }

    @Test func comingBackOnlineRestoresIdleFromOffline() {
        let state = SyncState()
        state.isOnline = false
        state.isOnline = true
        #expect(state.status == .idle)
    }

    @Test func comingOnlineLeavesNonOfflineStatusAlone() {
        let state = SyncState()
        state.status = .error("boom")
        state.isOnline = true   // already online; didSet still runs
        #expect(state.status == .error("boom"))
    }

    @Test func goingOfflineOverwritesErrorStatus() {
        let state = SyncState()
        state.status = .error("boom")
        state.isOnline = false

        #expect(state.status == .offline)   // documents: the error is lost when offline flips
        #expect(state.errorMessage == nil)
    }

    @Test func statusConvenienceAccessors() {
        let state = SyncState()

        state.status = .syncing
        #expect(state.isSyncing)
        #expect(!state.hasError)

        state.status = .error("boom")
        #expect(state.hasError)
        #expect(state.errorMessage == "boom")
        #expect(!state.isSyncing)

        state.status = .idle
        #expect(!state.hasError)
        #expect(state.errorMessage == nil)
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `bash scripts/test.sh --unit 2>&1 | tail -20`
Expected: BUILD FAILURE — `LocalStore` has no `schema` static and no `init(container:)`.

- [ ] **Step 3: Add the seam**

In `Groo/Core/Storage/LocalStore.swift`, replace the top of the class (the `static let shared` / `let container` / `private init()` opening through the `let schema = Schema([...])` block, lines 14–28) with:

```swift
    static let shared = LocalStore()

    let container: ModelContainer

    /// Full app schema — shared by the App Group store and test containers.
    static let schema = Schema([
        LocalPadItem.self,
        LocalScratchpad.self,
        PendingOperation.self,
        CachedTokenPrice.self,
        LocalStockHolding.self,
        LocalStockTransaction.self,
        LocalAzanPreferences.self,
        PrayerLog.self,
    ])

    /// Testing seam: wrap an injected container (e.g. in-memory). The
    /// `shared` App Group store is unaffected.
    init(container: ModelContainer) {
        self.container = container
    }

    private init() {
        let schema = Self.schema
```

Everything after that line in `private init()` (the `ModelConfiguration(schema:groupContainer:)` and recovery logic) stays exactly as-is.

- [ ] **Step 4: Run to verify pass**

Run: `bash scripts/test.sh --unit 2>&1 | tail -20`
Expected: PASS — **152 tests** (141 + 11).

Verify the app still builds: `xcodebuild build -project Groo.xcodeproj -scheme Groo -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -3` → `** BUILD SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add Groo/Core/Storage/LocalStore.swift GrooTests
git commit -m "test: PendingOperation + SyncState suites; LocalStore container seam for in-memory SwiftData"
```

---

### Task 2: APIClient session seam + auth/retry/error-typing tests

**Files:**
- Modify: `Groo/Core/Network/APIClient.swift:43-58` (init)
- Test: `GrooTests/Core/Network/APIClientTests.swift`

**Interfaces:**
- Consumes: `StubURLProtocol` (+ `URLRequest.bodyData`); `APIError`.
- Produces: `APIClient.init(baseURL:sessionConfiguration:tokenProvider:forceRefresh:)` — Task 4 constructs the SyncService API on it. `tokenProvider`/`forceRefresh` are already injectable in production; only the session needs a seam.

**Note:** on 401, `withUnauthorizedRetry` calls `forceRefresh()` then re-runs the operation, which calls `tokenProvider()` *again* — the retry's Authorization header comes from `tokenProvider`, not from `forceRefresh`'s return value. The `TokenSource` helper models this: `refresh()` swaps the token that `token()` returns next.

- [ ] **Step 1: Write the failing tests**

`GrooTests/Core/Network/APIClientTests.swift`:

```swift
//
//  APIClientTests.swift
//  GrooTests
//
//  Generic Pad APIClient: auth-header injection, 401→forced-refresh→single
//  retry, typed decode errors, server-message extraction. (PassAPIClient
//  has its own suite.)
//

import Foundation
import Testing
@testable import Groo

extension NetworkStubbedSuites {
@Suite(.serialized)
struct APIClientTests {
    struct EchoBody: Codable, Equatable { let value: String }
    struct OkResponse: Decodable { let ok: Bool }

    /// Thread-safe token source: `token()` returns the current token;
    /// `refresh()` swaps in the refreshed one and counts calls.
    final class TokenSource: @unchecked Sendable {
        private let lock = NSLock()
        private var current: String
        private let refreshed: String
        private var _refreshCalls = 0

        init(current: String = "tok-1", refreshed: String = "tok-2") {
            self.current = current
            self.refreshed = refreshed
        }

        var refreshCalls: Int { lock.lock(); defer { lock.unlock() }; return _refreshCalls }
        func token() -> String { lock.lock(); defer { lock.unlock() }; return current }
        func refresh() -> String {
            lock.lock(); defer { lock.unlock() }
            _refreshCalls += 1
            current = refreshed
            return current
        }
    }

    static func makeClient(tokens: TokenSource = TokenSource()) -> APIClient {
        APIClient(
            baseURL: URL(string: "https://pad.test")!,
            sessionConfiguration: StubURLProtocol.stubbedConfiguration(),
            tokenProvider: { tokens.token() },
            forceRefresh: { tokens.refresh() }
        )
    }

    // MARK: - Header injection

    @Test func getInjectsAuthAndContentHeaders() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.enqueue(method: "GET", pathSuffix: "/v1/thing", json: #"{"ok":true}"#)

        let response: OkResponse = try await Self.makeClient().get("/v1/thing")

        #expect(response.ok)
        let request = try #require(StubURLProtocol.recordedRequests.first)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer tok-1")
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
    }

    @Test func postEncodesBodyAndDecodesResponse() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.enqueue(method: "POST", pathSuffix: "/v1/thing", json: #"{"ok":true}"#)

        let response: OkResponse = try await Self.makeClient().post("/v1/thing", body: EchoBody(value: "hi"))

        #expect(response.ok)
        let request = try #require(StubURLProtocol.recordedRequests.first)
        let body = try JSONDecoder().decode(EchoBody.self, from: try #require(request.bodyData))
        #expect(body == EchoBody(value: "hi"))
    }

    @Test func putSendsBodyWithPutMethod() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.enqueue(method: "PUT", pathSuffix: "/v1/thing/42", json: #"{"ok":true}"#)

        let response: OkResponse = try await Self.makeClient().put("/v1/thing/42", body: EchoBody(value: "updated"))

        #expect(response.ok)
        let request = try #require(StubURLProtocol.recordedRequests.first)
        #expect(request.httpMethod == "PUT")
        let body = try JSONDecoder().decode(EchoBody.self, from: try #require(request.bodyData))
        #expect(body.value == "updated")
    }

    @Test func deleteTreats2xxAsSuccessWithNoDecode() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.enqueue(method: "DELETE", pathSuffix: "/v1/thing/42", status: 204, json: "")

        try await Self.makeClient().delete("/v1/thing/42")   // must not throw

        #expect(StubURLProtocol.recordedRequests.first?.httpMethod == "DELETE")
    }

    // MARK: - 401 → forced refresh → single retry

    @Test func unauthorizedForcesRefreshAndRetriesWithNewToken() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.enqueue(method: "GET", pathSuffix: "/v1/thing", status: 401, json: "{}")
        StubURLProtocol.enqueue(method: "GET", pathSuffix: "/v1/thing", json: #"{"ok":true}"#)
        let tokens = TokenSource()

        let response: OkResponse = try await Self.makeClient(tokens: tokens).get("/v1/thing")

        #expect(response.ok)
        #expect(tokens.refreshCalls == 1)
        let requests = StubURLProtocol.recordedRequests
        #expect(requests.count == 2)
        #expect(requests[0].value(forHTTPHeaderField: "Authorization") == "Bearer tok-1")
        #expect(requests[1].value(forHTTPHeaderField: "Authorization") == "Bearer tok-2")
    }

    @Test func second401PropagatesWithoutFurtherRetries() async {
        StubURLProtocol.reset()
        StubURLProtocol.enqueue(method: "GET", pathSuffix: "/v1/thing", status: 401, json: "{}")
        // last-response-repeats: the retry also sees 401
        let tokens = TokenSource()

        await #expect {
            let _: OkResponse = try await Self.makeClient(tokens: tokens).get("/v1/thing")
        } throws: { error in
            guard case APIError.unauthorized = error else { return false }
            return true
        }

        #expect(tokens.refreshCalls == 1)
        #expect(StubURLProtocol.recordedRequests.count == 2)
    }

    @Test func refreshFailureAbortsBeforeRetry() async {
        StubURLProtocol.reset()
        StubURLProtocol.enqueue(method: "GET", pathSuffix: "/v1/thing", status: 401, json: "{}")
        let client = APIClient(
            baseURL: URL(string: "https://pad.test")!,
            sessionConfiguration: StubURLProtocol.stubbedConfiguration(),
            tokenProvider: { "tok-1" },
            forceRefresh: { throw URLError(.userCancelledAuthentication) }
        )

        await #expect(throws: URLError.self) {
            let _: OkResponse = try await client.get("/v1/thing")
        }
        #expect(StubURLProtocol.recordedRequests.count == 1)
    }

    @Test func missingTokenFailsWithoutNetworkTraffic() async {
        StubURLProtocol.reset()
        // Default closures both throw .unauthorized (the production default)
        let client = APIClient(
            baseURL: URL(string: "https://pad.test")!,
            sessionConfiguration: StubURLProtocol.stubbedConfiguration()
        )

        await #expect {
            let _: OkResponse = try await client.get("/v1/thing")
        } throws: { error in
            guard case APIError.unauthorized = error else { return false }
            return true
        }
        #expect(StubURLProtocol.recordedRequests.isEmpty)
    }

    // MARK: - Error typing

    @Test func decodeFailureSurfacesAsTypedError() async {
        StubURLProtocol.reset()
        StubURLProtocol.enqueue(method: "GET", pathSuffix: "/v1/thing", json: "not json")

        await #expect {
            let _: OkResponse = try await Self.makeClient().get("/v1/thing")
        } throws: { error in
            guard case APIError.decodingFailed = error else { return false }
            return true
        }
    }

    @Test func httpErrorExtractsServerMessage() async {
        StubURLProtocol.reset()
        StubURLProtocol.enqueue(method: "GET", pathSuffix: "/v1/thing", status: 400, json: #"{"error":"nope"}"#)

        await #expect {
            let _: OkResponse = try await Self.makeClient().get("/v1/thing")
        } throws: { error in
            guard case APIError.httpError(let status, let message) = error else { return false }
            return status == 400 && message == "nope"
        }
    }

    @Test func httpErrorWithoutJsonBodyHasNilMessage() async {
        StubURLProtocol.reset()
        StubURLProtocol.enqueue(method: "GET", pathSuffix: "/v1/thing", status: 503, json: "busy")

        await #expect {
            let _: OkResponse = try await Self.makeClient().get("/v1/thing")
        } throws: { error in
            guard case APIError.httpError(let status, let message) = error else { return false }
            return status == 503 && message == nil
        }
    }

    @Test func transportErrorPropagatesAsURLError() async {
        StubURLProtocol.reset()
        StubURLProtocol.enqueue(method: "GET", pathSuffix: "/v1/thing", error: URLError(.timedOut))

        await #expect {
            let _: OkResponse = try await Self.makeClient().get("/v1/thing")
        } throws: { error in
            // Documents actual behavior: transport errors are NOT wrapped in APIError
            (error as? URLError)?.code == .timedOut
        }
    }
}
}
```

- [ ] **Step 2: Run to verify failure**

Run: `bash scripts/test.sh --unit 2>&1 | tail -20`
Expected: BUILD FAILURE — `APIClient` has no `sessionConfiguration` init parameter.

- [ ] **Step 3: Add the seam**

In `Groo/Core/Network/APIClient.swift`, replace the init (lines 43–58, keeping the doc comment above it) with:

```swift
    init(
        baseURL: URL,
        sessionConfiguration: URLSessionConfiguration = .default,
        tokenProvider: @escaping @Sendable () async throws -> String = { throw APIError.unauthorized },
        forceRefresh: @escaping @Sendable () async throws -> String = { throw APIError.unauthorized }
    ) {
        self.baseURL = baseURL
        self.tokenProvider = tokenProvider
        self.forceRefresh = forceRefresh
        self.decoder = JSONDecoder()
        self.encoder = JSONEncoder()

        let config = sessionConfiguration
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: config)
    }
```

- [ ] **Step 4: Run to verify pass**

Run: `bash scripts/test.sh --unit 2>&1 | tail -20`
Expected: PASS — **164 tests** (152 + 12).

Verify the app still builds: `xcodebuild build -project Groo.xcodeproj -scheme Groo -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -3` → `** BUILD SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add Groo/Core/Network/APIClient.swift GrooTests
git commit -m "test: APIClient suite (auth header, 401 refresh-retry, typed errors); inject session configuration"
```

---

### Task 3: Phase 2 fast-follows — APICache injected clock + WalletManager EIP-155 chain-id pin

**Files:**
- Modify: `Groo/Core/Network/APICache.swift:28-42` (Entry.isValid + init)
- Modify: `GrooTests/Core/Network/APICacheTests.swift` (add clock + expiry test)
- Modify: `GrooTests/Features/Crypto/WalletManagerTests.swift` (add RLP helper + chain-id test)

**Interfaces:**
- Consumes: existing `APICacheTests` suite/`makeCache` conventions; existing `WalletManagerTests.makeWalletEnv`/`tearDown`/vector constants; `BigUInt`.
- Produces: `APICache.init(sessionConfiguration:now:)` with `now: @Sendable () -> Date = Date.init`.

- [ ] **Step 1: Write the failing APICache test**

In `GrooTests/Core/Network/APICacheTests.swift`, add inside the `APICacheTests` struct (after `makeCache()`):

```swift
    /// Advanceable wall clock for TTL tests (no sleeps).
    final class MutableClock: @unchecked Sendable {
        private let lock = NSLock()
        private var _now = Date(timeIntervalSince1970: 1_700_000_000)
        var now: Date { lock.lock(); defer { lock.unlock() }; return _now }
        func advance(by seconds: TimeInterval) {
            lock.lock(); defer { lock.unlock() }
            _now = _now.addingTimeInterval(seconds)
        }
    }

    @Test func entryExpiresWhenTtlElapsesOnInjectedClock() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.enqueue(method: "GET", pathSuffix: "/prices/eth", json: #"{"v":1}"#)
        StubURLProtocol.enqueue(method: "GET", pathSuffix: "/prices/eth", json: #"{"v":2}"#)
        let clock = MutableClock()
        let cache = APICache(
            sessionConfiguration: StubURLProtocol.stubbedConfiguration(),
            now: { clock.now }
        )

        let first = try await cache.fetch(Self.url, ttl: 300)
        clock.advance(by: 299)
        let stillCached = try await cache.fetch(Self.url, ttl: 300)   // 299s < 300s TTL
        #expect(stillCached == first)
        #expect(StubURLProtocol.recordedRequests.count == 1)

        clock.advance(by: 2)   // 301s total — past the TTL
        let refreshed = try await cache.fetch(Self.url, ttl: 300)
        #expect(refreshed == Data(#"{"v":2}"#.utf8))
        #expect(StubURLProtocol.recordedRequests.count == 2)
    }
```

Run: `bash scripts/test.sh --unit 2>&1 | tail -20`
Expected: BUILD FAILURE — `APICache` init has no `now` parameter.

- [ ] **Step 2: Add the APICache clock seam**

In `Groo/Core/Network/APICache.swift`, replace the `Entry` struct and init (lines 28–42) with:

```swift
    struct Entry {
        let data: Data
        let timestamp: Date

        func isValid(ttl: TimeInterval, now: Date) -> Bool {
            now.timeIntervalSince(timestamp) < ttl
        }
    }

    private let now: @Sendable () -> Date

    init(
        sessionConfiguration: URLSessionConfiguration = .default,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.now = now
        let config = sessionConfiguration
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        session = URLSession(configuration: config)
    }
```

Then in `fetch(_:ttl:forceRefresh:)`, update the two call sites:

Cache check (step 1):

```swift
        if !forceRefresh, let entry = cache[key], entry.isValid(ttl: ttl, now: now()) {
            return entry.data
        }
```

Store result (step 4):

```swift
            cache[key] = Entry(data: data, timestamp: now())
```

- [ ] **Step 3: Add the WalletManager chain-id test**

In `GrooTests/Features/Crypto/WalletManagerTests.swift`, add inside the `WalletManagerTests` struct (in the `// MARK: - Signing` section, after `signTransactionProducesRlpEncodedBytes`):

```swift
    enum RLPError: Error { case malformed }

    /// Minimal RLP decoder for a top-level list of byte-string items — just
    /// enough to pull v/r/s out of a signed legacy transaction. Nested lists
    /// are rejected (a legacy tx has none).
    static func rlpListItems(_ data: Data) throws -> [Data] {
        let bytes = [UInt8](data)
        guard let first = bytes.first else { throw RLPError.malformed }

        var index: Int
        let end: Int
        if (0xc0...0xf7).contains(first) {
            index = 1
            end = index + Int(first - 0xc0)
        } else if first >= 0xf8 {
            let lengthOfLength = Int(first - 0xf7)
            guard bytes.count > lengthOfLength else { throw RLPError.malformed }
            let length = bytes[1...lengthOfLength].reduce(0) { $0 << 8 | Int($1) }
            index = 1 + lengthOfLength
            end = index + length
        } else {
            throw RLPError.malformed
        }
        guard end <= bytes.count else { throw RLPError.malformed }

        var items: [Data] = []
        while index < end {
            let marker = bytes[index]
            switch marker {
            case 0x00...0x7f:
                items.append(Data([marker]))
                index += 1
            case 0x80...0xb7:
                let length = Int(marker - 0x80)
                guard index + 1 + length <= end else { throw RLPError.malformed }
                items.append(Data(bytes[(index + 1)..<(index + 1 + length)]))
                index += 1 + length
            case 0xb8...0xbf:
                let lengthOfLength = Int(marker - 0xb7)
                guard index + 1 + lengthOfLength <= end else { throw RLPError.malformed }
                let length = bytes[(index + 1)...(index + lengthOfLength)].reduce(0) { $0 << 8 | Int($1) }
                guard index + 1 + lengthOfLength + length <= end else { throw RLPError.malformed }
                items.append(Data(bytes[(index + 1 + lengthOfLength)..<(index + 1 + lengthOfLength + length)]))
                index += 1 + lengthOfLength + length
            default:
                throw RLPError.malformed   // nested list — not valid in a legacy tx
            }
        }
        return items
    }

    /// A wallet signing for the wrong chain is a real failure mode: the
    /// signature would be valid on some other network and replayable there.
    /// EIP-155: v = chainId * 2 + 35 (+ recovery bit) → 37/38 for mainnet.
    @Test func signTransactionEmbedsChainId1InV() async throws {
        let walletEnv = try await Self.makeWalletEnv()
        defer { Self.tearDown(walletEnv) }
        _ = try await walletEnv.manager.importWallet(privateKey: Self.vectorPrivateKey)

        let signed = try walletEnv.manager.signTransaction(
            to: "0x3535353535353535353535353535353535353535",
            value: BigUInt(1_000_000_000_000_000_000),
            nonce: BigUInt(9),
            gasPrice: BigUInt(20_000_000_000),
            gasLimit: BigUInt(21_000),
            fromAddress: Self.vectorPrivateKeyAddress
        )

        // Legacy signed tx RLP: [nonce, gasPrice, gasLimit, to, value, data, v, r, s]
        let fields = try Self.rlpListItems(signed)
        #expect(fields.count == 9)
        let v = fields[6].reduce(BigUInt(0)) { $0 << 8 | BigUInt($1) }
        try #require(v >= 35, "expected an EIP-155 v, got \(v) — pre-EIP-155 signature has no replay protection")
        let chainId = (v - 35) / 2
        #expect(chainId == 1, "transaction signed for chainId \(chainId), not Ethereum mainnet (1) — wrong-chain signature")
    }
```

- [ ] **Step 4: Run to verify pass**

Run: `bash scripts/test.sh --unit 2>&1 | tail -20`
Expected: PASS — **166 tests** (164 + 2). If the chain-id assertion fails, report BLOCKED with the actual `v`/chainId — do NOT change the expected value; the default `chainId: 1` in `signTransaction` would be broken.

Verify the app still builds: `xcodebuild build -project Groo.xcodeproj -scheme Groo -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -3` → `** BUILD SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add Groo/Core/Network/APICache.swift GrooTests
git commit -m "test: Phase 2 fast-follows - APICache TTL expiry via injected clock; pin EIP-155 chainId in signed txs"
```

---

### Task 4: SyncService integration suite (stubbed API + in-memory store)

**Files:**
- Modify: `Groo/Core/Sync/SyncService.swift:27-35` (init)
- Test: `GrooTests/Core/Sync/SyncServiceTests.swift`

**Interfaces:**
- Consumes: `InMemoryLocalStore.make()` (Task 1), `APIClient(baseURL:sessionConfiguration:tokenProvider:)` (Task 2), `StubURLProtocol`, `PadListItem`/`PadEncryptedPayload`/`PadUserState` JSON shape, `SyncStatus`.
- Produces: `SyncService.init(api:store:monitorsNetwork:)`.

**Notes:**
- The seam disables `NWPathMonitor` in tests — otherwise the simulator's real path status fires `sync()` asynchronously mid-test. Tests drive `service.state.isOnline` and call `sync()` directly.
- `SyncService` and `LocalStore` are `@MainActor`; the suite is `@MainActor` and nests under `NetworkStubbedSuites`.
- Two operations queued in quick succession get near-identical `createdAt` values; the flush-order test pins distinct timestamps on the stored operations before syncing so the FIFO assertion cannot race on equal `Date`s.
- The error-status assertions couple to the production message `"Some changes couldn't be synced"` deliberately (it's user-visible).

- [ ] **Step 1: Write the failing tests**

`GrooTests/Core/Sync/SyncServiceTests.swift`:

```swift
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
```

- [ ] **Step 2: Run to verify failure**

Run: `bash scripts/test.sh --unit 2>&1 | tail -20`
Expected: BUILD FAILURE — `SyncService` has no `monitorsNetwork` init parameter.

- [ ] **Step 3: Add the seam**

In `Groo/Core/Sync/SyncService.swift`, replace the init (lines 27–35) with:

```swift
    /// - Parameter monitorsNetwork: the production default starts NWPathMonitor
    ///   (which flips `state.isOnline` and triggers sync on reconnect). Tests
    ///   pass `false` and drive `state.isOnline` + `sync()` directly.
    init(
        api: APIClient,
        store: LocalStore = .shared,
        monitorsNetwork: Bool = true
    ) {
        self.api = api
        self.store = store

        if monitorsNetwork {
            setupNetworkMonitoring()
        }
    }
```

- [ ] **Step 4: Run to verify pass**

Run: `bash scripts/test.sh --unit 2>&1 | tail -20`
Expected: PASS — **176 tests** (166 + 10).

Verify the app still builds: `xcodebuild build -project Groo.xcodeproj -scheme Groo -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -3` → `** BUILD SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add Groo/Core/Sync/SyncService.swift GrooTests
git commit -m "test: SyncService integration suite (offline queue, flush order, partial failure, 404 dedupe); monitorsNetwork seam"
```

---

### Task 5: WebSocketService socket/timer/token seams + state-machine suite

**Files:**
- Modify: `Groo/Core/Sync/WebSocketService.swift` (full-file replacement below)
- Test: `GrooTests/Support/WebSocketFakes.swift`
- Test: `GrooTests/Core/Sync/WebSocketServiceTests.swift`

**Interfaces:**
- Consumes: `AuthService.accessToken()`/`forceRefresh()` (unchanged), `Config.padAPIBaseURL`, `Log.sync`.
- Produces: `WebSocketTokenProviding` (AuthService conforms), `WebSocketConnection` protocol + `URLSessionWebSocketConnection` production wrapper, `WebSocketTimerFactory`, `WebSocketService.init(authService:makeConnection:makeTimer:)`.
- Call-site compatibility: `WebSocketService(authService: authService)` in `ScratchpadView.swift:640` compiles unchanged (`AuthService` conforms to the new protocol; the other params default).

**Behavior-preservation checklist for the refactor (verify each against the pre-change file):**
- 401-on-handshake → exactly one `forceRefresh()` + one retry; second 401 or failed refresh → `onDisconnected`, no more retries.
- Non-401 errored completions are ignored by the handshake handler (receive's failure branch / `didCloseWith` drive normal reconnect).
- Reconnect backoff: `min(2^attempt, 30)` seconds, max 5 attempts; attempts reset on successful open and on fresh `connect()`.
- Ping every 30s; server `ping` answered with `pong`; malformed/undecodable frames logged and dropped without disconnecting.
- `disconnect()` cancels with `.goingAway`, stops both timers, resets attempts.
- The class no longer subclasses `NSObject` (that existed only for the URLSession delegate, which moved into the wrapper).

- [ ] **Step 1: Write the failing fakes + tests**

`GrooTests/Support/WebSocketFakes.swift`:

```swift
//
//  WebSocketFakes.swift
//  GrooTests
//
//  Scriptable doubles for the WebSocketService seams: token provider,
//  connection, connection factory, and timer recorder. Timers are recorded
//  and fired manually — never waited on.
//

import Foundation
@testable import Groo

@MainActor
final class FakeTokenProvider: WebSocketTokenProviding {
    var currentToken = "tok-1"
    var refreshedToken = "tok-2"
    var accessTokenError: (any Error)?
    var forceRefreshError: (any Error)?
    private(set) var accessTokenCalls = 0
    private(set) var forceRefreshCalls = 0

    func accessToken() async throws -> String {
        accessTokenCalls += 1
        if let accessTokenError { throw accessTokenError }
        return currentToken
    }

    func forceRefresh() async throws -> String {
        forceRefreshCalls += 1
        if let forceRefreshError { throw forceRefreshError }
        currentToken = refreshedToken
        return currentToken
    }
}

@MainActor
final class FakeWebSocketConnection: WebSocketConnection {
    var onOpen: (() -> Void)?
    var onClose: ((URLSessionWebSocketTask.CloseCode, Data?) -> Void)?
    var onHandshakeFailure: ((Int?, any Error) -> Void)?

    private(set) var resumeCalls = 0
    private(set) var cancelledWith: URLSessionWebSocketTask.CloseCode?
    private(set) var sentTexts: [String] = []

    private var pendingReceives: [(Result<URLSessionWebSocketTask.Message, any Error>) -> Void] = []
    private var queuedResults: [Result<URLSessionWebSocketTask.Message, any Error>] = []

    func resume() { resumeCalls += 1 }

    func cancel(with closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        cancelledWith = closeCode
    }

    func send(_ text: String, completion: @escaping @Sendable ((any Error)?) -> Void) {
        sentTexts.append(text)
        completion(nil)
    }

    func receive(completion: @escaping @Sendable (Result<URLSessionWebSocketTask.Message, any Error>) -> Void) {
        if queuedResults.isEmpty {
            pendingReceives.append(completion)
        } else {
            completion(queuedResults.removeFirst())
        }
    }

    // MARK: Test drivers

    /// Simulates the handshake completing.
    func open() { onOpen?() }

    /// Simulates the server closing the socket.
    func close(code: URLSessionWebSocketTask.CloseCode = .abnormalClosure) { onClose?(code, nil) }

    /// Simulates a failed upgrade (e.g. 401 before the socket opened).
    func failHandshake(statusCode: Int?, error: any Error = URLError(.userAuthenticationRequired)) {
        onHandshakeFailure?(statusCode, error)
    }

    /// Delivers a text frame to the service's receive loop. Frames delivered
    /// before the loop re-arms are buffered, preserving FIFO order.
    func deliver(_ text: String) { dispatch(.success(.string(text))) }

    /// Delivers a binary frame.
    func deliver(data: Data) { dispatch(.success(.data(data))) }

    /// Fails the receive loop (transport drop mid-stream).
    func failReceive(_ error: any Error) { dispatch(.failure(error)) }

    private func dispatch(_ result: Result<URLSessionWebSocketTask.Message, any Error>) {
        if pendingReceives.isEmpty {
            queuedResults.append(result)
        } else {
            pendingReceives.removeFirst()(result)
        }
    }
}

@MainActor
final class FakeConnectionFactory {
    private(set) var connections: [FakeWebSocketConnection] = []
    private(set) var requests: [URLRequest] = []
    var onCreate: ((FakeWebSocketConnection) -> Void)?

    func make(_ request: URLRequest) -> any WebSocketConnection {
        let connection = FakeWebSocketConnection()
        connections.append(connection)
        requests.append(request)
        onCreate?(connection)
        return connection
    }

    /// Runs `action`, then suspends until the factory creates the next
    /// connection (reconnects happen on a later main-actor turn).
    func connectionCreated(after action: @MainActor () -> Void) async -> FakeWebSocketConnection {
        await withCheckedContinuation { (continuation: CheckedContinuation<FakeWebSocketConnection, Never>) in
            onCreate = { [weak self] connection in
                self?.onCreate = nil
                continuation.resume(returning: connection)
            }
            action()
        }
    }
}

@MainActor
final class TimerRecorder {
    struct Entry {
        let interval: TimeInterval
        let repeats: Bool
        let block: @MainActor () -> Void
    }

    private(set) var entries: [Entry] = []

    /// Matches WebSocketTimerFactory. Returns an inert Timer (never added to
    /// a run loop): `invalidate()` is safe, and nothing ever fires on its own.
    func make(interval: TimeInterval, repeats: Bool, block: @escaping @MainActor () -> Void) -> Timer {
        entries.append(Entry(interval: interval, repeats: repeats, block: block))
        return Timer(timeInterval: interval, repeats: repeats) { _ in }
    }

    /// One-shot timers = the reconnect backoff schedule.
    var reconnectDelays: [TimeInterval] { entries.filter { !$0.repeats }.map(\.interval) }

    /// Repeating timers = the ping schedule.
    var pingIntervals: [TimeInterval] { entries.filter { $0.repeats }.map(\.interval) }

    func fireLastReconnect() {
        entries.last(where: { !$0.repeats })?.block()
    }

    func fireLastPing() {
        entries.last(where: { $0.repeats })?.block()
    }
}
```

`GrooTests/Core/Sync/WebSocketServiceTests.swift`:

```swift
//
//  WebSocketServiceTests.swift
//  GrooTests
//
//  Connect/drop/reconnect state machine over a scripted fake socket:
//  backoff schedule, give-up cap, 401 refresh-retry-once, ping/pong,
//  message dispatch. No real sockets, no waits — timers fire manually.
//

import Foundation
import Testing
@testable import Groo

@MainActor
struct WebSocketServiceTests {
    struct Env {
        let service: WebSocketService
        let auth: FakeTokenProvider
        let factory: FakeConnectionFactory
        let timers: TimerRecorder
    }

    static func makeEnv() -> Env {
        let auth = FakeTokenProvider()
        let factory = FakeConnectionFactory()
        let timers = TimerRecorder()
        let service = WebSocketService(
            authService: auth,
            makeConnection: { factory.make($0) },
            makeTimer: { timers.make(interval: $0, repeats: $1, block: $2) }
        )
        return Env(service: service, auth: auth, factory: factory, timers: timers)
    }

    /// connect() + complete the handshake on the first fake connection.
    static func makeConnectedEnv() async -> (Env, FakeWebSocketConnection) {
        let env = makeEnv()
        await env.service.connect()
        let connection = env.factory.connections[0]
        connection.open()
        return (env, connection)
    }

    // MARK: - Connect

    @Test func connectAttachesBearerTokenAndOpensToConnected() async {
        let env = Self.makeEnv()

        await env.service.connect()

        #expect(env.factory.requests.count == 1)
        #expect(env.factory.requests[0].value(forHTTPHeaderField: "Authorization") == "Bearer tok-1")
        #expect(env.factory.requests[0].url?.path == "/v1/ws")
        #expect(env.factory.connections[0].resumeCalls == 1)
        #expect(!env.service.isConnected)   // handshake hasn't completed yet

        var connectedFired = false
        env.service.onConnected = { connectedFired = true }
        env.factory.connections[0].open()

        #expect(env.service.isConnected)
        #expect(connectedFired)
    }

    @Test func tokenFailureAbortsConnect() async {
        let env = Self.makeEnv()
        env.auth.accessTokenError = URLError(.userAuthenticationRequired)

        await env.service.connect()

        #expect(env.factory.connections.isEmpty)
        #expect(!env.service.isConnected)
    }

    // MARK: - Message dispatch

    @Test func scratchpadEventsInvokeCallbacksWithId() async {
        let (env, connection) = await Self.makeConnectedEnv()

        let updated = await withCheckedContinuation { (continuation: CheckedContinuation<String, Never>) in
            env.service.onScratchpadUpdated = { continuation.resume(returning: $0) }
            connection.deliver(#"{"type":"scratchpad_updated","scratchpadId":"sp-1","timestamp":1}"#)
        }
        #expect(updated == "sp-1")

        let created = await withCheckedContinuation { (continuation: CheckedContinuation<String, Never>) in
            env.service.onScratchpadCreated = { continuation.resume(returning: $0) }
            connection.deliver(#"{"type":"scratchpad_created","scratchpadId":"sp-2"}"#)
        }
        #expect(created == "sp-2")

        let deleted = await withCheckedContinuation { (continuation: CheckedContinuation<String, Never>) in
            env.service.onScratchpadDeleted = { continuation.resume(returning: $0) }
            connection.deliver(#"{"type":"scratchpad_deleted","scratchpadId":"sp-3"}"#)
        }
        #expect(deleted == "sp-3")
    }

    @Test func malformedAndBinaryFramesAreHandledSafely() async {
        let (env, connection) = await Self.makeConnectedEnv()

        var unexpectedCallbacks = 0
        env.service.onScratchpadUpdated = { _ in unexpectedCallbacks += 1 }
        env.service.onScratchpadDeleted = { _ in unexpectedCallbacks += 1 }

        connection.deliver("not json at all")
        connection.deliver(data: Data([0xFF, 0xFE]))   // invalid UTF-8

        // Binary frames containing valid JSON are parsed (the .data path).
        // Frames are FIFO: once this callback fires, the garbage frames above
        // have already been (safely) dropped.
        let created = await withCheckedContinuation { (continuation: CheckedContinuation<String, Never>) in
            env.service.onScratchpadCreated = { continuation.resume(returning: $0) }
            connection.deliver(data: Data(#"{"type":"scratchpad_created","scratchpadId":"sp-2"}"#.utf8))
        }

        #expect(created == "sp-2")
        #expect(unexpectedCallbacks == 0)
        #expect(env.service.isConnected)   // garbage frames don't drop the connection
    }

    // MARK: - Ping/pong

    @Test func serverPingIsAnsweredWithPong() async throws {
        let (env, connection) = await Self.makeConnectedEnv()

        connection.deliver(#"{"type":"ping","timestamp":1}"#)
        // Frames are processed FIFO on the main actor: once the follow-up
        // message's callback fires, the pong for the ping was already sent.
        _ = await withCheckedContinuation { (continuation: CheckedContinuation<String, Never>) in
            env.service.onScratchpadUpdated = { continuation.resume(returning: $0) }
            connection.deliver(#"{"type":"scratchpad_updated","scratchpadId":"sp-1"}"#)
        }

        let sent = try #require(connection.sentTexts.first)
        let message = try JSONDecoder().decode(WebSocketMessage.self, from: Data(sent.utf8))
        #expect(message.type == .pong)
    }

    @Test func pingTimerSendsPing() async throws {
        let (env, connection) = await Self.makeConnectedEnv()
        #expect(env.timers.pingIntervals == [30])

        env.timers.fireLastPing()

        let sent = try #require(connection.sentTexts.last)
        let message = try JSONDecoder().decode(WebSocketMessage.self, from: Data(sent.utf8))
        #expect(message.type == .ping)
    }

    // MARK: - Drop → reconnect

    @Test func dropSchedulesReconnectAndTimerFireReconnects() async {
        let (env, connection) = await Self.makeConnectedEnv()

        var disconnected = false
        env.service.onDisconnected = { _ in disconnected = true }
        connection.close()

        #expect(disconnected)
        #expect(!env.service.isConnected)
        #expect(env.timers.reconnectDelays == [2.0])   // 2^1 for attempt 1

        let second = await env.factory.connectionCreated {
            env.timers.fireLastReconnect()
        }
        #expect(second.resumeCalls == 1)

        second.open()
        #expect(env.service.isConnected)
    }

    @Test func receiveFailureAlsoTriggersReconnect() async {
        let (env, connection) = await Self.makeConnectedEnv()

        let error = await withCheckedContinuation { (continuation: CheckedContinuation<(any Error)?, Never>) in
            env.service.onDisconnected = { continuation.resume(returning: $0) }
            connection.failReceive(URLError(.networkConnectionLost))
        }

        #expect(error != nil)
        #expect(!env.service.isConnected)
        #expect(env.timers.reconnectDelays == [2.0])
    }

    @Test func backoffDoublesAndGivesUpAfterFiveAttempts() async {
        let (env, connection) = await Self.makeConnectedEnv()

        var latest = connection
        latest.close()
        for _ in 0..<5 {
            latest = await env.factory.connectionCreated {
                env.timers.fireLastReconnect()
            }
            latest.close()   // every attempt fails before opening
        }

        #expect(env.timers.reconnectDelays == [2.0, 4.0, 8.0, 16.0, 30.0])   // capped at 30s
        #expect(env.factory.connections.count == 6)   // initial + 5 attempts
        // After the 5th failed attempt the service gave up — no 6th timer
        #expect(env.timers.reconnectDelays.count == 5)
    }

    @Test func successfulReconnectResetsBackoff() async {
        let (env, connection) = await Self.makeConnectedEnv()

        connection.close()
        #expect(env.timers.reconnectDelays == [2.0])

        let second = await env.factory.connectionCreated {
            env.timers.fireLastReconnect()
        }
        second.open()   // resets reconnectAttempts

        second.close()
        #expect(env.timers.reconnectDelays == [2.0, 2.0])   // back to attempt 1
    }

    // MARK: - 401 handshake → refresh-retry-once

    @Test func handshake401ForcesOneRefreshAndRetries() async {
        let env = Self.makeEnv()
        await env.service.connect()

        let second = await env.factory.connectionCreated {
            env.factory.connections[0].failHandshake(statusCode: 401)
        }

        #expect(env.auth.forceRefreshCalls == 1)
        #expect(env.factory.requests[1].value(forHTTPHeaderField: "Authorization") == "Bearer tok-2")

        second.open()
        #expect(env.service.isConnected)
    }

    @Test func second401GivesUpWithDisconnect() async {
        let env = Self.makeEnv()
        await env.service.connect()

        let second = await env.factory.connectionCreated {
            env.factory.connections[0].failHandshake(statusCode: 401)
        }

        let error = await withCheckedContinuation { (continuation: CheckedContinuation<(any Error)?, Never>) in
            env.service.onDisconnected = { continuation.resume(returning: $0) }
            second.failHandshake(statusCode: 401)
        }

        #expect(error != nil)
        #expect(env.auth.forceRefreshCalls == 1)          // refreshed exactly once
        #expect(env.factory.connections.count == 2)       // no third attempt
    }

    @Test func refreshFailureSurfacesAsDisconnect() async {
        let env = Self.makeEnv()
        env.auth.forceRefreshError = URLError(.badServerResponse)
        await env.service.connect()

        let error = await withCheckedContinuation { (continuation: CheckedContinuation<(any Error)?, Never>) in
            env.service.onDisconnected = { continuation.resume(returning: $0) }
            env.factory.connections[0].failHandshake(statusCode: 401)
        }

        #expect(error != nil)
        #expect(env.auth.forceRefreshCalls == 1)
        #expect(env.factory.connections.count == 1)   // no retry connection
    }

    @Test func non401HandshakeFailureDoesNotTriggerRefresh() async {
        let env = Self.makeEnv()
        await env.service.connect()

        env.factory.connections[0].failHandshake(statusCode: 503, error: URLError(.badServerResponse))

        // Non-401 completions are ignored by the handshake handler (the
        // receive-failure/close paths own normal reconnects) — synchronous
        // guard, so nothing is pending after this returns.
        #expect(env.auth.forceRefreshCalls == 0)
        #expect(env.factory.connections.count == 1)
    }

    // MARK: - Disconnect

    @Test func disconnectCancelsGoingAwayAndAllowsFreshConnect() async {
        let (env, connection) = await Self.makeConnectedEnv()

        env.service.disconnect()

        #expect(connection.cancelledWith == .goingAway)
        #expect(!env.service.isConnected)
        #expect(env.timers.reconnectDelays.isEmpty)   // clean disconnect never reconnects

        await env.service.connect()
        #expect(env.factory.connections.count == 2)
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `bash scripts/test.sh --unit 2>&1 | tail -20`
Expected: BUILD FAILURE — `WebSocketTokenProviding`/`WebSocketConnection` not found; `WebSocketService` has no `makeConnection`/`makeTimer` parameters.

- [ ] **Step 3: Replace the production file**

Replace the entire contents of `Groo/Core/Sync/WebSocketService.swift` with:

```swift
//
//  WebSocketService.swift
//  Groo
//
//  WebSocket connection for real-time scratchpad sync.
//  Handles connection, reconnection, and incoming updates.
//  The socket and timers sit behind seams (WebSocketConnection,
//  WebSocketTimerFactory) so tests can drive the state machine with a
//  scripted fake and fire backoff timers manually.
//

import Foundation
import os

// MARK: - WebSocket Message Types

enum WebSocketMessageType: String, Codable {
    case scratchpadUpdated = "scratchpad_updated"
    case scratchpadCreated = "scratchpad_created"
    case scratchpadDeleted = "scratchpad_deleted"
    case ping = "ping"
    case pong = "pong"
}

struct WebSocketMessage: Codable {
    let type: WebSocketMessageType
    let scratchpadId: String?
    let timestamp: Int?
}

// MARK: - Seams

/// The slice of AuthService the WebSocket layer needs (mirrors the
/// KeychainServicing extraction). Tests inject a fake token provider.
@MainActor
protocol WebSocketTokenProviding: AnyObject {
    func accessToken() async throws -> String
    func forceRefresh() async throws -> String
}

extension AuthService: WebSocketTokenProviding {}

/// One WebSocket connection attempt. Production wraps a
/// URLSession + URLSessionWebSocketTask pair; tests use a scripted fake.
@MainActor
protocol WebSocketConnection: AnyObject {
    /// Fired when the WebSocket handshake completes.
    var onOpen: (() -> Void)? { get set }
    /// Fired when the socket closes after having opened.
    var onClose: ((URLSessionWebSocketTask.CloseCode, Data?) -> Void)? { get set }
    /// Fired when the connection attempt errors out before any
    /// WebSocket-specific callback (e.g. the server rejected the upgrade).
    /// `statusCode` is the handshake's HTTP status when known.
    var onHandshakeFailure: ((_ statusCode: Int?, _ error: any Error) -> Void)? { get set }

    func resume()
    func cancel(with closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?)
    func send(_ text: String, completion: @escaping @Sendable ((any Error)?) -> Void)
    func receive(completion: @escaping @Sendable (Result<URLSessionWebSocketTask.Message, any Error>) -> Void)
}

/// Creates a scheduled timer. Injected so tests can record (interval,
/// repeats, block) and fire manually instead of waiting (no-sleeps rule).
typealias WebSocketTimerFactory = @MainActor (
    _ interval: TimeInterval,
    _ repeats: Bool,
    _ block: @escaping @MainActor () -> Void
) -> Timer

/// Production connection: owns a URLSession + URLSessionWebSocketTask pair
/// and forwards the delegate callbacks that used to live on WebSocketService.
@MainActor
final class URLSessionWebSocketConnection: NSObject, WebSocketConnection {
    var onOpen: (() -> Void)?
    var onClose: ((URLSessionWebSocketTask.CloseCode, Data?) -> Void)?
    var onHandshakeFailure: ((Int?, any Error) -> Void)?

    private var session: URLSession?
    private var task: URLSessionWebSocketTask?
    private let request: URLRequest

    init(request: URLRequest) {
        self.request = request
        super.init()
    }

    func resume() {
        let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        self.session = session
        let task = session.webSocketTask(with: request)
        self.task = task
        task.resume()
    }

    func cancel(with closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        task?.cancel(with: closeCode, reason: reason)
        task = nil
        session = nil
    }

    func send(_ text: String, completion: @escaping @Sendable ((any Error)?) -> Void) {
        task?.send(.string(text), completionHandler: completion)
    }

    func receive(completion: @escaping @Sendable (Result<URLSessionWebSocketTask.Message, any Error>) -> Void) {
        task?.receive(completionHandler: completion)
    }
}

extension URLSessionWebSocketConnection: URLSessionWebSocketDelegate {
    nonisolated func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        Task { @MainActor in
            self.onOpen?()
        }
    }

    nonisolated func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        Task { @MainActor in
            self.onClose?(closeCode, reason)
        }
    }

    /// A failed handshake (before any WebSocket-specific delegate callback
    /// fires) surfaces here — e.g. the server rejected the upgrade with 401.
    /// Successful completions (error == nil) are not forwarded; the close
    /// path and receive's failure branch drive the normal disconnect flow.
    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }
        let statusCode = (task.response as? HTTPURLResponse)?.statusCode
        Task { @MainActor in
            self.onHandshakeFailure?(statusCode, error)
        }
    }
}

// MARK: - WebSocket Service

@MainActor
@Observable
class WebSocketService {
    // Callbacks for events
    var onScratchpadUpdated: ((String) -> Void)?
    var onScratchpadCreated: ((String) -> Void)?
    var onScratchpadDeleted: ((String) -> Void)?
    var onConnected: (() -> Void)?
    var onDisconnected: ((Error?) -> Void)?

    private var connection: (any WebSocketConnection)?
    private let authService: any WebSocketTokenProviding
    private let makeConnection: @MainActor (URLRequest) -> any WebSocketConnection
    private let makeTimer: WebSocketTimerFactory

    private(set) var isConnected = false
    private var reconnectAttempts = 0
    private let maxReconnectAttempts = 5
    private var reconnectTimer: Timer?
    private var pingTimer: Timer?

    /// Guards against retrying the forced-refresh more than once per connection
    /// attempt: reset when a fresh `connect()` starts or the socket opens.
    private var didRetryAfterUnauthorized = false

    // Connection URL
    private var webSocketURL: URL? {
        // Convert HTTP URL to WebSocket URL
        var components = URLComponents(url: Config.padAPIBaseURL, resolvingAgainstBaseURL: false)
        components?.scheme = Config.padAPIBaseURL.scheme == "https" ? "wss" : "ws"
        components?.path = "/v1/ws"
        return components?.url
    }

    init(
        authService: any WebSocketTokenProviding,
        makeConnection: @escaping @MainActor (URLRequest) -> any WebSocketConnection = { URLSessionWebSocketConnection(request: $0) },
        makeTimer: @escaping WebSocketTimerFactory = { interval, repeats, block in
            Timer.scheduledTimer(withTimeInterval: interval, repeats: repeats) { _ in
                Task { @MainActor in
                    block()
                }
            }
        }
    ) {
        self.authService = authService
        self.makeConnection = makeConnection
        self.makeTimer = makeTimer
    }

    // MARK: - Connection Management

    func connect() async {
        // Fresh connect: reset the reconnect backoff
        reconnectAttempts = 0
        didRetryAfterUnauthorized = false
        stopReconnectTimer()
        await openConnection()
    }

    private func openConnection() async {
        guard !isConnected, connection == nil else { return }
        guard let url = webSocketURL else {
            Log.sync.error("WebSocket connect failed: invalid URL")
            isConnected = false
            return
        }

        // Get auth token (Pad's /v1/ws accepts a Bearer token on the upgrade request)
        let token: String
        do {
            token = try await authService.accessToken()
        } catch {
            Log.sync.error("WebSocket connect failed: couldn't get access token: \(String(describing: error), privacy: .public)")
            isConnected = false
            return
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let connection = makeConnection(request)
        self.connection = connection

        connection.onOpen = { [weak self] in
            guard let self else { return }
            self.isConnected = true
            self.reconnectAttempts = 0
            self.didRetryAfterUnauthorized = false
            Log.sync.debug("WebSocket connected")
            self.onConnected?()
        }

        connection.onClose = { [weak self] closeCode, reason in
            let reasonString = reason.flatMap { String(data: $0, encoding: .utf8) } ?? "unknown"
            Log.sync.debug("WebSocket closed: \(closeCode.rawValue) - \(reasonString, privacy: .public)")
            self?.handleDisconnect(error: nil)
        }

        connection.onHandshakeFailure = { [weak self] statusCode, error in
            // Only the 401-retry-once behavior lives here; other errored
            // completions are handled by receive's failure branch / onClose.
            guard statusCode == 401 else { return }
            Task { @MainActor in
                await self?.handleUnauthorizedHandshake(error: error)
            }
        }

        connection.resume()
        receiveMessage()
        startPingTimer()

        Log.sync.debug("WebSocket connecting to \(url.absoluteString, privacy: .public)")
    }

    /// Handles a handshake that failed with HTTP 401: forces exactly one token
    /// refresh and retries the connection once. A second 401 (or a failed
    /// refresh) surfaces as a normal disconnect — no further retries here.
    private func handleUnauthorizedHandshake(error: any Error) async {
        connection = nil
        isConnected = false
        stopPingTimer()

        guard !didRetryAfterUnauthorized else {
            Log.sync.error("WebSocket handshake unauthorized again after refresh — giving up")
            onDisconnected?(error)
            return
        }
        didRetryAfterUnauthorized = true

        do {
            _ = try await authService.forceRefresh()
        } catch {
            Log.sync.error("WebSocket forced refresh failed: \(String(describing: error), privacy: .public)")
            onDisconnected?(error)
            return
        }
        await openConnection()
    }

    func disconnect() {
        stopPingTimer()
        stopReconnectTimer()
        connection?.cancel(with: .goingAway, reason: nil)
        connection = nil
        isConnected = false
        reconnectAttempts = 0
        Log.sync.debug("WebSocket disconnected")
    }

    // MARK: - Message Handling

    private func receiveMessage() {
        connection?.receive { [weak self] result in
            Task { @MainActor in
                switch result {
                case .success(let message):
                    self?.handleMessage(message)
                    self?.receiveMessage() // Continue listening
                case .failure(let error):
                    Log.sync.error("WebSocket receive error: \(String(describing: error), privacy: .public)")
                    self?.handleDisconnect(error: error)
                }
            }
        }
    }

    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        switch message {
        case .string(let text):
            parseMessage(text)
        case .data(let data):
            if let text = String(data: data, encoding: .utf8) {
                parseMessage(text)
            }
        @unknown default:
            break
        }
    }

    private func parseMessage(_ text: String) {
        guard let data = text.data(using: .utf8) else {
            Log.sync.error("WebSocket message is not valid UTF-8")
            return
        }
        let message: WebSocketMessage
        do {
            message = try JSONDecoder().decode(WebSocketMessage.self, from: data)
        } catch {
            Log.sync.error("Failed to parse WebSocket message: \(String(describing: error), privacy: .public)")
            return
        }

        Log.sync.debug("WebSocket received: \(message.type.rawValue, privacy: .public)")

        switch message.type {
        case .scratchpadUpdated:
            if let id = message.scratchpadId {
                onScratchpadUpdated?(id)
            }
        case .scratchpadCreated:
            if let id = message.scratchpadId {
                onScratchpadCreated?(id)
            }
        case .scratchpadDeleted:
            if let id = message.scratchpadId {
                onScratchpadDeleted?(id)
            }
        case .ping:
            sendPong()
        case .pong:
            // Server responded to our ping
            break
        }
    }

    // MARK: - Ping/Pong

    private func startPingTimer() {
        pingTimer = makeTimer(30, true) { [weak self] in
            self?.sendPing()
        }
    }

    private func stopPingTimer() {
        pingTimer?.invalidate()
        pingTimer = nil
    }

    private func sendPing() {
        let message = WebSocketMessage(type: .ping, scratchpadId: nil, timestamp: Int(Date().timeIntervalSince1970 * 1000))
        send(message)
    }

    private func sendPong() {
        let message = WebSocketMessage(type: .pong, scratchpadId: nil, timestamp: Int(Date().timeIntervalSince1970 * 1000))
        send(message)
    }

    private func send(_ message: WebSocketMessage) {
        guard let data = try? JSONEncoder().encode(message),
              let text = String(data: data, encoding: .utf8) else { return }

        connection?.send(text) { error in
            if let error = error {
                Log.sync.error("WebSocket send error: \(String(describing: error), privacy: .public)")
            }
        }
    }

    // MARK: - Reconnection

    private func handleDisconnect(error: Error?) {
        isConnected = false
        connection = nil
        stopPingTimer()

        onDisconnected?(error)

        // Attempt to reconnect
        if reconnectAttempts < maxReconnectAttempts {
            scheduleReconnect()
        } else {
            Log.sync.error("WebSocket gave up after \(self.maxReconnectAttempts) reconnect attempts")
        }
    }

    private func scheduleReconnect() {
        reconnectAttempts += 1
        let delay = min(pow(2.0, Double(reconnectAttempts)), 30) // Exponential backoff, max 30s

        Log.sync.debug("WebSocket reconnecting in \(delay)s (attempt \(self.reconnectAttempts)/\(self.maxReconnectAttempts))")

        reconnectTimer = makeTimer(delay, false) { [weak self] in
            Task { @MainActor in
                await self?.openConnection()
            }
        }
    }

    private func stopReconnectTimer() {
        reconnectTimer?.invalidate()
        reconnectTimer = nil
    }
}
```

If the compiler rejects the `@MainActor` closure default arguments on the init (older-toolchain isolation inference), move the two defaults into the body via optional parameters is NOT the fix — instead mark the closure types in the signature exactly as written above; they are accepted on the project's current toolchain (Xcode 26). Report BLOCKED if a genuine toolchain error appears rather than restructuring the seam.

- [ ] **Step 4: Run to verify pass**

Run: `bash scripts/test.sh --unit 2>&1 | tail -20`
Expected: PASS — **191 tests** (176 + 15).

Verify the app still builds (all targets — the seam touched a file compiled into the main app): `xcodebuild build -project Groo.xcodeproj -scheme Groo -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -3` → `** BUILD SUCCEEDED **`

Manual smoke (behavior-preservation for the refactor): launch the app in the simulator, open the Scratchpad tab, confirm the WebSocket connects (Console: `WebSocket connected` in the `dev.groo.ios` sync category) and the scratchpad list loads.

- [ ] **Step 5: Commit**

```bash
git add Groo/Core/Sync/WebSocketService.swift GrooTests
git commit -m "refactor: WebSocketService socket/timer/token seams; test: connect/drop/reconnect state machine with fake socket"
```

---

### Task 6: Full verification + docs + coverage snapshot

**Files:**
- Modify: `README.md` (Testing conventions: two lines)

- [ ] **Step 1: Full suite twice**

Run: `bash scripts/test.sh --all 2>&1 | tail -5 && bash scripts/test.sh --all 2>&1 | tail -5`
Expected: `** TEST SUCCEEDED **` twice — 191 unit tests + 1 UI test, both runs.

- [ ] **Step 2: App builds**

Run: `xcodebuild build -project Groo.xcodeproj -scheme Groo -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Coverage snapshot**

Run: `bash scripts/test.sh --unit --coverage 2>&1 | tail -45`
Record in the task report: coverage for `SyncService.swift`, `SyncState.swift`, `WebSocketService.swift`, `APIClient.swift`, `PendingOperation.swift`, `LocalStore.swift`, `APICache.swift` (expected: SyncState/PendingOperation/APIClient/APICache well above 80%; SyncService above 60% — the scratchpad CRUD passthroughs are Phase 4 territory; WebSocketService above 70% — the URLSession wrapper is intentionally uncovered).

- [ ] **Step 4: README lines**

In `README.md`'s Testing conventions list (after the wallet-vectors line), append:

```markdown
- SwiftData suites use in-memory containers via `InMemoryLocalStore.make()` — never `LocalStore.shared`.
- WebSocket tests script a `FakeWebSocketConnection` (`GrooTests/Support/WebSocketFakes.swift`); reconnect/ping timers are recorded and fired manually, never waited on.
```

- [ ] **Step 5: Commit**

```bash
git add README.md
git commit -m "docs: note sync/websocket test conventions in README"
```

- [ ] **Step 6: Final report**

Include in the report to the user:
- Final test totals and the coverage numbers from Step 3.
- Product gaps found during planning (not bugs introduced): (1) the sync queue has no timed retry/backoff — failed ops wait for the next sync trigger; (2) no operation coalescing — offline create+delete of the same item pushes both operations; (3) `SyncState` discards an error status when connectivity flips offline. All three are documented by pinned tests; changing them is product work, not test retrofit.

---

## Post-plan

Remaining spec phases: 4 (extensions & remaining features), 5 (UI tests), 6 (edge-case sweep) — each gets its own plan. Phase 3 fast-follow candidates for the Phase 4 plan: `PadService`/`ScratchpadService` logic over the now-testable `SyncService` seams; `PushService` token registration (uses `AuthService` directly — may want the `WebSocketTokenProviding` protocol widened or a sibling seam).
