# iOS Test Suite — Phase 4 (Extensions & Remaining Features) + Phase 3 Fast-Follows Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Test the extension layer (AutoFill credential matching + pending-passkey queue, credential-identity payload building, Widget/Keyboard Pad decryption, `SharedConfig`/`Config` overrides) and the remaining feature services (Stocks cost-basis math + portfolio manager + Yahoo parsing, Azan preferences + prayer tracking, Pad/Scratchpad crypto roundtrips + scratchpad CRUD), plus two Phase 3 fast-follows (APIClient multipart/upload coverage; the pre-approved `URLSessionWebSocketConnection.cancel` session-invalidation fix).

**Architecture:** Same retrofit pattern as Phases 1–3, with one structural addition:

1. **Default-parameter injections** — `StockPortfolioManager(store:)`, `YahooFinanceService(cache:)`, `PrayerTrackingService(store:now:)`, `PadService(keychain:)` (concrete `KeychainService` → `any KeychainServicing`, mirroring PassService), `SharedPendingItemsStore(… fileURL:)`, `Config.overrideURL(forKey:in:)` — production call sites unchanged.
2. **Pure-logic extraction into `Shared/`** (the spec's "extract into Shared/ where currently inline in extension targets"): `SharedCredentialMatcher` (domain↔credential matching, search, passkey allow-list filtering, pending-queue merge — moved verbatim from `GrooAutoFill/AutoFillService.swift`) and `SharedPadCrypto` (AES-GCM Pad-payload decryption — moved verbatim from the byte-identical `ExtensionCrypto` copies in `WidgetExtension/ExtensionHelper.swift` and `KeyboardExtension/ExtensionHelper.swift`). Extension-target `.swift` files are NOT compiled into GrooTests; only `Shared/` (compiled into the app target) and `Groo/` are testable.
3. **pbxproj mechanics for new `Shared/` files** — `Shared/` is a **classic (non-synchronized) PBXGroup**: unlike `GrooTests/`/`Groo/` (PBXFileSystemSynchronizedRootGroup), files dropped into `Shared/` are NOT picked up automatically. Every existing Shared file has one PBXFileReference + one PBXBuildFile per consuming target (currently: Groo and GrooAutoFill only; Widget/Keyboard/Share compile zero Shared files). New Shared files are registered exclusively via the new `scripts/register_shared_file.rb` (Ruby + the installed `xcodeproj` gem 1.27.0, same toolchain as `scripts/add_test_targets.rb`) — **never by hand-editing the pbxproj**.

**Tech Stack:** Swift Testing; SwiftData in-memory containers (`InMemoryLocalStore`); `StubURLProtocol` (+ a new binary-body `enqueue(data:)` overload) under the `NetworkStubbedSuites` umbrella; `InMemoryKeychain`; Ruby `xcodeproj` for Shared-file registration; `xcodebuild` via `scripts/test.sh`.

**Spec:** `docs/superpowers/specs/2026-07-05-ios-test-suite-design.md` (Phase 4 section) + the Phase 3 final-review fast-follows.

## Spec-coverage notes (read before implementing)

What is deliberately **not** tested this phase, and why — do not invent coverage for these:

- **GrooAutoFill UI/host plumbing** (`CredentialProviderViewController`, `AutoFillCredentialListView`, `RegisterPasskeyView`, `AutoFillService.unlock()`/`loadCredentials()` vault I/O): needs a real `ASCredentialProviderExtensionContext`, the app-group keychain with biometrics, and `SharedVaultStore` files — none reachable from a test host. All *decidable logic* those paths call (domain matching, passkey allow-list filtering, credential-ID lookup, pending-queue merge/dedupe, assertion signing with sign count 0) is either extracted and tested here (Task 2) or already pinned (`SharedPasskeyCryptoTests`, Phase 1). The queue file format itself is pinned in Task 3.
- **`CredentialIdentityService.updateCredentialIdentities`/`clearCredentialIdentities`**: talk to the real `ASCredentialIdentityStore.shared` (entitlement-gated, global). The payload **builders** are made internal and tested; the store round-trip stays manual-smoke territory (PassService's *calls into* the service are already pinned via `RecordingCredentialService`).
- **Widget/Keyboard timeline & snapshot glue** (`PadWidgetProvider.loadItems`, `KeyboardViewController.loadItems`): a `prefix(5)`/`prefix(10)` + `isLocked` flag mapping — trivial, YAGNI, not extracted. The substantive logic they share (AES-GCM Pad-payload decryption) IS extracted and contract-tested in Task 4. `ExtensionDataProvider`/`ExtensionKeychain` require the real app-group keychain + on-disk SwiftData store — manual smoke only.
- **AzanWidget** entry building duplicates `PrayerTimeService`'s deadline/next-prayer logic inside the widget target. Not extracted this phase (would drag the Adhan dependency plumbing into Shared for logic that already exists in the app); flag in the final report as a consolidation candidate.
- **ShareExtension**: `NSItemProvider` loading is host-glue. Its `saveToAppGroup` merge/corrupt-move logic writes `shared_items.json` — **which nothing in the main app ever reads** (verified: zero references to `shared_items`/`SharedItem` outside `ShareExtension/`). Extracting write-only queue logic has no consumer to protect; flag as a **product gap** in the final report instead.
- **`PrayerTimeService`**: `Date()`/`Timer`-coupled Adhan wrapper throughout (`recalculate`, qaza cutoffs, Ramadan detection). Testing it honestly needs a `now` seam threaded through ~10 call sites — a bigger refactor than this phase's budget; the *preferences* feeding it are fully tested (Task 6). Flag as the top Phase 6 candidate.
- **`YahooFinanceService.withRetry` 429 backoff**: uses real `Task.sleep` — untestable under the no-sleeps rule without a sleep seam. Deliberately uncovered; flag as a refactor candidate.
- **`SharedConfig` "UserDefaults overrides"** (spec wording): `SharedConfig` has *no* UserDefaults overrides — that pattern lives in `Groo/Core/Config.swift` (`overrideURL(forKey:)`). Task 3 tests the actual override resolution there and pins `SharedConfig`'s compile-time values (including agreement with `Config`, which a typo would silently break — app and extensions would stop sharing the keychain/app-group). The third copy, `ExtensionConfig` in the Widget/Keyboard `ExtensionHelper.swift`, cannot be compile-checked from tests (extension targets) — noted as residual drift risk.
- **`Config.overrideURL` invalid-override branch**: calls `assertionFailure` — crashes a Debug test host by design. Valid/absent branches tested; invalid branch documented untestable.
- **`URLSessionWebSocketConnection.cancel` fix (Task 1)**: NOT observable via `FakeWebSocketConnection` — the fix lives inside the production wrapper the fake *replaces*, and driving the real wrapper needs a live socket handshake. Verified by build + full suite + the existing manual smoke; optional Instruments leak check noted. Also note: the same session-retain pattern exists on the non-cancel drop paths (`handleDisconnect`/`handleUnauthorizedHandshake` nil the connection without cancelling it) — fixing those is product work beyond the pre-approved one-liner; flag in the final report.

## Global Constraints

- Working directory: `/Users/groo/work/gr/ios`. Test runner: `bash scripts/test.sh --unit` → `** TEST SUCCEEDED **`.
- GrooTests uses synchronized folders — new `.swift` files under `GrooTests/` compile automatically. **`Shared/` does NOT**: it is a classic group; new Shared files are registered only via `ruby scripts/register_shared_file.rb <File.swift> <Target>...` (Tasks 2 and 4). **Never edit the pbxproj by hand.** After each ruby run, inspect `git diff Groo.xcodeproj/project.pbxproj` — the diff must be pure additions of the expected PBXFileReference/PBXBuildFile/group-children/Sources entries.
- Suites that use `StubURLProtocol` (existing `APIClientTests` being extended, new `YahooFinanceServiceTests`, `PadServiceTests`, `SyncServiceScratchpadTests`) MUST be declared inside `extension NetworkStubbedSuites { ... }` with `@Suite(.serialized)` and call `StubURLProtocol.reset()` first in each test. All other new suites touch no shared static state and stay outside the umbrella (parallel-safe).
- **No sleeps, no `Task.yield` polling.** Time is injected where needed (`PrayerTrackingService(now:)`); everything else in this phase is synchronous or awaits its own async call.
- Every production change is behavior-preserving: default-parameter seams keep byte-for-byte default behavior; the two `Shared/` extractions move code verbatim (the `SharedCredentialMatcher` guard clauses reproduce `AutoFillService`'s early returns exactly; `SharedPadCrypto` is the `ExtensionCrypto` body unchanged); `PadService`'s keychain type widening passes the previously-implicit default `prompt: "Authenticate to access Pad"` explicitly (same string as `KeychainService`'s default parameter).
- SwiftData in tests: always `InMemoryLocalStore.make()`. Never `LocalStore.shared`.
- UserDefaults in tests: only suite-named instances (`UserDefaults(suiteName:)` + `removePersistentDomain` cleanup). Never write `UserDefaults.standard` (in particular never set `padAPIBaseURL` or `displayCurrency`). Reading `.standard` indirectly (e.g. `StockPortfolioManager.displayCurrency`) is unavoidable but no test asserts values that depend on it.
- Temp files (`SharedPendingItemsStoreTests`): under `FileManager.default.temporaryDirectory` + UUID, removed at test end. Never the app-group container.
- **Verification discipline:** baseline is **191 unit tests in 23 suites + 1 UI test**, all green. Before each commit: `bash scripts/test.sh --unit` green AND the app builds (`xcodebuild build -project Groo.xcodeproj -scheme Groo -destination 'platform=iOS Simulator,name=iPhone 17 Pro'` — this also compiles all five extension targets, which is the compile-check for extension-side edits). Running totals per task (verify the count in the xcodebuild summary; if it differs, find out why before committing):
  - After Task 1: **198** unit tests, 23 suites
  - After Task 2: **213** unit tests, 25 suites
  - After Task 3: **224** unit tests, 28 suites
  - After Task 4: **230** unit tests, 29 suites
  - After Task 5: **250** unit tests, 32 suites
  - After Task 6: **263** unit tests, 34 suites
  - After Task 7: **280** unit tests, 37 suites
- Test-failure messages that pin product semantics (the `"group.dev.groo.ios.debug"` app-group ID, the multipart field name `"file"`/filename `"encrypted"`, the sub-vs-lookalike domain-matching rule) are intentional couplings — if one fails, investigate the production change, don't silently update the string.

---

### Task 1: Phase 3 fast-follows — APIClient upload/download coverage + WebSocket session-leak fix

**Files:**
- Modify: `GrooTests/Core/Network/APIClientTests.swift` (append tests inside the existing struct)
- Modify: `Groo/Core/Sync/WebSocketService.swift:95-99` (`URLSessionWebSocketConnection.cancel`)

**Interfaces:**
- Consumes: existing `APIClientTests` conventions (`Self.makeClient(tokens:)`, `TokenSource`, `StubURLProtocol`, `URLRequest.bodyData`), `FileUploadResponse`, `APIError`.
- Produces: nothing new — `uploadFile`/`downloadFile`/void-`post` already exist and the session is already injectable (Phase 3 seam).

**Note:** `uploadFile` builds its own request (bypassing `buildRequest`), generates a fresh UUID boundary per attempt, and routes errors through `perform` (server message parsed). `downloadFile` does NOT parse server messages (`message: nil` always) — the test documents that. The `cancel` fix is the pre-approved one-liner: the per-connection `URLSession` retains its delegate (the connection) until invalidated, so every connect/disconnect cycle leaks a session+connection pair without it. It is not observable through `FakeWebSocketConnection` (see spec-coverage notes) — verification is compile + suite + manual smoke.

- [ ] **Step 1: Write the failing-then-passing tests**

In `GrooTests/Core/Network/APIClientTests.swift`, add inside the `APIClientTests` struct, after `transportErrorPropagatesAsURLError` (before the struct's closing brace):

```swift
    // MARK: - File upload (multipart)

    @Test func uploadFileBuildsMultipartBodyMatchingHeaderBoundary() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.enqueue(method: "POST", pathSuffix: "/v1/files", json: #"{"id":"f-1","size":9,"r2Key":"k/f-1"}"#)
        let payload = Data("encrypted".utf8)

        let response = try await Self.makeClient().uploadFile(payload, to: "/v1/files")

        #expect(response.id == "f-1")
        #expect(response.size == 9)
        #expect(response.r2Key == "k/f-1")

        let request = try #require(StubURLProtocol.recordedRequests.first)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer tok-1")
        let contentType = try #require(request.value(forHTTPHeaderField: "Content-Type"))
        #expect(contentType.hasPrefix("multipart/form-data; boundary="))
        let boundary = String(contentType.dropFirst("multipart/form-data; boundary=".count))
        try #require(!boundary.isEmpty)

        // Byte-exact multipart layout: the server contract for encrypted uploads
        let body = try #require(request.bodyData)
        let expected = Data((
            "--\(boundary)\r\n" +
            "Content-Disposition: form-data; name=\"file\"; filename=\"encrypted\"\r\n" +
            "Content-Type: application/octet-stream\r\n\r\n"
        ).utf8) + payload + Data("\r\n--\(boundary)--\r\n".utf8)
        #expect(body == expected)
    }

    @Test func uploadFile401RefreshesAndRetriesWithFreshBoundary() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.enqueue(method: "POST", pathSuffix: "/v1/files", status: 401, json: "{}")
        StubURLProtocol.enqueue(method: "POST", pathSuffix: "/v1/files", json: #"{"id":"f-1","size":4,"r2Key":"k"}"#)
        let tokens = TokenSource()

        _ = try await Self.makeClient(tokens: tokens).uploadFile(Data("data".utf8), to: "/v1/files")

        #expect(tokens.refreshCalls == 1)
        let requests = StubURLProtocol.recordedRequests
        try #require(requests.count == 2)
        #expect(requests[0].value(forHTTPHeaderField: "Authorization") == "Bearer tok-1")
        #expect(requests[1].value(forHTTPHeaderField: "Authorization") == "Bearer tok-2")
        // The retry re-runs the whole operation — each attempt's body opens
        // with its own header's boundary (fresh UUID per attempt)
        for request in requests {
            let contentType = try #require(request.value(forHTTPHeaderField: "Content-Type"))
            let boundary = String(contentType.dropFirst("multipart/form-data; boundary=".count))
            let body = try #require(request.bodyData)
            #expect(body.starts(with: Data("--\(boundary)\r\n".utf8)))
        }
    }

    @Test func uploadFileHttpErrorSurfacesServerMessage() async {
        StubURLProtocol.reset()
        StubURLProtocol.enqueue(method: "POST", pathSuffix: "/v1/files", status: 413, json: #"{"error":"too large"}"#)

        await #expect {
            _ = try await Self.makeClient().uploadFile(Data("x".utf8), to: "/v1/files")
        } throws: { error in
            guard case APIError.httpError(let status, let message) = error else { return false }
            return status == 413 && message == "too large"
        }
    }

    // MARK: - File download

    @Test func downloadFileReturnsRawBytesWithoutDecoding() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.enqueue(method: "GET", pathSuffix: "/v1/files/abc123", json: "raw-bytes-not-json")

        let data = try await Self.makeClient().downloadFile(from: "/v1/files/abc123")

        #expect(data == Data("raw-bytes-not-json".utf8))
    }

    @Test func downloadFileErrorHasNoServerMessage() async {
        StubURLProtocol.reset()
        StubURLProtocol.enqueue(method: "GET", pathSuffix: "/v1/files/abc123", status: 404, json: #"{"error":"gone"}"#)

        await #expect {
            _ = try await Self.makeClient().downloadFile(from: "/v1/files/abc123")
        } throws: { error in
            // Documents actual behavior: downloadFile never parses the server
            // message — message is always nil (unlike perform/performVoid)
            guard case APIError.httpError(let status, let message) = error else { return false }
            return status == 404 && message == nil
        }
    }

    // MARK: - Void POST

    @Test func voidPostTreats2xxAsSuccess() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.enqueue(method: "POST", pathSuffix: "/v1/ping", status: 204, json: "")

        try await Self.makeClient().post("/v1/ping")   // must not throw

        let request = try #require(StubURLProtocol.recordedRequests.first)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer tok-1")
        #expect(request.bodyData == nil)
    }

    @Test func voidPostExtractsServerMessageOnError() async {
        StubURLProtocol.reset()
        StubURLProtocol.enqueue(method: "POST", pathSuffix: "/v1/ping", status: 500, json: #"{"error":"boom"}"#)

        await #expect {
            try await Self.makeClient().post("/v1/ping")
        } throws: { error in
            guard case APIError.httpError(let status, let message) = error else { return false }
            return status == 500 && message == "boom"
        }
    }
```

- [ ] **Step 2: Run to verify the tests pass against current production**

Run: `bash scripts/test.sh --unit 2>&1 | tail -5`
Expected: PASS — **198 tests** (191 + 7). These are coverage tests over existing behavior, not TDD for a new seam — if any fails, production deviates from the recon'd contract: STOP and report, don't adjust assertions.

- [ ] **Step 3: Apply the pre-approved leak fix**

In `Groo/Core/Sync/WebSocketService.swift`, in `URLSessionWebSocketConnection`, replace:

```swift
    func cancel(with closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        task?.cancel(with: closeCode, reason: reason)
        task = nil
        session = nil
    }
```

with:

```swift
    func cancel(with closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        task?.cancel(with: closeCode, reason: reason)
        task = nil
        // The session retains its delegate (self) until invalidated — without
        // this, every connect/disconnect cycle leaks a session+connection pair.
        session?.invalidateAndCancel()
        session = nil
    }
```

- [ ] **Step 4: Run to verify pass**

Run: `bash scripts/test.sh --unit 2>&1 | tail -5`
Expected: PASS — **198 tests** (the WebSocket suite drives the fake, unaffected).

Verify the app still builds: `xcodebuild build -project Groo.xcodeproj -scheme Groo -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -3` → `** BUILD SUCCEEDED **`

Manual smoke (leak fix): launch the app, open Scratchpad (WebSocket connects), background/foreground twice — Console shows `WebSocket disconnected` / `WebSocket connected` with no crash. (Optional: Instruments → Leaks confirms no accumulating `URLSessionWebSocketConnection`.)

- [ ] **Step 5: Commit**

```bash
git add Groo/Core/Sync/WebSocketService.swift GrooTests
git commit -m "test: APIClient upload/download coverage; fix: invalidate WebSocket URLSession on cancel (delegate-retain leak)"
```

---

### Task 2: AutoFill matching → `Shared/SharedCredentialMatcher` + credential-identity payload tests

**Files:**
- Create: `scripts/register_shared_file.rb` (reusable — Task 4 uses it again)
- Create: `Shared/SharedCredentialMatcher.swift` (+ pbxproj registration to Groo, GrooAutoFill)
- Modify: `GrooAutoFill/AutoFillService.swift` (delegate to the matcher)
- Modify: `Groo/Features/Pass/CredentialIdentityService.swift` (builders `private` → internal)
- Test: `GrooTests/Shared/SharedCredentialMatcherTests.swift`
- Test: `GrooTests/Features/Pass/CredentialIdentityServiceTests.swift`

**Interfaces:**
- Consumes: `SharedPassPasswordItem` (`domains`, `urls`, `name`, `username`), `SharedPassPasskeyItem` (explicit init), `Data.base64URLEncodedString` (all in `Shared/SharedPassModels.swift`, compiled into both targets); `PassVaultItem`/`PassPasswordItem`/`PassPasskeyItem` explicit inits (main-app models, test-host only).
- Produces: `SharedCredentialMatcher` (pure static API below); internal `CredentialIdentityService.buildPasswordIdentities(from:)`/`buildPasskeyIdentities(from:)`.
- Call-site compatibility: `AutoFillService`'s public method signatures are unchanged (`AutoFillCredentialListView` and `CredentialProviderViewController` compile as-is). `AutoFillService.domainsMatch` is deleted — verified to have no callers outside `AutoFillService` itself.

- [ ] **Step 1: Create the registration script**

`scripts/register_shared_file.rb`:

```ruby
#!/usr/bin/env ruby
# Registers an existing Shared/<file> in the classic (non-synchronized) Shared
# group and adds it to the given targets' Sources phases. Shared/ is NOT a
# filesystem-synchronized group — without this, a new Shared file compiles
# into nothing. Idempotent.
# usage: ruby scripts/register_shared_file.rb <FileName.swift> <Target> [<Target>...]
require 'xcodeproj'

file_name = ARGV.shift
abort 'usage: register_shared_file.rb <FileName.swift> <Target>...' if file_name.nil? || ARGV.empty?
target_names = ARGV

abort "ERROR: Shared/#{file_name} does not exist on disk" \
  unless File.exist?(File.expand_path("../Shared/#{file_name}", __dir__))

project_path = File.expand_path('../Groo.xcodeproj', __dir__)
project = Xcodeproj::Project.open(project_path)

shared_group = project.main_group['Shared']
abort 'ERROR: Shared group not found' unless shared_group

file_ref = shared_group.files.find { |f| f.path == file_name } || shared_group.new_reference(file_name)

target_names.each do |name|
  target = project.targets.find { |t| t.name == name }
  abort "ERROR: target #{name} not found" unless target
  if target.source_build_phase.files_references.include?(file_ref)
    puts "#{name}: already registered"
  else
    target.source_build_phase.add_file_reference(file_ref)
    puts "#{name}: added"
  end
end

project.save
puts "OK: Shared/#{file_name} registered"
```

- [ ] **Step 2: Write the failing tests**

`GrooTests/Shared/SharedCredentialMatcherTests.swift`:

```swift
//
//  SharedCredentialMatcherTests.swift
//  GrooTests
//
//  Domain↔credential matching, query search, passkey allow-list filtering,
//  and pending-queue merge — the pure logic behind AutoFill suggestions.
//

import Foundation
import Testing
@testable import Groo

struct SharedCredentialMatcherTests {
    /// SharedPassPasswordItem has no memberwise init (custom Decodable
    /// initializer suppresses it) — build fixtures through the decoder,
    /// which also keeps them honest against the wire format.
    static func credential(
        id: String = "c-1",
        name: String = "Example",
        username: String = "user@example.com",
        urls: [String]
    ) throws -> SharedPassPasswordItem {
        let urlsJSON = urls.map { #""\#($0)""# }.joined(separator: ",")
        let json = #"{"id":"\#(id)","type":"password","name":"\#(name)","username":"\#(username)","password":"pw","urls":[\#(urlsJSON)]}"#
        return try JSONDecoder().decode(SharedPassPasswordItem.self, from: Data(json.utf8))
    }

    static func passkey(
        id: String = "pk-1",
        name: String = "Example",
        rpId: String = "example.com",
        credentialId: String = "Y3JlZC1pZA"
    ) -> SharedPassPasskeyItem {
        SharedPassPasskeyItem(
            id: id, name: name, rpId: rpId, rpName: rpId,
            credentialId: credentialId, publicKey: "cHVi", privateKey: "cHJpdg==",
            userHandle: "dXNlcg", userName: "user@example.com"
        )
    }

    // MARK: - Domain matching

    @Test func domainsMatchExactAndSubdomainsBothDirections() {
        #expect(SharedCredentialMatcher.domainsMatch("google.com", "google.com"))
        #expect(SharedCredentialMatcher.domainsMatch("accounts.google.com", "google.com"))
        #expect(SharedCredentialMatcher.domainsMatch("google.com", "accounts.google.com"))
        #expect(!SharedCredentialMatcher.domainsMatch("google.com", "github.com"))
    }

    @Test func lookalikeDomainsNeverMatch() {
        // The dot-anchored suffix rule: "app.com" must not unlock "myapp.com"
        #expect(!SharedCredentialMatcher.domainsMatch("myapp.com", "app.com"))
        #expect(!SharedCredentialMatcher.domainsMatch("app.com", "myapp.com"))
        #expect(!SharedCredentialMatcher.domainsMatch("oo.dev", "groo.dev"))
    }

    @Test func emptySearchDomainsReturnsAllCredentials() throws {
        let credentials = [
            try Self.credential(id: "c-1", urls: ["https://a.com"]),
            try Self.credential(id: "c-2", urls: ["https://b.io"]),
        ]
        let result = SharedCredentialMatcher.credentials(credentials, matchingDomains: [])
        #expect(result.map(\.id) == ["c-1", "c-2"])
    }

    @Test func credentialMatchesViaAnyOfItsSavedUrls() throws {
        let credentials = [
            try Self.credential(id: "multi", urls: ["https://mail.google.com", "github.com"]),
            try Self.credential(id: "other", urls: ["https://example.com"]),
        ]
        let result = SharedCredentialMatcher.credentials(credentials, matchingDomains: ["github.com"])
        #expect(result.map(\.id) == ["multi"])
    }

    @Test func subdomainSearchMatchesSavedRootDomain() throws {
        let credentials = [try Self.credential(id: "root", urls: ["google.com"])]
        let fromSubdomain = SharedCredentialMatcher.credentials(credentials, matchingDomains: ["accounts.google.com"])
        #expect(fromSubdomain.map(\.id) == ["root"])

        let saved = [try Self.credential(id: "sub", urls: ["https://accounts.google.com"])]
        let fromRoot = SharedCredentialMatcher.credentials(saved, matchingDomains: ["google.com"])
        #expect(fromRoot.map(\.id) == ["sub"])
    }

    @Test func credentialWithoutParseableUrlsNeverMatches() throws {
        let credentials = [try Self.credential(id: "no-urls", urls: [])]
        let result = SharedCredentialMatcher.credentials(credentials, matchingDomains: ["example.com"])
        #expect(result.isEmpty)
    }

    // MARK: - Query search

    @Test func querySearchIsCaseInsensitiveAcrossNameUsernameAndUrls() throws {
        let credentials = [
            try Self.credential(id: "by-name", name: "GitHub", urls: ["https://a.com"]),
            try Self.credential(id: "by-user", username: "GITHUB-bot@x.com", urls: ["https://b.com"]),
            try Self.credential(id: "by-url", urls: ["https://github.com/login"]),
            try Self.credential(id: "no-hit", name: "Example", urls: ["https://example.com"]),
        ]
        let result = SharedCredentialMatcher.credentials(credentials, matchingQuery: "github")
        #expect(result.map(\.id) == ["by-name", "by-user", "by-url"])
        #expect(SharedCredentialMatcher.credentials(credentials, matchingQuery: "").count == 4)
    }

    // MARK: - Passkeys

    @Test func passkeysFilterByRpIdAndAllowList() {
        let passkeys = [
            Self.passkey(id: "pk-1", rpId: "example.com", credentialId: "aWQtMQ"),
            Self.passkey(id: "pk-2", rpId: "example.com", credentialId: "aWQtMg"),
            Self.passkey(id: "pk-3", rpId: "other.com", credentialId: "aWQtMw"),
        ]

        #expect(SharedCredentialMatcher.passkeys(passkeys, forRpId: nil, allowedCredentialIds: []).isEmpty)
        #expect(SharedCredentialMatcher.passkeys(passkeys, forRpId: "example.com", allowedCredentialIds: []).map(\.id) == ["pk-1", "pk-2"])
        #expect(SharedCredentialMatcher.passkeys(passkeys, forRpId: "example.com", allowedCredentialIds: ["aWQtMg"]).map(\.id) == ["pk-2"])
    }

    @Test func findPasskeyComparesRawBytesAgainstStoredBase64URL() {
        // "cred-id" bytes → base64url "Y3JlZC1pZA" (no padding)
        let passkeys = [Self.passkey(id: "pk-1", credentialId: "Y3JlZC1pZA")]

        let found = SharedCredentialMatcher.passkey(in: passkeys, credentialId: Data("cred-id".utf8))
        #expect(found?.id == "pk-1")
        #expect(SharedCredentialMatcher.passkey(in: passkeys, credentialId: Data("other".utf8)) == nil)
    }

    @Test func mergingPendingPasskeysDedupesByCredentialIdVaultWins() {
        let vault = [Self.passkey(id: "vault-copy", credentialId: "aWQtMQ")]
        let pending = [
            Self.passkey(id: "stale-pending", credentialId: "aWQtMQ"),   // already merged into the vault
            Self.passkey(id: "fresh-pending", credentialId: "aWQtMg"),
        ]

        let merged = SharedCredentialMatcher.mergingPendingPasskeys(vault: vault, pending: pending)
        #expect(merged.map(\.id) == ["vault-copy", "fresh-pending"])
    }
}
```

`GrooTests/Features/Pass/CredentialIdentityServiceTests.swift`:

```swift
//
//  CredentialIdentityServiceTests.swift
//  GrooTests
//
//  QuickType identity payload building: URL normalization, per-URL fan-out,
//  deleted/malformed record exclusion, base64url decoding for passkeys.
//  (The ASCredentialIdentityStore round-trip itself is entitlement-gated and
//  stays manual-smoke territory.)
//

import AuthenticationServices
import Foundation
import Testing
@testable import Groo

struct CredentialIdentityServiceTests {
    static func passwordItem(
        id: String,
        urls: [String],
        username: String = "user@example.com",
        deletedAt: Int? = nil
    ) -> PassPasswordItem {
        PassPasswordItem(
            id: id, type: .password, name: "Item", username: username, password: "pw",
            urls: urls, notes: nil, totp: nil, folderId: nil, favorite: nil,
            createdAt: 1_700_000_000_000, updatedAt: 1_700_000_000_000, deletedAt: deletedAt
        )
    }

    static func passkeyItem(
        id: String,
        rpId: String = "example.com",
        credentialId: String = "Y3JlZC1pZA",
        userHandle: String = "dXNlcg",
        deletedAt: Int? = nil
    ) -> PassPasskeyItem {
        var item = PassPasskeyItem(
            id: id, name: rpId, rpId: rpId, rpName: rpId,
            credentialId: credentialId, publicKey: "cHVi", privateKey: "cHJpdg==",
            userHandle: userHandle, userName: "user@example.com", signCount: 0,
            createdAt: 1_700_000_000_000, updatedAt: 1_700_000_000_000
        )
        item.deletedAt = deletedAt
        return item
    }

    // MARK: - Password identities

    @Test func schemelessUrlsAreNormalizedAndHostsLowercased() throws {
        // Saved URLs are often bare domains — the https:// prefix rule is what
        // makes them appear in QuickType at all
        let service = CredentialIdentityService()
        let items: [PassVaultItem] = [.password(Self.passwordItem(id: "p-1", urls: ["MyApp.Example.COM"]))]

        let identities = service.buildPasswordIdentities(from: items)

        let identity = try #require(identities.first)
        #expect(identities.count == 1)
        #expect(identity.serviceIdentifier.identifier == "myapp.example.com")
        #expect(identity.serviceIdentifier.type == .domain)
        #expect(identity.user == "user@example.com")
        #expect(identity.recordIdentifier == "p-1")
    }

    @Test func oneIdentityPerSavedUrl() {
        let service = CredentialIdentityService()
        let items: [PassVaultItem] = [.password(Self.passwordItem(id: "p-1", urls: ["https://a.com/login", "b.io"]))]

        let identities = service.buildPasswordIdentities(from: items)

        #expect(identities.map(\.serviceIdentifier.identifier) == ["a.com", "b.io"])
        #expect(identities.allSatisfy { $0.recordIdentifier == "p-1" })
    }

    @Test func deletedAndNonPasswordItemsProduceNoPasswordIdentities() {
        let service = CredentialIdentityService()
        let items: [PassVaultItem] = [
            .password(Self.passwordItem(id: "trashed", urls: ["https://a.com"], deletedAt: 1_700_000_000_000)),
            .password(Self.passwordItem(id: "no-urls", urls: [])),
            .passkey(Self.passkeyItem(id: "pk-1")),
        ]

        #expect(service.buildPasswordIdentities(from: items).isEmpty)
    }

    // MARK: - Passkey identities

    @Test func passkeyIdentityDecodesBase64URLFields() throws {
        let service = CredentialIdentityService()
        // "Y3JlZC1pZA" → "cred-id", "dXNlcg" → "user"
        let items: [PassVaultItem] = [.passkey(Self.passkeyItem(id: "pk-1"))]

        let identities = service.buildPasskeyIdentities(from: items)

        let identity = try #require(identities.first)
        #expect(identities.count == 1)
        #expect(identity.relyingPartyIdentifier == "example.com")
        #expect(identity.credentialID == Data("cred-id".utf8))
        #expect(identity.userHandle == Data("user".utf8))
        #expect(identity.userName == "user@example.com")
        #expect(identity.recordIdentifier == "pk-1")
    }

    @Test func malformedAndDeletedPasskeysAreSkippedNotCrashed() {
        let service = CredentialIdentityService()
        let items: [PassVaultItem] = [
            .passkey(Self.passkeyItem(id: "bad-b64", credentialId: "!!!not-base64url!!!")),
            .passkey(Self.passkeyItem(id: "trashed", deletedAt: 1_700_000_000_000)),
            .password(Self.passwordItem(id: "p-1", urls: ["https://a.com"])),
        ]

        #expect(service.buildPasskeyIdentities(from: items).isEmpty)
    }
}
```

- [ ] **Step 3: Run to verify failure**

Run: `bash scripts/test.sh --unit 2>&1 | tail -20`
Expected: BUILD FAILURE — `SharedCredentialMatcher` not found; `buildPasswordIdentities` inaccessible (private).

- [ ] **Step 4: Create the Shared file and register it**

`Shared/SharedCredentialMatcher.swift`:

```swift
//
//  SharedCredentialMatcher.swift
//  Groo
//
//  Pure credential/passkey matching and search logic shared by the app and
//  the AutoFill extension. Extracted verbatim from AutoFillService so the
//  domain-matching semantics are testable from GrooTests (extension-target
//  files are not compiled into the test host).
//

import Foundation

enum SharedCredentialMatcher {
    /// Exact host or subdomain match: "accounts.google.com" matches a saved
    /// "google.com" (and vice versa), but "app.com" never matches "myapp.com"
    static func domainsMatch(_ a: String, _ b: String) -> Bool {
        a == b || a.hasSuffix(".\(b)") || b.hasSuffix(".\(a)")
    }

    /// Filter credentials that match any of the search domains (checks all
    /// saved URLs). An empty search-domain list means "no filter".
    static func credentials(
        _ credentials: [SharedPassPasswordItem],
        matchingDomains searchDomains: [String]
    ) -> [SharedPassPasswordItem] {
        guard !searchDomains.isEmpty else {
            return credentials
        }

        return credentials.filter { credential in
            let credentialDomains = credential.domains
            guard !credentialDomains.isEmpty else { return false }

            return searchDomains.contains { searchDomain in
                credentialDomains.contains { credDomain in
                    domainsMatch(credDomain, searchDomain)
                }
            }
        }
    }

    /// Case-insensitive search over name, username, and raw saved URLs.
    static func credentials(
        _ credentials: [SharedPassPasswordItem],
        matchingQuery query: String
    ) -> [SharedPassPasswordItem] {
        guard !query.isEmpty else {
            return credentials
        }

        let lowercasedQuery = query.lowercased()

        return credentials.filter { credential in
            credential.name.lowercased().contains(lowercasedQuery) ||
            credential.username.lowercased().contains(lowercasedQuery) ||
            credential.urls.contains { $0.lowercased().contains(lowercasedQuery) }
        }
    }

    /// Filter passkeys by relying party ID and the request's allow-list of
    /// base64url credential IDs. An empty allow-list means "any".
    static func passkeys(
        _ passkeys: [SharedPassPasskeyItem],
        forRpId rpId: String?,
        allowedCredentialIds allowed: Set<String>
    ) -> [SharedPassPasskeyItem] {
        guard let rpId = rpId else { return [] }

        return passkeys.filter { passkey in
            passkey.rpId == rpId && (allowed.isEmpty || allowed.contains(passkey.credentialId))
        }
    }

    /// Case-insensitive search over name, userName, and rpId.
    static func passkeys(
        _ passkeys: [SharedPassPasskeyItem],
        matchingQuery query: String
    ) -> [SharedPassPasskeyItem] {
        guard !query.isEmpty else {
            return passkeys
        }

        let lowercasedQuery = query.lowercased()

        return passkeys.filter { passkey in
            passkey.name.lowercased().contains(lowercasedQuery) ||
            passkey.userName.lowercased().contains(lowercasedQuery) ||
            passkey.rpId.lowercased().contains(lowercasedQuery)
        }
    }

    /// Find a passkey by its raw credential ID bytes (stored IDs are base64url).
    static func passkey(
        in passkeys: [SharedPassPasskeyItem],
        credentialId: Data
    ) -> SharedPassPasskeyItem? {
        let credentialIdBase64URL = credentialId.base64URLEncodedString
        return passkeys.first { $0.credentialId == credentialIdBase64URL }
    }

    /// Vault passkeys plus pending-queue passkeys, deduped by credentialId
    /// (the vault copy wins — the queue may lag behind a completed merge).
    static func mergingPendingPasskeys(
        vault: [SharedPassPasskeyItem],
        pending: [SharedPassPasskeyItem]
    ) -> [SharedPassPasskeyItem] {
        let knownCredentialIds = Set(vault.map(\.credentialId))
        return vault + pending.filter { !knownCredentialIds.contains($0.credentialId) }
    }
}
```

Register it (Groo for tests + GrooAutoFill for the delegating call sites):

```bash
ruby scripts/register_shared_file.rb SharedCredentialMatcher.swift Groo GrooAutoFill
git diff --stat Groo.xcodeproj/project.pbxproj
grep -c "SharedCredentialMatcher.swift" Groo.xcodeproj/project.pbxproj
```

Expected: script prints `Groo: added`, `GrooAutoFill: added`, `OK: ...`; the grep count is **6** (2 PBXBuildFile + 1 PBXFileReference + 1 Shared-group child + 2 Sources entries). The pbxproj diff must be pure additions — if the gem rewrote unrelated sections, STOP and report.

- [ ] **Step 5: Delegate from AutoFillService and open the builders**

In `GrooAutoFill/AutoFillService.swift`:

(a) In `loadCredentials()`, replace the pending-merge block:

```swift
        // Merge passkeys created here but not yet synced into the vault by the main app
        do {
            let knownCredentialIds = Set(passkeys.map(\.credentialId))
            let pending = try SharedPendingItemsStore.load(key: key)
            passkeys.append(contentsOf: pending.filter { !knownCredentialIds.contains($0.credentialId) })
        } catch {
```

with:

```swift
        // Merge passkeys created here but not yet synced into the vault by the main app
        do {
            let pending = try SharedPendingItemsStore.load(key: key)
            passkeys = SharedCredentialMatcher.mergingPendingPasskeys(vault: passkeys, pending: pending)
        } catch {
```

(b) Replace the entire `// MARK: - Search` section (from `/// Filter credentials by service identifiers (domains)` through the end of `searchCredentials`, including the `domainsMatch` static) with:

```swift
    /// Filter credentials by service identifiers (domains)
    func filteredCredentials(for serviceIdentifiers: [ASCredentialServiceIdentifier]) -> [SharedPassPasswordItem] {
        // Extract domains from service identifiers; the matcher treats an
        // empty domain list as "no filter" (same as the previous early returns)
        let searchDomains = serviceIdentifiers.compactMap { identifier -> String? in
            switch identifier.type {
            case .domain:
                return identifier.identifier.lowercased()
            case .URL:
                guard let url = URL(string: identifier.identifier),
                      let host = url.host else {
                    return nil
                }
                return host.lowercased()
            @unknown default:
                return nil
            }
        }

        return SharedCredentialMatcher.credentials(credentials, matchingDomains: searchDomains)
    }

    /// Search credentials by query string
    func searchCredentials(query: String) -> [SharedPassPasswordItem] {
        SharedCredentialMatcher.credentials(credentials, matchingQuery: query)
    }
```

(c) Replace the three functions under `// MARK: - Passkey Methods` (`findPasskey`, `filteredPasskeys`, `searchPasskeys`) with:

```swift
    /// Find a passkey by its credential ID
    func findPasskey(credentialId: Data) -> SharedPassPasskeyItem? {
        SharedCredentialMatcher.passkey(in: passkeys, credentialId: credentialId)
    }

    /// Filter passkeys by relying party ID and the request's allowed credential list
    func filteredPasskeys(for rpId: String?, allowedCredentialIds: [Data] = []) -> [SharedPassPasskeyItem] {
        SharedCredentialMatcher.passkeys(
            passkeys,
            forRpId: rpId,
            allowedCredentialIds: Set(allowedCredentialIds.map { $0.base64URLEncodedString })
        )
    }

    /// Search passkeys by query string
    func searchPasskeys(query: String) -> [SharedPassPasskeyItem] {
        SharedCredentialMatcher.passkeys(passkeys, matchingQuery: query)
    }
```

In `Groo/Features/Pass/CredentialIdentityService.swift`, drop `private` on the two builders (add the test note):

```swift
    /// Build password credential identities from vault items.
    /// Internal (not private) so GrooTests can pin the payload building.
    func buildPasswordIdentities(from items: [PassVaultItem]) -> [ASPasswordCredentialIdentity] {
```

```swift
    /// Build passkey credential identities from vault items (iOS 17+).
    /// Internal (not private) so GrooTests can pin the payload building.
    @available(iOS 17.0, *)
    func buildPasskeyIdentities(from items: [PassVaultItem]) -> [ASPasskeyCredentialIdentity] {
```

- [ ] **Step 6: Run to verify pass**

Run: `bash scripts/test.sh --unit 2>&1 | tail -5`
Expected: PASS — **213 tests** (198 + 15).

Verify all targets build (compiles the modified GrooAutoFill): `xcodebuild build -project Groo.xcodeproj -scheme Groo -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -3` → `** BUILD SUCCEEDED **`

Manual smoke (behavior-preservation for the extraction): in Safari on the simulator, focus a login field → Groo AutoFill still lists/filters credentials for the site after unlock.

- [ ] **Step 7: Commit**

```bash
git add Shared/SharedCredentialMatcher.swift GrooAutoFill/AutoFillService.swift Groo/Features/Pass/CredentialIdentityService.swift scripts/register_shared_file.rb Groo.xcodeproj/project.pbxproj GrooTests
git commit -m "refactor: extract AutoFill matching into Shared/SharedCredentialMatcher; test: matcher + credential-identity payload suites"
```

---

### Task 3: SharedPendingItemsStore fileURL seam + queue tests; SharedConfig/Config override tests

**Files:**
- Modify: `Shared/SharedPendingItemsStore.swift` (full-file replacement below)
- Modify: `Groo/Core/Config.swift:16-26` (`overrideURL` seam)
- Test: `GrooTests/Shared/SharedPendingItemsStoreTests.swift`
- Test: `GrooTests/Shared/SharedConfigTests.swift`
- Test: `GrooTests/Core/ConfigTests.swift`

**Interfaces:**
- Consumes: `SharedPassPasskeyItem` explicit init, `SymmetricKey`, `SharedCryptoError`.
- Produces: `SharedPendingItemsStore.load(key:fileURL:)`/`append(_:key:fileURL:)`/`clear(fileURL:)` with `defaultFileURL` (the App Group path) as default — `AutoFillService.savePendingPasskey`, `AutoFillService.loadCredentials`, and `PassService.mergePendingPasskeys` call sites compile unchanged. `Config.overrideURL(forKey:in:)` with `.standard` default — the five internal call sites compile unchanged.

- [ ] **Step 1: Write the failing tests**

`GrooTests/Shared/SharedPendingItemsStoreTests.swift`:

```swift
//
//  SharedPendingItemsStoreTests.swift
//  GrooTests
//
//  Pending-passkey queue semantics against a temp-directory file: roundtrips,
//  wrong-key rejection (never "empty"), corrupt-queue move-aside, clear.
//  The real App Group file is never touched (explicit fileURL every call).
//

import CryptoKit
import Foundation
import Testing
@testable import Groo

struct SharedPendingItemsStoreTests {
    static func tempQueueURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("pending-items-tests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("pending_passkeys.enc")
    }

    static func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }

    static func makePasskey(id: String = "pk-1", credentialId: String = "Y3JlZC1pZA") -> SharedPassPasskeyItem {
        SharedPassPasskeyItem(
            id: id, name: "example.com", rpId: "example.com", rpName: "example.com",
            credentialId: credentialId, publicKey: "cHVi", privateKey: "cHJpdg==",
            userHandle: "dXNlcg", userName: "user@example.com"
        )
    }

    @Test func missingQueueFileLoadsEmpty() throws {
        let url = Self.tempQueueURL()
        defer { Self.cleanup(url) }

        #expect(try SharedPendingItemsStore.load(key: SymmetricKey(size: .bits256), fileURL: url).isEmpty)
    }

    @Test func appendThenLoadRoundtripsAllFields() throws {
        let url = Self.tempQueueURL()
        defer { Self.cleanup(url) }
        let key = SymmetricKey(size: .bits256)

        try SharedPendingItemsStore.append(Self.makePasskey(), key: key, fileURL: url)
        let loaded = try SharedPendingItemsStore.load(key: key, fileURL: url)

        try #require(loaded.count == 1)
        #expect(loaded[0].id == "pk-1")
        #expect(loaded[0].rpId == "example.com")
        #expect(loaded[0].credentialId == "Y3JlZC1pZA")
        #expect(loaded[0].privateKey == "cHJpdg==")   // the unsynced private key survives
        #expect(loaded[0].signCount == 0)
    }

    @Test func appendAccumulatesInOrder() throws {
        let url = Self.tempQueueURL()
        defer { Self.cleanup(url) }
        let key = SymmetricKey(size: .bits256)

        try SharedPendingItemsStore.append(Self.makePasskey(id: "pk-1", credentialId: "aWQtMQ"), key: key, fileURL: url)
        try SharedPendingItemsStore.append(Self.makePasskey(id: "pk-2", credentialId: "aWQtMg"), key: key, fileURL: url)

        #expect(try SharedPendingItemsStore.load(key: key, fileURL: url).map(\.id) == ["pk-1", "pk-2"])
    }

    @Test func wrongKeyThrowsUnreadableNeverEmpty() throws {
        let url = Self.tempQueueURL()
        defer { Self.cleanup(url) }
        try SharedPendingItemsStore.append(Self.makePasskey(), key: SymmetricKey(size: .bits256), fileURL: url)

        // An unreadable queue must never be mistaken for an empty one — the
        // caller (PassService) keeps the file for a retry with the right key
        #expect {
            _ = try SharedPendingItemsStore.load(key: SymmetricKey(size: .bits256), fileURL: url)
        } throws: { error in
            guard case SharedPendingItemsStoreError.unreadable = error else { return false }
            return true
        }
    }

    @Test func appendMovesUnreadableQueueAsideAndStartsFresh() throws {
        let url = Self.tempQueueURL()
        defer { Self.cleanup(url) }
        let key = SymmetricKey(size: .bits256)
        let garbage = Data("not an AES-GCM box".utf8)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try garbage.write(to: url)

        try SharedPendingItemsStore.append(Self.makePasskey(), key: key, fileURL: url)

        // Fresh queue holds only the new item…
        #expect(try SharedPendingItemsStore.load(key: key, fileURL: url).map(\.id) == ["pk-1"])
        // …and the unreadable original (which may hold unsynced private keys)
        // was moved aside, not destroyed
        let backup = url.appendingPathExtension("corrupt")
        #expect(try Data(contentsOf: backup) == garbage)
    }

    @Test func clearRemovesQueue() throws {
        let url = Self.tempQueueURL()
        defer { Self.cleanup(url) }
        let key = SymmetricKey(size: .bits256)
        try SharedPendingItemsStore.append(Self.makePasskey(), key: key, fileURL: url)

        SharedPendingItemsStore.clear(fileURL: url)

        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(try SharedPendingItemsStore.load(key: key, fileURL: url).isEmpty)
    }

    @Test func nilFileURLThrowsContainerNotAvailable() {
        // Mirrors an extension running with a broken App Group entitlement
        #expect {
            _ = try SharedPendingItemsStore.load(key: SymmetricKey(size: .bits256), fileURL: nil)
        } throws: { error in
            guard case SharedPendingItemsStoreError.containerNotAvailable = error else { return false }
            return true
        }
    }
}
```

`GrooTests/Shared/SharedConfigTests.swift`:

```swift
//
//  SharedConfigTests.swift
//  GrooTests
//
//  Pins the compile-time identifiers the app and extensions must agree on.
//  A silent typo here would disconnect app↔extension data sharing (vault,
//  pending passkeys, keychain) without any error. Test builds are Debug, so
//  the .debug variants are the pinned values.
//

import Testing
@testable import Groo

struct SharedConfigTests {
    @Test func debugIdentifiersArePinned() {
        #expect(SharedConfig.appGroupIdentifier == "group.dev.groo.ios.debug")
        #expect(SharedConfig.keychainService == "dev.groo.ios.debug")
        #expect(SharedConfig.KeychainKey.passEncryptionKey == "pass_encryption_key")
        #expect(SharedConfig.KeychainKey.passSalt == "pass_salt")
    }

    @Test func sharedAndAppConfigAgree() {
        // Config (app) and SharedConfig (app + AutoFill) must never drift —
        // they address the same keychain and App Group container.
        // (ExtensionConfig in Widget/Keyboard cannot be compile-checked from
        // tests; see the phase plan's spec-coverage notes.)
        #expect(SharedConfig.appGroupIdentifier == Config.appGroupIdentifier)
        #expect(SharedConfig.keychainService == Config.keychainService)
    }
}
```

`GrooTests/Core/ConfigTests.swift`:

```swift
//
//  ConfigTests.swift
//  GrooTests
//
//  UserDefaults override resolution for API base URLs, driven through a
//  suite-named UserDefaults (never .standard). The invalid-override branch
//  calls assertionFailure and is untestable in a Debug test host by design.
//

import Foundation
import Testing
@testable import Groo

struct ConfigTests {
    @Test func presentValidOverrideWins() throws {
        let suiteName = "config-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("https://pad.override.test:9999", forKey: "padAPIBaseURL")

        let url = Config.overrideURL(forKey: "padAPIBaseURL", in: defaults)

        #expect(url == URL(string: "https://pad.override.test:9999"))
    }

    @Test func absentOverrideFallsThroughToNil() throws {
        let suiteName = "config-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        #expect(Config.overrideURL(forKey: "padAPIBaseURL", in: defaults) == nil)
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `bash scripts/test.sh --unit 2>&1 | tail -20`
Expected: BUILD FAILURE — `load(key:fileURL:)` has no `fileURL` parameter; `Config.overrideURL` is private / has no `in` parameter.

- [ ] **Step 3: Add the seams**

Replace the entire contents of `Shared/SharedPendingItemsStore.swift` with:

```swift
//
//  SharedPendingItemsStore.swift
//  Groo
//
//  Queue for passkeys created by the AutoFill extension.
//  The extension can't push to the Pass server, so new passkeys are stored
//  here (encrypted with the vault key) until the main app merges them into
//  the vault and syncs.
//

import CryptoKit
import Foundation
import os

enum SharedPendingItemsStoreError: Error {
    case containerNotAvailable
    case unreadable(Error)
}

enum SharedPendingItemsStore {
    /// Production queue location inside the App Group container. Tests pass
    /// an explicit temp-directory URL instead of touching this file.
    static var defaultFileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: SharedConfig.appGroupIdentifier)?
            .appendingPathComponent("pass", isDirectory: true)
            .appendingPathComponent("pending_passkeys.enc")
    }

    /// Load pending passkeys. Returns [] only when no queue file exists.
    /// Throws `.unreadable` when the file exists but can't be decrypted/decoded —
    /// callers must NOT treat that as an empty queue.
    static func load(
        key: SymmetricKey,
        fileURL: URL? = SharedPendingItemsStore.defaultFileURL
    ) throws -> [SharedPassPasskeyItem] {
        guard let url = fileURL else {
            throw SharedPendingItemsStoreError.containerNotAvailable
        }
        guard FileManager.default.fileExists(atPath: url.path) else {
            return []
        }

        do {
            let combined = try Data(contentsOf: url)
            let sealedBox = try AES.GCM.SealedBox(combined: combined)
            let decrypted = try AES.GCM.open(sealedBox, using: key)
            return try JSONDecoder().decode([SharedPassPasskeyItem].self, from: decrypted)
        } catch {
            Log.autofill.error("Pending passkey queue exists but is unreadable: \(String(describing: error), privacy: .public)")
            throw SharedPendingItemsStoreError.unreadable(error)
        }
    }

    /// Append a passkey to the pending queue
    static func append(
        _ item: SharedPassPasskeyItem,
        key: SymmetricKey,
        fileURL: URL? = SharedPendingItemsStore.defaultFileURL
    ) throws {
        guard let url = fileURL else {
            throw SharedPendingItemsStoreError.containerNotAvailable
        }

        var items: [SharedPassPasskeyItem]
        do {
            items = try load(key: key, fileURL: url)
        } catch SharedPendingItemsStoreError.unreadable {
            // Never overwrite an unreadable queue — it may hold unsynced passkey
            // private keys. Move it aside so it stays recoverable on disk.
            let backup = url.appendingPathExtension("corrupt")
            try? FileManager.default.removeItem(at: backup)
            try FileManager.default.moveItem(at: url, to: backup)
            Log.autofill.fault("Moved unreadable pending passkey queue aside to \(backup.lastPathComponent, privacy: .public)")
            items = []
        }
        items.append(item)

        let data = try JSONEncoder().encode(items)
        let sealed = try AES.GCM.seal(data, using: key)
        guard let combined = sealed.combined else {
            throw SharedCryptoError.decryptionFailed
        }

        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try combined.write(to: url, options: .atomic)
    }

    /// Remove the pending queue (after the main app has merged it)
    static func clear(fileURL: URL? = SharedPendingItemsStore.defaultFileURL) {
        guard let url = fileURL, FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            Log.autofill.error("Failed to clear pending passkey queue: \(String(describing: error), privacy: .public)")
        }
    }
}
```

In `Groo/Core/Config.swift`, replace the `overrideURL` function (lines 13–26, keeping the doc comment's intent) with:

```swift
    /// Resolve a UserDefaults URL override. A present-but-unparseable override
    /// is a dev configuration error: log it and assert instead of silently
    /// falling through to the default URL. `defaults` is injectable so tests
    /// drive resolution with a suite-named UserDefaults, never `.standard`.
    static func overrideURL(forKey key: String, in defaults: UserDefaults = .standard) -> URL? {
        guard let override = defaults.string(forKey: key) else {
            return nil
        }
        guard let url = URL(string: override) else {
            Log.network.error("Invalid \(key, privacy: .public) override \"\(override, privacy: .public)\"; falling back to default")
            assertionFailure("Invalid \(key) override: \(override)")
            return nil
        }
        return url
    }
```

- [ ] **Step 4: Run to verify pass**

Run: `bash scripts/test.sh --unit 2>&1 | tail -5`
Expected: PASS — **224 tests** (213 + 11).

Verify the app still builds: `xcodebuild build -project Groo.xcodeproj -scheme Groo -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -3` → `** BUILD SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add Shared/SharedPendingItemsStore.swift Groo/Core/Config.swift GrooTests
git commit -m "test: SharedPendingItemsStore queue semantics via fileURL seam; SharedConfig pins + Config override resolution"
```

---

### Task 4: Widget/Keyboard Pad decryption → `Shared/SharedPadCrypto`

**Files:**
- Create: `Shared/SharedPadCrypto.swift` (+ pbxproj registration to Groo, WidgetExtensionExtension, KeyboardExtension)
- Modify: `WidgetExtension/ExtensionHelper.swift` and `KeyboardExtension/ExtensionHelper.swift` (identical edit — the files must stay byte-identical to each other)
- Test: `GrooTests/Shared/SharedPadCryptoTests.swift`

**Interfaces:**
- Consumes: `CryptoService` (test-side, for the cross-implementation contract), `CryptoKit`.
- Produces: `SharedPadCrypto.EncryptedPayload`, `SharedPadCrypto.DecryptError`, `SharedPadCrypto.decrypt(_:using:)` — the moved-verbatim `ExtensionCrypto` body. Both `ExtensionHelper.swift` copies keep compiling via `typealias ExtensionCrypto = SharedPadCrypto` (call sites `ExtensionCrypto.EncryptedPayload`/`.decrypt`/`.DecryptError` unchanged).
- pbxproj: registered to **Groo** (test reachability), **WidgetExtensionExtension**, and **KeyboardExtension** (the exact target names in the pbxproj). NOT registered to GrooAutoFill/ShareExtension — they don't use it.

**Why this is the extraction worth doing:** `ExtensionCrypto.decrypt` is a second, hand-rolled implementation of the AES-GCM payload format that `CryptoService.encrypt` produces (base64 "ciphertext+tag" split at the last 16 bytes + separate base64 IV), duplicated byte-identically in two extension targets. If either side of that format contract drifts, widgets/keyboard silently show nothing. The test encrypts with the app's `CryptoService` and decrypts with the extensions' code path.

- [ ] **Step 1: Write the failing tests**

`GrooTests/Shared/SharedPadCryptoTests.swift`:

```swift
//
//  SharedPadCryptoTests.swift
//  GrooTests
//
//  The app↔extension crypto contract: payloads encrypted by the app's
//  CryptoService must decrypt through SharedPadCrypto (the Widget/Keyboard
//  code path), and tampering/wrong keys must fail loudly.
//

import CryptoKit
import Foundation
import Testing
@testable import Groo

struct SharedPadCryptoTests {
    static func payload(from encrypted: EncryptedPayload) -> SharedPadCrypto.EncryptedPayload {
        SharedPadCrypto.EncryptedPayload(
            ciphertext: encrypted.ciphertext,
            iv: encrypted.iv,
            version: encrypted.version
        )
    }

    @Test func decryptsPayloadsProducedByCryptoService() throws {
        let key = SymmetricKey(size: .bits256)
        let plaintext = "Pad item — سلام 👋 with unicode"

        let encrypted = try CryptoService().encrypt(plaintext, using: key)
        let decrypted = try SharedPadCrypto.decrypt(Self.payload(from: encrypted), using: key)

        #expect(decrypted == plaintext)
    }

    @Test func emptyPlaintextRoundtrips() throws {
        let key = SymmetricKey(size: .bits256)
        let encrypted = try CryptoService().encrypt("", using: key)
        #expect(try SharedPadCrypto.decrypt(Self.payload(from: encrypted), using: key) == "")
    }

    @Test func wrongKeyFailsLoudly() throws {
        let encrypted = try CryptoService().encrypt("secret", using: SymmetricKey(size: .bits256))

        #expect(throws: (any Error).self) {
            _ = try SharedPadCrypto.decrypt(Self.payload(from: encrypted), using: SymmetricKey(size: .bits256))
        }
    }

    @Test func tamperedCiphertextFailsLoudly() throws {
        let key = SymmetricKey(size: .bits256)
        let encrypted = try CryptoService().encrypt("secret", using: key)

        var bytes = try #require(Data(base64Encoded: encrypted.ciphertext))
        bytes[0] ^= 0xFF
        let tampered = SharedPadCrypto.EncryptedPayload(
            ciphertext: bytes.base64EncodedString(), iv: encrypted.iv, version: encrypted.version
        )

        #expect(throws: (any Error).self) {
            _ = try SharedPadCrypto.decrypt(tampered, using: key)
        }
    }

    @Test func malformedBase64ThrowsMalformedPayload() {
        let bad = SharedPadCrypto.EncryptedPayload(ciphertext: "%%%not-base64%%%", iv: "also bad", version: 1)

        #expect {
            _ = try SharedPadCrypto.decrypt(bad, using: SymmetricKey(size: .bits256))
        } throws: { error in
            guard case SharedPadCrypto.DecryptError.malformedPayload = error else { return false }
            return true
        }
    }

    @Test func truncatedCiphertextFailsLoudly() throws {
        // Shorter than one GCM tag — must throw, never return garbage
        let key = SymmetricKey(size: .bits256)
        let iv = try CryptoService().encrypt("x", using: key).iv
        let truncated = SharedPadCrypto.EncryptedPayload(
            ciphertext: Data([0x01, 0x02]).base64EncodedString(), iv: iv, version: 1
        )

        #expect(throws: (any Error).self) {
            _ = try SharedPadCrypto.decrypt(truncated, using: key)
        }
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `bash scripts/test.sh --unit 2>&1 | tail -20`
Expected: BUILD FAILURE — `SharedPadCrypto` not found.

- [ ] **Step 3: Create the Shared file, register, and delegate**

`Shared/SharedPadCrypto.swift`:

```swift
//
//  SharedPadCrypto.swift
//  Groo
//
//  AES-256-GCM decryption for Pad payloads: base64 "ciphertext+tag" with a
//  separate base64 IV — exactly the format CryptoService.encrypt produces.
//  Compiled into the app (for tests) and the Widget/Keyboard extensions,
//  which previously carried duplicate copies inside ExtensionHelper.swift.
//

import CryptoKit
import Foundation

enum SharedPadCrypto {
    struct EncryptedPayload: Codable {
        let ciphertext: String
        let iv: String
        let version: Int
    }

    enum DecryptError: Error {
        case malformedPayload
        case invalidUTF8
    }

    /// Decrypt text using AES-256-GCM
    static func decrypt(_ payload: EncryptedPayload, using key: SymmetricKey) throws -> String {
        guard let ciphertextData = Data(base64Encoded: payload.ciphertext),
              let ivData = Data(base64Encoded: payload.iv) else {
            throw DecryptError.malformedPayload
        }

        let nonce = try AES.GCM.Nonce(data: ivData)
        let sealedBox = try AES.GCM.SealedBox(nonce: nonce, ciphertext: ciphertextData.dropLast(16), tag: ciphertextData.suffix(16))
        let decryptedData = try AES.GCM.open(sealedBox, using: key)
        guard let text = String(data: decryptedData, encoding: .utf8) else {
            throw DecryptError.invalidUTF8
        }
        return text
    }
}
```

Register it:

```bash
ruby scripts/register_shared_file.rb SharedPadCrypto.swift Groo WidgetExtensionExtension KeyboardExtension
git diff --stat Groo.xcodeproj/project.pbxproj
grep -c "SharedPadCrypto.swift" Groo.xcodeproj/project.pbxproj
```

Expected: `Groo: added`, `WidgetExtensionExtension: added`, `KeyboardExtension: added`; grep count **8** (3 PBXBuildFile + 1 PBXFileReference + 1 group child + 3 Sources entries); pure-addition diff.

Then, in **both** `WidgetExtension/ExtensionHelper.swift` and `KeyboardExtension/ExtensionHelper.swift`, replace the entire `enum ExtensionCrypto { ... }` block (everything from `enum ExtensionCrypto {` through its closing `}` under `// MARK: - Crypto Helper`) with:

```swift
// Pad-payload decryption now lives in Shared/SharedPadCrypto.swift (compiled
// into this extension target); the alias keeps this file's call sites — and
// the byte-identical Widget/Keyboard copies — unchanged.
typealias ExtensionCrypto = SharedPadCrypto
```

Verify the two copies are still byte-identical:

```bash
diff WidgetExtension/ExtensionHelper.swift KeyboardExtension/ExtensionHelper.swift && echo IDENTICAL
```

Expected: `IDENTICAL`.

- [ ] **Step 4: Run to verify pass**

Run: `bash scripts/test.sh --unit 2>&1 | tail -5`
Expected: PASS — **230 tests** (224 + 6).

Verify all targets build (compiles both modified extensions): `xcodebuild build -project Groo.xcodeproj -scheme Groo -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -3` → `** BUILD SUCCEEDED **`

Manual smoke: add the Pad widget to the simulator home screen (or long-press an existing one → it re-renders) — items still decrypt after unlocking Pad in the app.

- [ ] **Step 5: Commit**

```bash
git add Shared/SharedPadCrypto.swift WidgetExtension/ExtensionHelper.swift KeyboardExtension/ExtensionHelper.swift Groo.xcodeproj/project.pbxproj GrooTests
git commit -m "refactor: extract Pad payload decryption into Shared/SharedPadCrypto (Widget/Keyboard); test: app-extension crypto format contract"
```

---

### Task 5: Stocks — cost-basis math, portfolio manager (store seam), Yahoo parsing (cache seam)

**Files:**
- Modify: `Groo/Features/Stocks/Services/StockPortfolioManager.swift` (store seam)
- Modify: `Groo/Features/Stocks/Services/YahooFinanceService.swift:12-25` (cache seam)
- Test: `GrooTests/Features/Stocks/StockModelsTests.swift`
- Test: `GrooTests/Features/Stocks/StockPortfolioManagerTests.swift`
- Test: `GrooTests/Features/Stocks/YahooFinanceServiceTests.swift`

**Interfaces:**
- Consumes: `StockHolding`/`StockTransaction`/`StockQuote`/`StockSearchResult` (StockModels.swift), `LocalStockHolding`/`LocalStockTransaction` inits, `InMemoryLocalStore`, `APICache(sessionConfiguration:)` (Phase 2/3 seam), `StubURLProtocol`, `YahooFinanceError`.
- Produces: `StockPortfolioManager(store:)` (+ `exportJSON(store:)`/`importJSON(_:store:)`), `YahooFinanceService(cache:)`.

**Notes:**
- `StockPortfolioManager.displayCurrency` reads/writes `UserDefaults.standard` — no test touches it or asserts anything derived from it (`totalValue`/`totalCostBasis`/`exchangeRate(for:)` are environment-dependent through it; the underlying per-holding math is pinned in `StockModelsTests` instead). Flag the `.standard` coupling as a seam candidate in the final report.
- The Yahoo 429-retry path uses real `Task.sleep` — deliberately untested (no-sleeps rule).
- Float assertions use exactly-representable fixtures (dyadic fractions) so `==` is safe; anything else uses an explicit tolerance.

- [ ] **Step 1: Write the failing tests**

`GrooTests/Features/Stocks/StockModelsTests.swift`:

```swift
//
//  StockModelsTests.swift
//  GrooTests
//
//  Cost-basis math on StockHolding/StockTransaction — pure, no store, no
//  network. Fixtures use dyadic values so Double == comparisons are exact.
//

import Foundation
import Testing
@testable import Groo

struct StockModelsTests {
    static func tx(_ type: TransactionType, shares: Double, totalCost: Double) -> StockTransaction {
        StockTransaction(id: UUID().uuidString, type: type, shares: shares, totalCost: totalCost, date: Date(timeIntervalSince1970: 1_700_000_000))
    }

    static func holding(
        price: Double = 0,
        previousClose: Double = 0,
        transactions: [StockTransaction] = []
    ) -> StockHolding {
        StockHolding(
            symbol: "AAPL", companyName: "Apple", exchange: "NMS", currency: "USD",
            currentPrice: price, changePercent: 0, previousClose: previousClose,
            transactions: transactions
        )
    }

    @Test func netSharesAndInvestedAreNetOfSells() {
        let holding = Self.holding(transactions: [
            Self.tx(.buy, shares: 8, totalCost: 800),
            Self.tx(.buy, shares: 4, totalCost: 500),
            Self.tx(.sell, shares: 2, totalCost: 300),
        ])

        #expect(holding.netShares == 10)          // 12 bought - 2 sold
        #expect(holding.totalInvested == 1000)    // 1300 spent - 300 proceeds
    }

    @Test func currentValueAndGainLossFollowNetShares() {
        let holding = Self.holding(price: 150, transactions: [Self.tx(.buy, shares: 4, totalCost: 400)])

        #expect(holding.currentValue == 600)
        #expect(holding.totalGainLoss == 200)
        #expect(holding.totalGainLossPercent == 50)
    }

    @Test func watchlistOnlyHoldingHasNilGainLoss() {
        let holding = Self.holding(price: 150)

        #expect(!holding.hasTransactions)
        #expect(holding.totalGainLoss == nil)
        #expect(holding.totalGainLossPercent == nil)
        #expect(holding.dayGainLoss == nil)
    }

    @Test func gainLossPercentGuardsZeroCostBasis() {
        // Fully recouped position: invested 0 net — percent must be nil, not ∞
        let holding = Self.holding(price: 100, transactions: [
            Self.tx(.buy, shares: 4, totalCost: 400),
            Self.tx(.sell, shares: 2, totalCost: 400),
        ])

        #expect(holding.totalInvested == 0)
        #expect(holding.totalGainLossPercent == nil)
    }

    @Test func dayGainLossRequiresPreviousClose() {
        let withClose = Self.holding(price: 110, previousClose: 100, transactions: [Self.tx(.buy, shares: 2, totalCost: 200)])
        #expect(withClose.dayGainLoss == 20)

        let withoutClose = Self.holding(price: 110, previousClose: 0, transactions: [Self.tx(.buy, shares: 2, totalCost: 200)])
        #expect(withoutClose.dayGainLoss == nil)
    }

    @Test func costPerShareGuardsZeroShares() {
        #expect(Self.tx(.buy, shares: 4, totalCost: 500).costPerShare == 125)
        #expect(Self.tx(.buy, shares: 0, totalCost: 500).costPerShare == 0)
    }
}
```

`GrooTests/Features/Stocks/StockPortfolioManagerTests.swift`:

```swift
//
//  StockPortfolioManagerTests.swift
//  GrooTests
//
//  CRUD + load/sort semantics over an in-memory LocalStore. No network:
//  refreshPrices/exchange-rate flows depend on UserDefaults.standard-backed
//  displayCurrency and are deliberately out of scope (see phase plan).
//

import Foundation
import Testing
@testable import Groo

@MainActor
struct StockPortfolioManagerTests {
    static func makeManager() throws -> (manager: StockPortfolioManager, store: LocalStore) {
        let store = try InMemoryLocalStore.make()
        return (StockPortfolioManager(store: store), store)
    }

    @Test func addHoldingUppercasesAndDeduplicates() throws {
        let (manager, store) = try Self.makeManager()

        manager.addHolding(symbol: "aapl", companyName: "Apple", exchange: "NMS")
        manager.addHolding(symbol: "AAPL", companyName: "Apple Again", exchange: "NMS")

        #expect(manager.holdings.map(\.symbol) == ["AAPL"])
        #expect(store.getStockHolding(symbol: "AAPL")?.companyName == "Apple")   // first write wins
    }

    @Test func unknownTransactionTypesAreSkippedNotGarbage() throws {
        let (manager, store) = try Self.makeManager()
        manager.addHolding(symbol: "AAPL", companyName: "Apple", exchange: "NMS")
        manager.addTransaction(to: "AAPL", type: .buy, shares: 2, totalCost: 300, date: Date(timeIntervalSince1970: 1_700_000_000))

        // A future/unknown persisted type must not decode into a wrong enum case
        let local = try #require(store.getStockHolding(symbol: "AAPL"))
        local.transactions.append(LocalStockTransaction(type: "transfer", shares: 1, totalCost: 100, holding: local))
        store.saveStockChanges()
        manager.loadCachedHoldings()

        let holding = try #require(manager.holdings.first)
        #expect(holding.transactions.count == 1)
        #expect(holding.transactions.first?.type == .buy)
    }

    @Test func sortPutsTransactedHoldingsByValueThenWatchlistAlphabetically() throws {
        let (manager, store) = try Self.makeManager()
        for symbol in ["ZZZ", "AAA", "BBB", "MMM"] {
            manager.addHolding(symbol: symbol, companyName: symbol, exchange: "X")
        }
        manager.addTransaction(to: "AAA", type: .buy, shares: 1, totalCost: 100, date: Date(timeIntervalSince1970: 1_700_000_000))
        manager.addTransaction(to: "BBB", type: .buy, shares: 1, totalCost: 100, date: Date(timeIntervalSince1970: 1_700_000_000))
        try #require(store.getStockHolding(symbol: "AAA")).cachedPrice = 100
        try #require(store.getStockHolding(symbol: "BBB")).cachedPrice = 500
        store.saveStockChanges()

        manager.loadCachedHoldings()

        // Transacted first (value desc), then watchlist-only (symbol asc)
        #expect(manager.holdings.map(\.symbol) == ["BBB", "AAA", "MMM", "ZZZ"])
    }

    @Test func addTransactionToUnknownSymbolSurfacesError() throws {
        let (manager, _) = try Self.makeManager()

        manager.addTransaction(to: "GHOST", type: .buy, shares: 1, totalCost: 100, date: Date())

        #expect(manager.error == "Could not save transaction — GHOST not found")
        #expect(manager.holdings.isEmpty)
    }

    @Test func updateAndDeleteTransactionPersist() throws {
        let (manager, store) = try Self.makeManager()
        manager.addHolding(symbol: "AAPL", companyName: "Apple", exchange: "NMS")
        manager.addTransaction(to: "AAPL", type: .buy, shares: 2, totalCost: 300, date: Date(timeIntervalSince1970: 1_700_000_000))
        let txId = try #require(store.getStockHolding(symbol: "AAPL")?.transactions.first?.id)

        manager.updateTransaction(id: txId, type: .sell, shares: 1, totalCost: 200, date: Date(timeIntervalSince1970: 1_700_000_100))
        var holding = try #require(manager.holdings.first)
        #expect(holding.transactions.first?.type == .sell)
        #expect(holding.transactions.first?.totalCost == 200)

        manager.deleteTransaction(id: txId)
        holding = try #require(manager.holdings.first)
        #expect(holding.transactions.isEmpty)
    }

    @Test func exportImportRoundtripsAndSkipsExistingHoldings() throws {
        let (source, sourceStore) = try Self.makeManager()
        source.addHolding(symbol: "AAPL", companyName: "Apple", exchange: "NMS")
        source.addTransaction(to: "AAPL", type: .buy, shares: 2, totalCost: 300, date: Date(timeIntervalSince1970: 1_700_000_000))

        let data = try StockPortfolioManager.exportJSON(store: sourceStore)

        let (_, freshStore) = try Self.makeManager()
        #expect(StockPortfolioManager.importJSON(data, store: freshStore) == 1)
        #expect(freshStore.getStockHolding(symbol: "AAPL")?.transactions.count == 1)
        // Second import: existing holdings are skipped, nothing duplicated
        #expect(StockPortfolioManager.importJSON(data, store: freshStore) == 0)
        #expect(freshStore.getStockHolding(symbol: "AAPL")?.transactions.count == 1)
    }
}
```

`GrooTests/Features/Stocks/YahooFinanceServiceTests.swift`:

```swift
//
//  YahooFinanceServiceTests.swift
//  GrooTests
//
//  Quote/search/exchange-rate parsing over a stubbed APICache session.
//  The 429 retry path uses real Task.sleep and is deliberately untested
//  (no-sleeps rule) — flagged in the phase plan.
//

import Foundation
import Testing
@testable import Groo

extension NetworkStubbedSuites {
@Suite(.serialized)
struct YahooFinanceServiceTests {
    static func makeService() -> YahooFinanceService {
        YahooFinanceService(cache: APICache(sessionConfiguration: StubURLProtocol.stubbedConfiguration()))
    }

    static func chartJSON(price: String, previousClose: String, currency: String = "USD") -> String {
        #"{"chart":{"result":[{"meta":{"regularMarketPrice":\#(price),"previousClose":\#(previousClose),"exchangeName":"NMS","symbol":"AAPL","currency":"\#(currency)"},"timestamp":null,"indicators":{"quote":[]}}],"error":null}}"#
    }

    @Test func quoteParsesPriceAndComputesChangePercent() async throws {
        StubURLProtocol.reset()
        // 150 vs 200 previous close → exactly -25% (dyadic, safe to ==)
        StubURLProtocol.enqueue(method: "GET", pathSuffix: "/chart/AAPL", json: Self.chartJSON(price: "150.0", previousClose: "200.0"))

        let quote = try await Self.makeService().getQuote(symbol: "aapl")

        #expect(quote.symbol == "AAPL")
        #expect(quote.price == 150)
        #expect(quote.previousClose == 200)
        #expect(quote.changePercent == -25)
        #expect(quote.currency == "USD")
        #expect(quote.exchange == "NMS")
    }

    @Test func missingPriceThrowsSymbolNotFound() async {
        StubURLProtocol.reset()
        StubURLProtocol.enqueue(method: "GET", pathSuffix: "/chart/AAPL", json: Self.chartJSON(price: "null", previousClose: "null"))

        await #expect {
            _ = try await Self.makeService().getQuote(symbol: "AAPL")
        } throws: { error in
            guard case YahooFinanceError.symbolNotFound = error else { return false }
            return true
        }
    }

    @Test func apiErrorDescriptionSurfaces() async {
        StubURLProtocol.reset()
        StubURLProtocol.enqueue(
            method: "GET", pathSuffix: "/chart/GHOST",
            json: #"{"chart":{"result":null,"error":{"code":"Not Found","description":"No data found"}}}"#
        )

        await #expect {
            _ = try await Self.makeService().getQuote(symbol: "GHOST")
        } throws: { error in
            guard case YahooFinanceError.apiError(let message) = error else { return false }
            return message == "No data found"
        }
    }

    @Test func malformedJsonSurfacesAsDecodingError() async {
        StubURLProtocol.reset()
        StubURLProtocol.enqueue(method: "GET", pathSuffix: "/chart/AAPL", json: "not json")

        await #expect {
            _ = try await Self.makeService().getQuote(symbol: "AAPL")
        } throws: { error in
            error is DecodingError
        }
    }

    @Test func getQuotesCollectsSuccessesAndDropsFailures() async {
        StubURLProtocol.reset()
        StubURLProtocol.enqueue(method: "GET", pathSuffix: "/chart/AAPL", json: Self.chartJSON(price: "150.0", previousClose: "200.0"))
        // MSFT is unstubbed → transport error → dropped, not propagated

        let quotes = await Self.makeService().getQuotes(symbols: ["AAPL", "MSFT"])

        #expect(Set(quotes.keys) == ["AAPL"])
        #expect(quotes["AAPL"]?.price == 150)
    }

    @Test func searchFiltersToEquitiesAndEtfsAndPrefersLongname() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.enqueue(
            method: "GET", pathSuffix: "/v1/finance/search",
            json: #"{"quotes":[{"symbol":"AAPL","shortname":"Apple","longname":"Apple Inc.","exchDisp":"NASDAQ","quoteType":"EQUITY"},{"symbol":"VOO","shortname":"Vanguard S&P 500","exchDisp":"NYSEArca","quoteType":"ETF"},{"symbol":"BTC-USD","shortname":"Bitcoin","quoteType":"CRYPTOCURRENCY"},{"shortname":"NoSymbol","quoteType":"EQUITY"}]}"#
        )

        let results = try await Self.makeService().search(query: "apple")

        #expect(results.map(\.symbol) == ["AAPL", "VOO"])
        #expect(results.first?.name == "Apple Inc.")        // longname preferred
        #expect(results.last?.name == "Vanguard S&P 500")   // shortname fallback
    }

    @Test func sameCurrencyExchangeRateShortCircuitsWithoutNetwork() async throws {
        StubURLProtocol.reset()

        let rate = try await Self.makeService().getExchangeRate(from: "usd", to: "USD")

        #expect(rate == 1.0)
        #expect(StubURLProtocol.recordedRequests.isEmpty)
    }

    @Test func exchangeRateUsesCurrencyPairChartSymbol() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.enqueue(method: "GET", pathSuffix: "/chart/JPYUSD=X", json: Self.chartJSON(price: "0.0068", previousClose: "0.0068"))

        let rate = try await Self.makeService().getExchangeRate(from: "jpy", to: "usd")

        #expect(rate == 0.0068)
        #expect(StubURLProtocol.recordedRequests.first?.url?.path.hasSuffix("/chart/JPYUSD=X") == true)
    }
}
}
```

- [ ] **Step 2: Run to verify failure**

Run: `bash scripts/test.sh --unit 2>&1 | tail -20`
Expected: BUILD FAILURE — `StockPortfolioManager` has no `init(store:)`/`exportJSON(store:)`; `YahooFinanceService` has no `cache` parameter.

- [ ] **Step 3: Add the seams**

In `Groo/Features/Stocks/Services/StockPortfolioManager.swift`:

(a) After the `private(set) var exchangeRates: [String: Double] = [:]` property, insert:

```swift
    private let store: LocalStore

    /// Testing seam: inject an in-memory LocalStore. Production callers keep
    /// using the shared App Group store.
    init(store: LocalStore = .shared) {
        self.store = store
    }
```

(b) Replace every `LocalStore.shared` in the **instance** methods (`loadCachedHoldings`, `refreshPrices`, `addHolding`, `addTransaction`, `updateTransaction`, `deleteTransaction`, `deleteHolding`) with `store`.

(c) Change the two static functions' signatures and bodies:

```swift
    static func exportJSON(store: LocalStore = .shared) throws -> Data {
        let stored = store.getAllStockHoldings()
```

```swift
    static func importJSON(_ data: Data, store: LocalStore = .shared) -> Int {
```

…and inside `importJSON`, replace the three `LocalStore.shared.` calls (`getStockHolding`, `saveStockHolding`, `saveStockChanges`) with `store.`.

Verify nothing was missed: `grep -n "LocalStore.shared" Groo/Features/Stocks/Services/StockPortfolioManager.swift` → no output.

In `Groo/Features/Stocks/Services/YahooFinanceService.swift`, replace the properties/init (lines 13–25):

```swift
    private let logger = Logger(subsystem: "dev.groo.ios", category: "YahooFinanceService")
    private let decoder: JSONDecoder
    private let cache: APICache

    private let chartBaseURL = URL(string: "https://query1.finance.yahoo.com/v8/finance/chart")!
    private let searchBaseURL = URL(string: "https://query1.finance.yahoo.com/v1/finance/search")!

    private let quoteTTL: TimeInterval = 60       // 1 minute
    private let chartTTL: TimeInterval = 300      // 5 minutes
    private let searchTTL: TimeInterval = 600     // 10 minutes

    /// Testing seam: inject an APICache over a stubbed session. Production
    /// callers share the process-wide cache.
    init(cache: APICache = .shared) {
        self.decoder = JSONDecoder()
        self.cache = cache
    }
```

…then replace the three `APICache.shared.fetch` call sites (`getQuote`, `getChartData`, `search`) with `self.cache.fetch` (keep the surrounding arguments identical; in `search`, `cache.fetch` without `self.` also compiles — use `self.cache.fetch` in the two closure bodies where `self.` is already required).

Verify: `grep -n "APICache.shared" Groo/Features/Stocks/Services/YahooFinanceService.swift` → no output.

- [ ] **Step 4: Run to verify pass**

Run: `bash scripts/test.sh --unit 2>&1 | tail -5`
Expected: PASS — **250 tests** (230 + 20).

Verify the app still builds: `xcodebuild build -project Groo.xcodeproj -scheme Groo -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -3` → `** BUILD SUCCEEDED **`

Manual smoke: open the Stocks tab — cached holdings load, pull-to-refresh updates prices.

- [ ] **Step 5: Commit**

```bash
git add Groo/Features/Stocks GrooTests
git commit -m "test: stock cost-basis math, portfolio manager CRUD (store seam), Yahoo quote parsing (cache seam)"
```

---

### Task 6: Azan — preferences/prayer-log persistence + tracking stats (clock seam)

**Files:**
- Modify: `Groo/Features/Azan/Services/PrayerTrackingService.swift:51-63` (store/now init) + 2 `Date()` call sites
- Test: `GrooTests/Features/Azan/AzanPreferencesTests.swift`
- Test: `GrooTests/Features/Azan/PrayerTrackingServiceTests.swift`

**Interfaces:**
- Consumes: `LocalAzanPreferences` (memberwise init with defaults), `PrayerLog`, `Prayer`/`PrayerStatus`/`Prayer.notifiable`, `LocalStore` azan/prayer-log CRUD, `InMemoryLocalStore`.
- Produces: `PrayerTrackingService.init(store:now:)` with `now: () -> Date = Date.init` — `PrayerTrackingService()`/`PrayerTrackingService(store:)` call sites compile unchanged.

**Notes:** All "today"-relative date strings in tests are computed from the same fixed `now` through the same `yyyy-MM-dd`/`en_US_POSIX` formatter + `Calendar.current` the service uses, so assertions are deterministic in any timezone. Non-dyadic percentages use a tolerance. `PrayerTimeService` (Adhan wrapper) is out of scope — see spec-coverage notes.

- [ ] **Step 1: Write the failing tests**

`GrooTests/Features/Azan/AzanPreferencesTests.swift`:

```swift
//
//  AzanPreferencesTests.swift
//  GrooTests
//
//  LocalAzanPreferences defaults/fallbacks/per-prayer accessors and the
//  single-row persistence contract through LocalStore, plus PrayerLog
//  upsert + raw-value fallbacks.
//

import Foundation
import SwiftData
import Testing
@testable import Groo

@MainActor
struct AzanPreferencesTests {
    @Test func defaultsPinProductChoices() {
        let prefs = LocalAzanPreferences()

        #expect(prefs.id == "default")
        #expect(prefs.parsedCalculationMethod == .muslimWorldLeague)
        #expect(prefs.parsedMadhab == .hanafi)
        #expect(prefs.showSunrise && !prefs.showSunset)
        #expect(prefs.jumuahReminderMinutes == 60)
        #expect(prefs.suhoorReminderMinutes == 30)
        #expect(prefs.hijriDateAdjustment == 0)
    }

    @Test func unknownRawValuesFallBackSafely() {
        let prefs = LocalAzanPreferences(calculationMethod: "bogus-method", madhab: "bogus-madhab")

        // A bad persisted string must degrade to defaults, never crash or
        // silently compute wrong times with a nil method
        #expect(prefs.parsedCalculationMethod == .muslimWorldLeague)
        #expect(prefs.parsedMadhab == .hanafi)
    }

    @Test func perPrayerAccessorsMapCorrectly() {
        let prefs = LocalAzanPreferences(
            showSunrise: false,
            sunriseNotification: true,
            ishaNotification: false,
            asrAdjustment: 7,
            ishaAdjustment: -3
        )

        #expect(prefs.isNotificationEnabled(for: .sunrise))
        #expect(!prefs.isNotificationEnabled(for: .isha))
        #expect(prefs.adjustment(for: .asr) == 7)
        #expect(prefs.adjustment(for: .isha) == -3)
        #expect(prefs.adjustment(for: .fajr) == 0)
        #expect(!prefs.isVisible(prayer: .sunrise))   // tracks showSunrise
        #expect(prefs.isVisible(prayer: .dhuhr))      // real prayers always visible
    }

    @Test func saveReplacesTheSingletonRow() throws {
        let store = try InMemoryLocalStore.make()
        store.saveAzanPreferences(LocalAzanPreferences(latitude: 21.42, longitude: 39.83, locationName: "Makkah"))

        store.saveAzanPreferences(LocalAzanPreferences(latitude: 24.47, longitude: 39.61, locationName: "Madinah"))

        let loaded = try #require(store.getAzanPreferences())
        #expect(loaded.locationName == "Madinah")
        #expect(loaded.latitude == 24.47)
        #expect(try store.context.fetchCount(FetchDescriptor<LocalAzanPreferences>()) == 1)
    }

    @Test func prayerLogUpsertsByDateAndPrayer() throws {
        let store = try InMemoryLocalStore.make()
        store.savePrayerLog(PrayerLog(dateString: "2026-07-01", prayer: .fajr, status: .onTime))
        store.savePrayerLog(PrayerLog(dateString: "2026-07-01", prayer: .fajr, status: .late))
        store.savePrayerLog(PrayerLog(dateString: "2026-07-02", prayer: .fajr, status: .onTime))

        let day1 = store.getPrayerLogs(forDateString: "2026-07-01")
        #expect(day1.count == 1)
        #expect(day1.first?.status == .late)   // second log replaced the first
        #expect(store.getPrayerLogs(from: "2026-07-01", to: "2026-07-02").count == 2)

        store.deletePrayerLog(dateString: "2026-07-01", prayer: .fajr)
        #expect(store.getPrayerLogs(forDateString: "2026-07-01").isEmpty)
    }

    @Test func prayerLogUnknownRawValuesFallBack() {
        let log = PrayerLog(dateString: "2026-07-01", prayer: .asr, status: .late)
        log.prayerRaw = "bogus"
        log.statusRaw = "bogus"

        #expect(log.prayer == .fajr)      // documented fallback
        #expect(log.status == .onTime)    // documented fallback
    }
}
```

`GrooTests/Features/Azan/PrayerTrackingServiceTests.swift`:

```swift
//
//  PrayerTrackingServiceTests.swift
//  GrooTests
//
//  Streaks, weekly grid, and stats over an in-memory LocalStore with an
//  injected fixed clock. Date strings are derived from the same fixed now
//  through the same formatter the service uses — timezone-independent.
//

import Foundation
import Testing
@testable import Groo

@MainActor
struct PrayerTrackingServiceTests {
    static let fixedNow = Date(timeIntervalSince1970: 1_751_700_000)   // 2025-07-05T07:20Z

    static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    static func dateString(daysAgo: Int) -> String {
        let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: fixedNow)!
        return formatter.string(from: date)
    }

    static func makeService() throws -> PrayerTrackingService {
        let store = try InMemoryLocalStore.make()
        return PrayerTrackingService(store: store, now: { Self.fixedNow })
    }

    static func logFullDay(_ service: PrayerTrackingService, daysAgo: Int, status: PrayerStatus = .onTime) {
        for prayer in Prayer.notifiable {
            service.logPrayer(dateString: Self.dateString(daysAgo: daysAgo), prayer: prayer, status: status)
        }
    }

    @Test func loggingUpdatesTodayCountsAndUpserts() throws {
        let service = try Self.makeService()

        service.logPrayer(dateString: Self.dateString(daysAgo: 0), prayer: .fajr, status: .onTime)
        service.logPrayer(dateString: Self.dateString(daysAgo: 0), prayer: .fajr, status: .late)
        service.logPrayer(dateString: Self.dateString(daysAgo: 0), prayer: .dhuhr, status: .onTime)

        #expect(service.todayCompletedCount == 2)          // fajr upserted, not duplicated
        #expect(service.todayLogs[.fajr] == .late)
        #expect(service.todayLogs[.dhuhr] == .onTime)
        #expect(service.todayDateString() == Self.dateString(daysAgo: 0))
    }

    @Test func incompleteTodayDoesNotBreakTheStreak() throws {
        let service = try Self.makeService()
        Self.logFullDay(service, daysAgo: 2)
        Self.logFullDay(service, daysAgo: 1)
        // Nothing logged today — the day isn't over yet

        #expect(service.currentStreak == 2)
    }

    @Test func fullTodayExtendsTheStreak() throws {
        let service = try Self.makeService()
        Self.logFullDay(service, daysAgo: 1)
        Self.logFullDay(service, daysAgo: 0)

        #expect(service.currentStreak == 2)
        #expect(service.bestStreak == 2)
    }

    @Test func gapBreaksCurrentStreakButBestRemembers() throws {
        let service = try Self.makeService()
        Self.logFullDay(service, daysAgo: 5)
        Self.logFullDay(service, daysAgo: 4)
        Self.logFullDay(service, daysAgo: 3)
        // daysAgo 2: gap
        Self.logFullDay(service, daysAgo: 1)

        #expect(service.currentStreak == 1)
        #expect(service.bestStreak == 3)
    }

    @Test func weeklyGridCoversSevenDaysOldestFirst() throws {
        let service = try Self.makeService()
        service.logPrayer(dateString: Self.dateString(daysAgo: 6), prayer: .asr, status: .late)
        service.logPrayer(dateString: Self.dateString(daysAgo: 0), prayer: .fajr, status: .onTime)
        service.logPrayer(dateString: Self.dateString(daysAgo: 0), prayer: .dhuhr, status: .onTime)

        try #require(service.weeklyGrid.count == 7)
        #expect(service.weeklyGrid.first?.dateString == Self.dateString(daysAgo: 6))
        #expect(service.weeklyGrid.first?.lateCount == 1)
        #expect(service.weeklyGrid.first?.completedCount == 1)
        #expect(service.weeklyGrid.last?.dateString == Self.dateString(daysAgo: 0))
        #expect(service.weeklyGrid.last?.onTimeCount == 2)
        #expect(service.weeklyGrid.last?.isFull == false)
    }

    @Test func removingALogRecalculates() throws {
        let service = try Self.makeService()
        Self.logFullDay(service, daysAgo: 0)
        #expect(service.todayCompletedCount == 5)

        service.removePrayerLog(dateString: Self.dateString(daysAgo: 0), prayer: .isha)

        #expect(service.todayCompletedCount == 4)
        #expect(service.todayLogs[.isha] == nil)
    }

    @Test func onTimeRateAndWeekPercentAggregate() throws {
        let service = try Self.makeService()
        // Today: 4 on-time + 1 late = 5 of 35 possible this week
        for prayer in [Prayer.fajr, .dhuhr, .asr, .maghrib] {
            service.logPrayer(dateString: Self.dateString(daysAgo: 0), prayer: prayer, status: .onTime)
        }
        service.logPrayer(dateString: Self.dateString(daysAgo: 0), prayer: .isha, status: .late)

        #expect(service.totalPrayersLogged == 5)
        #expect(abs(service.onTimeRate - 80.0) < 0.0001)                    // 4/5
        #expect(abs(service.thisWeekPercent - (5.0 / 35.0 * 100)) < 0.0001)
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `bash scripts/test.sh --unit 2>&1 | tail -20`
Expected: BUILD FAILURE — `PrayerTrackingService` has no `now` init parameter.

- [ ] **Step 3: Add the clock seam**

In `Groo/Features/Azan/Services/PrayerTrackingService.swift`, three surgical edits (the `dateFormatter` static between them is untouched):

(a) Replace the two stored-dependency lines:

```swift
    private let store: LocalStore
    private let trackablePrayers: [Prayer] = Prayer.notifiable
```

with:

```swift
    private let store: LocalStore
    private let now: () -> Date
    private let trackablePrayers: [Prayer] = Prayer.notifiable
```

(b) Replace the init:

```swift
    init(store: LocalStore = .shared) {
        self.store = store
    }
```

with:

```swift
    /// - Parameter now: injected clock (tests pass a fixed date so "today",
    ///   streak walks, and weekly grids are deterministic).
    init(store: LocalStore = .shared, now: @escaping () -> Date = Date.init) {
        self.store = store
        self.now = now
    }
```

(c) Update the two `Date()` call sites:

- In `recalculate()`: `let today = Self.dateFormatter.string(from: Date())` → `let today = Self.dateFormatter.string(from: now())`
- In `todayDateString()`: `Self.dateFormatter.string(from: Date())` → `Self.dateFormatter.string(from: now())`

(`PrayerLog.loggedAt`'s internal `Date()` is metadata, not read by any computation — leave it.)

- [ ] **Step 4: Run to verify pass**

Run: `bash scripts/test.sh --unit 2>&1 | tail -5`
Expected: PASS — **263 tests** (250 + 13).

Verify the app still builds: `xcodebuild build -project Groo.xcodeproj -scheme Groo -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -3` → `** BUILD SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add Groo/Features/Azan/Services/PrayerTrackingService.swift GrooTests
git commit -m "test: Azan preferences/prayer-log persistence + tracking stats via injected clock"
```

---

### Task 7: Pad & Scratchpad — PadService roundtrips (keychain seam), SyncService scratchpad CRUD, local-model fallbacks

**Files:**
- Modify: `Groo/Features/Pad/PadService.swift:44-54` (keychain protocol) + `unlockWithBiometric` (explicit prompt)
- Modify: `GrooTests/Support/StubURLProtocol.swift` (binary-body enqueue overload)
- Test: `GrooTests/Features/Pad/PadServiceTests.swift`
- Test: `GrooTests/Core/Sync/SyncServiceScratchpadTests.swift`
- Test: `GrooTests/Core/Storage/LocalPadModelsTests.swift`

**Interfaces:**
- Consumes: `InMemoryKeychain` (`KeychainServicing`), `InMemoryLocalStore`, `CryptoService` (encrypt/encryptData for fixtures), `APIClient(baseURL:sessionConfiguration:tokenProvider:)`, `SyncService(api:store:monitorsNetwork:)` (Phase 3 seams), `PadListItem`/`PadScratchpad`/`PadEncryptedPayload`/`DecryptedFileAttachment`, `LocalPadItem`/`LocalScratchpad`.
- Produces: `PadService.init(api:crypto:keychain:store:)` with `keychain: any KeychainServicing = KeychainService()` (was concrete `KeychainService` — mirrors PassService's Phase 1 widening); `StubURLProtocol.enqueue(method:pathSuffix:status:data:)`.

**Notes:**
- Unlocking in tests goes through `unlockWithBiometric()` against a pre-seeded `InMemoryKeychain` — no PBKDF2 derivation, no `/v1/state` stub needed for unlock.
- Widening the keychain type forces the `loadBiometricProtected` call to pass `prompt:` explicitly (protocols have no default arguments). The value passed is exactly `KeychainService`'s former default (`"Authenticate to access Pad"`) — behavior identical.
- `SyncService` scratchpad CRUD was explicitly deferred from Phase 3 ("the scratchpad CRUD passthroughs are Phase 4 territory").

- [ ] **Step 1: Write the failing tests + stub overload**

In `GrooTests/Support/StubURLProtocol.swift`, add after the existing `enqueue(method:pathSuffix:status:json:)`:

```swift
    /// Binary-body variant (e.g. encrypted file downloads).
    static func enqueue(method: String, pathSuffix: String, status: Int = 200, data: Data) {
        lock.lock(); defer { lock.unlock() }
        queues[key(method, pathSuffix), default: []].append(.success(status: status, body: data))
    }
```

`GrooTests/Features/Pad/PadServiceTests.swift`:

```swift
//
//  PadServiceTests.swift
//  GrooTests
//
//  Pad crypto lifecycle over an in-memory keychain + store: biometric-unlock
//  seam, encrypt→persist→decrypt roundtrips, loud decrypt-failure counting,
//  encrypted file upload/download over a stubbed API.
//

import CryptoKit
import Foundation
import Testing
@testable import Groo

extension NetworkStubbedSuites {
@MainActor
@Suite(.serialized)
struct PadServiceTests {
    struct Env {
        let service: PadService
        let store: LocalStore
        let keychain: InMemoryKeychain
        let key: SymmetricKey
    }

    static func makeUnlockedEnv() throws -> Env {
        let store = try InMemoryLocalStore.make()
        let keychain = InMemoryKeychain()
        let key = SymmetricKey(size: .bits256)
        try keychain.saveBiometricProtected(key.withUnsafeBytes { Data($0) }, for: KeychainService.Key.padEncryptionKey)
        let api = APIClient(
            baseURL: URL(string: "https://pad.test")!,
            sessionConfiguration: StubURLProtocol.stubbedConfiguration(),
            tokenProvider: { "pad-token" }
        )
        let service = PadService(api: api, keychain: keychain, store: store)
        #expect(try service.unlockWithBiometric())
        return Env(service: service, store: store, keychain: keychain, key: key)
    }

    @Test func biometricUnlockLoadsKeyFromKeychain() throws {
        StubURLProtocol.reset()
        let env = try Self.makeUnlockedEnv()

        #expect(env.service.isUnlocked)
        #expect(env.service.canUnlockWithBiometric)
    }

    @Test func lockKeepsBiometricKeyButClearRemovesIt() throws {
        StubURLProtocol.reset()
        let env = try Self.makeUnlockedEnv()

        env.service.lock()
        #expect(!env.service.isUnlocked)
        #expect(env.service.canUnlockWithBiometric)   // key stays for re-unlock

        env.service.lockAndClearKey()
        #expect(!env.service.canUnlockWithBiometric)  // full sign-out wipes it
    }

    @Test func createEncryptedItemRoundtripsThroughLocalStore() throws {
        StubURLProtocol.reset()
        let env = try Self.makeUnlockedEnv()

        let item = try env.service.createEncryptedItem(text: "buy milk 🥛")
        #expect(item.id.count == 8)                        // short lowercase id
        #expect(item.encryptedText.ciphertext != "buy milk 🥛")
        env.store.savePadItem(from: item)

        let decrypted = try env.service.getDecryptedItems()
        #expect(decrypted.map(\.text) == ["buy milk 🥛"])
        #expect(env.service.decryptFailureCount == 0)
    }

    @Test func decryptFailuresAreCountedNotSilentlyDropped() throws {
        StubURLProtocol.reset()
        let env = try Self.makeUnlockedEnv()
        let good = try env.service.createEncryptedItem(text: "readable")
        env.store.savePadItem(from: good)
        // Undecodable payload JSON and undecryptable-but-well-formed payload
        env.store.savePadItem(LocalPadItem(id: "bad-json", encryptedTextJSON: "garbage", createdAt: Date(timeIntervalSince1970: 100)))
        env.store.savePadItem(LocalPadItem(
            id: "bad-crypto",
            encryptedTextJSON: #"{"ciphertext":"AAAAAAAAAAAAAAAAAAAAAAAAAAAA","iv":"AAAAAAAAAAAAAAAA","version":1}"#,
            createdAt: Date(timeIntervalSince1970: 200)
        ))

        let decrypted = try env.service.getDecryptedItems()

        #expect(decrypted.map(\.text) == ["readable"])
        #expect(env.service.decryptFailureCount == 2)   // surfaced, not swallowed
    }

    @Test func lockedServiceThrowsNoEncryptionKey() throws {
        StubURLProtocol.reset()
        let store = try InMemoryLocalStore.make()
        let api = APIClient(
            baseURL: URL(string: "https://pad.test")!,
            sessionConfiguration: StubURLProtocol.stubbedConfiguration(),
            tokenProvider: { "pad-token" }
        )
        let service = PadService(api: api, keychain: InMemoryKeychain(), store: store)

        // do/catch instead of #expect(performing:throws:) — the sync performing
        // closure is not MainActor-isolated, but these methods are
        do {
            _ = try service.getDecryptedItems()
            Issue.record("getDecryptedItems must throw when locked")
        } catch PadError.noEncryptionKey {
            // expected: locked reads fail loudly
        } catch {
            Issue.record("expected PadError.noEncryptionKey, got \(error)")
        }
        do {
            _ = try service.createEncryptedItem(text: "x")
            Issue.record("createEncryptedItem must throw when locked")
        } catch PadError.noEncryptionKey {
            // expected: locked writes fail loudly
        } catch {
            Issue.record("expected PadError.noEncryptionKey, got \(error)")
        }
    }

    @Test func uploadFileEncryptsBytesAndMetadata() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.enqueue(method: "POST", pathSuffix: "/v1/files", json: #"{"id":"file-1","size":123,"r2Key":"r2/file-1"}"#)
        let env = try Self.makeUnlockedEnv()
        let plainBytes = Data("very secret document bytes".utf8)

        let attachment = try await env.service.uploadFile(name: "report.pdf", type: "application/pdf", data: plainBytes)

        #expect(attachment.id == "file-1")
        #expect(attachment.r2Key == "r2/file-1")
        // The wire body must never contain the plaintext bytes
        let body = try #require(StubURLProtocol.recordedRequests.first?.bodyData)
        #expect(body.range(of: plainBytes) == nil)
        // Metadata is encrypted but recoverable with the vault key
        let crypto = CryptoService()
        #expect(try crypto.decrypt(attachment.encryptedName.toEncryptedPayload(), using: env.key) == "report.pdf")
        #expect(try crypto.decrypt(attachment.encryptedType.toEncryptedPayload(), using: env.key) == "application/pdf")
    }

    @Test func downloadFileDecryptsServerBytes() async throws {
        StubURLProtocol.reset()
        let env = try Self.makeUnlockedEnv()
        let original = Data("downloaded content 📄".utf8)
        let encrypted = try CryptoService().encryptData(original, using: env.key)
        StubURLProtocol.enqueue(method: "GET", pathSuffix: "/v1/files/abc123", data: encrypted)

        let file = DecryptedFileAttachment(id: "file-1", name: "doc", type: "text/plain", size: original.count, r2Key: "abc123")
        let downloaded = try await env.service.downloadFile(file)

        #expect(downloaded == original)
    }
}
}
```

`GrooTests/Core/Sync/SyncServiceScratchpadTests.swift`:

```swift
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
```

`GrooTests/Core/Storage/LocalPadModelsTests.swift`:

```swift
//
//  LocalPadModelsTests.swift
//  GrooTests
//
//  LocalPadItem/LocalScratchpad JSON-accessor fallbacks and API-model
//  conversions (millisecond timestamps), plus DecryptedScratchpad title
//  derivation. Pure model logic — no container needed.
//

import Foundation
import Testing
@testable import Groo

struct LocalPadModelsTests {
    static let payload = PadEncryptedPayload(ciphertext: "Y2lwaGVy", iv: "aXZpdml2aXZpdg==", version: 1)

    @Test func garbageStoredJsonDegradesToNilPayloadAndEmptyFiles() {
        let item = LocalPadItem(id: "x", encryptedTextJSON: "garbage", createdAt: Date(timeIntervalSince1970: 1))
        item.filesJSON = Data("also garbage".utf8)

        #expect(item.encryptedText == nil)     // nil, never a wrong payload
        #expect(item.files.isEmpty)
        #expect(item.toPadListItem() == nil)   // unconvertible → skipped, not fabricated
    }

    @Test func padItemConvertsToAndFromApiModel() throws {
        let file = PadFileAttachment(id: "f-1", encryptedName: Self.payload, size: 9, encryptedType: Self.payload, r2Key: "r2/f-1")
        let apiItem = PadListItem(id: "item-1", encryptedText: Self.payload, files: [file], createdAt: 1_700_000_000_000)

        let local = try #require(LocalPadItem(from: apiItem))

        #expect(local.createdAt == Date(timeIntervalSince1970: 1_700_000_000))   // ms → Date
        #expect(local.toPadListItem() == apiItem)                                // …and back
    }

    @Test func scratchpadConvertsToAndFromApiModel() throws {
        let apiScratchpad = PadScratchpad(
            id: "sp-1", encryptedContent: Self.payload, files: [],
            createdAt: 1_700_000_000_000, updatedAt: 1_700_000_060_000
        )

        let local = try #require(LocalScratchpad(from: apiScratchpad))

        #expect(local.updatedAt == Date(timeIntervalSince1970: 1_700_000_060))
        #expect(local.toPadScratchpad() == apiScratchpad)
    }

    @Test func scratchpadTitleDerivesFromFirstLine() {
        func scratchpad(_ content: String) -> DecryptedScratchpad {
            DecryptedScratchpad(id: "sp", content: content, files: [], createdAt: 0, updatedAt: 0)
        }

        #expect(scratchpad("# Meeting Notes\nbody text").title == "Meeting Notes")
        #expect(scratchpad("plain first line\nsecond").title == "plain first line")
        #expect(scratchpad("###   ").title == "Untitled")
        #expect(scratchpad("").title == "Untitled")
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `bash scripts/test.sh --unit 2>&1 | tail -20`
Expected: BUILD FAILURE — `PadService.init` rejects `InMemoryKeychain` (parameter is concrete `KeychainService`).

- [ ] **Step 3: Widen the keychain seam**

In `Groo/Features/Pad/PadService.swift`:

(a) Property: `private let keychain: KeychainService` → `private let keychain: any KeychainServicing`

(b) Init parameter: `keychain: KeychainService = KeychainService(),` → `keychain: any KeychainServicing = KeychainService(),`

(c) In `unlockWithBiometric(context:)`, the protocol has no default arguments — pass the former default explicitly (same string as `KeychainService.loadBiometricProtected`'s default):

```swift
        let keyData = try keychain.loadBiometricProtected(
            for: KeychainService.Key.padEncryptionKey,
            prompt: "Authenticate to access Pad",
            context: context
        )
```

- [ ] **Step 4: Run to verify pass**

Run: `bash scripts/test.sh --unit 2>&1 | tail -5`
Expected: PASS — **280 tests** (263 + 17).

Verify the app still builds: `xcodebuild build -project Groo.xcodeproj -scheme Groo -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -3` → `** BUILD SUCCEEDED **`

Manual smoke: unlock Pad with Face ID (simulator: Features → Face ID → Matching Face), add an item, open a scratchpad.

- [ ] **Step 5: Commit**

```bash
git add Groo/Features/Pad/PadService.swift GrooTests
git commit -m "test: PadService crypto roundtrips (keychain seam), SyncService scratchpad CRUD, local Pad model fallbacks"
```

---

### Task 8: Full verification + docs + coverage snapshot

**Files:**
- Modify: `README.md` (Testing conventions: two lines)

- [ ] **Step 1: Full suite twice**

Run: `bash scripts/test.sh --all 2>&1 | tail -5 && bash scripts/test.sh --all 2>&1 | tail -5`
Expected: `** TEST SUCCEEDED **` twice — **280 unit tests + 1 UI test**, both runs.

- [ ] **Step 2: App builds**

Run: `xcodebuild build -project Groo.xcodeproj -scheme Groo -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Coverage snapshot**

Run: `bash scripts/test.sh --unit --coverage 2>&1 | tail -60`
Record in the task report: coverage for `APIClient.swift` (expected: well above the 51% baseline — the upload/download mass is now covered), `SharedCredentialMatcher.swift`, `SharedPadCrypto.swift`, `SharedPendingItemsStore.swift` (all expected >90%), `CredentialIdentityService.swift` (builders covered; the store round-trip methods intentionally not), `StockPortfolioManager.swift` (>60% — `refreshPrices`/exchange-rate flows intentionally uncovered), `YahooFinanceService.swift` (>60% — chart-data and 429-retry paths uncovered), `PrayerTrackingService.swift` (>85%), `PadService.swift` (>60% — password-unlock/clipboard paths uncovered), `SyncService.swift` (should rise vs Phase 3 now that scratchpad CRUD is covered).

- [ ] **Step 4: README lines**

In `README.md`'s Testing conventions list (after the Phase 3 lines), append:

```markdown
- `Shared/` is a classic (non-synchronized) Xcode group: register new Shared files with `ruby scripts/register_shared_file.rb <File.swift> <Target>...` — never by hand-editing the pbxproj.
- Extension pure logic lives in `Shared/` (`SharedCredentialMatcher`, `SharedPadCrypto`) and is tested from GrooTests through the app target; extension-target `.swift` files are not compiled into tests.
```

- [ ] **Step 5: Commit**

```bash
git add README.md
git commit -m "docs: note Shared-file registration and extension-logic test conventions in README"
```

- [ ] **Step 6: Final report**

Include in the report to the user:
- Final test totals (280 unit + 1 UI) and the coverage numbers from Step 3.
- Product gaps found during planning (not bugs introduced):
  1. **ShareExtension's queue is write-only** — it saves `shared_items.json` to the App Group, but nothing in the main app reads it. Shared texts silently go nowhere.
  2. **WebSocket session retention on non-cancel paths** — the Task 1 fix invalidates the session on `cancel()`, but `handleDisconnect`/`handleUnauthorizedHandshake` nil the connection without cancelling it, so drop/401 paths still retain a session per attempt until reconnect churn stops.
  3. **AzanWidget duplicates PrayerTimeService's deadline/next-prayer logic** in the widget target — consolidation candidate (would need the deadline math extracted to Shared with Adhan available to both).
  4. **`StockPortfolioManager.displayCurrency` couples totals to `UserDefaults.standard`** — untestable without a defaults seam; totals silently exclude holdings with missing exchange rates (by design, but only observable via `staleReason`).
  5. **`YahooFinanceService` 429 backoff uses real `Task.sleep`** — needs a sleep/clock seam to be testable.
  6. **`PrayerTimeService` is `Date()`/`Timer`-coupled throughout** — top candidate for a `now` seam in Phase 6.
  7. **`ExtensionConfig`** (Widget/Keyboard) is a third copy of the app-group/keychain identifiers that tests cannot compile-check; `SharedConfigTests` pins the other two copies against each other.

---

## Post-plan

Remaining spec phases: 5 (UI tests — `--uitest` launch argument, in-memory storage, accessibility identifiers) and 6 (edge-case sweep — unicode/size/date-boundary passes per suite; `PrayerTimeService` with a `now` seam belongs here). Phase 4 fast-follow candidates for the Phase 5/6 plans: consume-or-remove decision for the ShareExtension queue; WebSocket session invalidation on the drop paths; `YahooFinanceService` sleep seam + 429 tests.
