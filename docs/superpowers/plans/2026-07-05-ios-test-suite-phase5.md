# iOS Test Suite — Phase 5 (UI Tests) + Phase 4 Fast-Follows Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** End-to-end XCUITest coverage of the critical UI flows — Pass vault unlock/lock, Pass login-item CRUD (create → list → edit → detail → trash → restore), password generator, wallet onboarding up to (not including) real network, and a tab-navigation smoke — driven through a small, fenced `--uitest` launch-argument seam so UI tests never touch real local data or real APIs. Plus two Phase 4 fast-follows in the unit suite: `SharedCredentialMatcher.passkeys(_:matchingQuery:)` (the only untested matcher API) and `PadService` scratchpad encrypt/decrypt roundtrips.

**Architecture:** One production seam, one fencing condition:

1. **`Groo/Core/UITestMode.swift` (new, app target)** — everything UI-test-specific lives in this one file and is inert unless the process was launched with `--uitest` (`ProcessInfo.processInfo.arguments.contains("--uitest")`, evaluated exactly once). It provides: per-launch UserDefaults wipe + volatile dead-end URL overrides, an in-memory `KeychainServicing` fake, an in-memory SwiftData container, a no-op `CredentialIdentityProviding`, and an **in-process Pass API stub** (`URLProtocol` + in-memory vault server seeded with an empty vault encrypted under a known master password at 10k PBKDF2 iterations). The app's real crypto (`CryptoService` PBKDF2/AES-GCM, BIP39/BIP32 wallet derivation) runs unmodified — only I/O boundaries are swapped.
2. **Four fenced touchpoints** outside that file (every one a `UITestMode.isActive` branch, byte-for-byte identical behavior when false): `GrooApp` (activate + skip the push-permission prompt), `ContentView` (auth bypass + hermetic service construction), `LocalStore.shared` (in-memory container), and `Config.coinGeckoBaseURL` (gains the standard `overrideURL` pattern; `CoinGeckoService` reads it instead of a duplicated hardcoded constant — same URL).
3. **Auth is bypassed, not mocked**: `ContentView` treats `--uitest` as logged in and builds `PadService`/`SyncService` with a token provider that always throws `APIError.unauthorized` — every Pad/Sync API call dies at the token provider, before any socket is opened. `PassService` gets the in-process stub. `AuthService`/GrooAuth are constructed but never consulted for tokens. No OAuth mocking framework.
4. **Accessibility identifiers** (`.accessibilityIdentifier(...)`, zero behavior) are added to the controls the tests drive, namespaced by feature: `pass.unlock.*`, `pass.form.*`, `pass.detail.*`, `pass.menu`, `pass.add`, `passgen.*`, `wallet.*`.
5. **GrooUITests** is a filesystem-synchronized group — new `.swift` files under `GrooUITests/` compile automatically (no pbxproj work this phase; `Shared/` is untouched).

**Tech Stack:** XCUITest (`XCUIApplication` launch arguments, `waitForExistence(timeout:)`, `XCTNSPredicateExpectation` for attribute changes — never sleeps); Swift Testing for the two fast-follow unit suites; `scripts/test.sh --ui` (already supports `-only-testing:GrooUITests`); iPhone 17 Pro simulator (iOS 26.2).

**Spec:** `docs/superpowers/specs/2026-07-05-ios-test-suite-design.md` (Phase 5 section).

## Spec-coverage notes (read before implementing)

Honest feasibility check per spec flow — what is deliberately **not** tested and why. Do not invent coverage for these:

- **"Fresh launch → unlock screen → correct password reaches home"** — as written this describes `GlobalLockView`, which only appears when *biometric-protected* keys exist in the keychain and immediately auto-fires an `LAContext` Face ID prompt (system UI that XCUITest cannot stub; simulator Face ID enrollment is not automatable from a test). Under `--uitest` the fake keychain starts empty, so the app boots straight to `MainTabView` — which is itself the assertion that auth+lock gating is bypassed correctly. The *password* unlock surface in this app is the Pass vault (`PassUnlockView`), and that is what the unlock/lock tests drive end-to-end: wrong password rejected (real PBKDF2 derives a wrong key, real AES-GCM fails to open the stub vault, error surfaces, vault stays locked) and correct password reaching the item list. `GlobalLockView`/`UnlockView`/`PadUnlockView` biometric paths stay manual-smoke territory.
- **"Global lock re-engages on backgrounding"** — **this behavior does not exist in production.** Only `AzanView` observes `scenePhase`; `ContentView` sets `needsGlobalUnlock` exactly once, on the signed-out→signed-in transition. There is nothing to test; flag in the final report as a spec/product mismatch (either the spec assumed a feature that was never built, or backgrounding-relock is missing product work).
- **Login screen / OAuth flow** — `LoginView` drives `ASWebAuthenticationSession` against the real accounts server; the browser sheet is out-of-process system UI. Untestable headlessly without a big production bypass, which is exactly what `--uitest` avoids being. The smoke test pins the inverse contract: under `--uitest` the login screen must never appear.
- **Wallet import flow** — spec names only the create-wallet path; import (typing a seed phrase into a `TextEditor`) is deferred. Import parsing/derivation is already unit-pinned with real BIP39 vectors (`WalletManagerTests`, Phase 2).
- **Clipboard contents** — copy actions are asserted via their UI confirmations ("Copied!" label state), not by reading `UIPasteboard` from the runner process (cross-process pasteboard reads are a notorious flake source and iOS pasteboard-access prompts would inject system alerts).
- **Card/bank/note CRUD, folders, TOTP display, password health UI** — logic is unit-pinned (Phases 1–4); Phase 5 spec scopes UI CRUD to a login item. Phase 6 candidates.
- **Residual real-data touchpoints under `--uitest`** (all verified read-only or non-secret; document, don't fix this phase):
  1. `PassService.mergePendingPasskeys` reads the real App Group `pending_passkeys.enc` via `SharedPendingItemsStore.load(key:)`'s default `fileURL`. With the test vault key the file (if a developer's copy exists) is *unreadable* → the load throws, `mergePendingPasskeys` returns without clearing anything. Read-only, no state change, logged. A `pendingItemsFileURL` seam through `PassService` is not worth the surface for this.
  2. `AzanView.loadAndConfigure` calls `prefs.syncToAppGroup()` — writes non-secret prayer preferences to the App Group UserDefaults (the widget's mirror). The SwiftData side is in-memory (`LocalStore.shared` seam); only this mirror write escapes.
  3. GrooAuth's session restore reads its own keychain storage at `AuthService` construction (read-only; never asked for tokens under `--uitest`).
  4. The `--uitest` bootstrap **wipes the app's `UserDefaults` persistent domain** each launch — this is the test-independence mechanism, and it means running UI tests on a simulator you also develop on resets in-app preferences (tab order, dev URL overrides). The App Group store, real keychain, and real vault cache are untouched.
- **Yahoo Finance is not stubbed and needs no stub**: with the wiped defaults + in-memory store there are no stock holdings, and every `YahooFinanceService` call site is behind a `hasHoldings`/`!symbols.isEmpty` guard (verified: `HomeView.swift:335-343`, `StockPortfolioManager.refreshPrices` guard). If Phase 6 adds a stocks UI flow, Yahoo needs the same `Config` override treatment CoinGecko gets here.
- **System permission alerts**: the push-notification prompt is fenced off at the source (`GrooApp.setupPushNotifications` skips under `--uitest`). The *location* prompt can fire on first Azan-tab visit (`AzanLocationService.requestWhenInUseAuthorization`); the tab-smoke test dismisses it via a springboard `waitForExistence` check (no interruption-monitor magic, no sleeps).
- **`XCTNSPredicateExpectation` exception to "waitForExistence exclusively"**: label-*change* assertions (the Copy button flipping to "Copied!") can't be expressed as existence of an identifier-addressed element. One predicate-expectation helper is allowed; it is still a run-loop wait, not a sleep.

## Global Constraints

- Working directory: `/Users/groo/work/gr/ios`. Runners: `bash scripts/test.sh --unit` and `bash scripts/test.sh --ui` → `** TEST SUCCEEDED **`.
- **Baseline: 280 unit tests in 37 suites + 1 UI test**, all green. Running totals (verify in the xcodebuild summary; if a count differs, find out why before committing):
  - After Task 1: **284 unit tests, 37 suites** + 1 UI test
  - After Task 2: 284 unit + 1 UI (seam only — both suites must stay green, all 6 targets must build)
  - After Task 3: 284 unit + **3 UI tests**
  - After Task 4: 284 unit + **5 UI tests**
  - After Task 5: 284 unit + **7 UI tests**
- `GrooTests/` and `GrooUITests/` are synchronized folders — new `.swift` files compile automatically. **Do not touch `Shared/` or the pbxproj this phase.**
- **Every `--uitest` branch is fenced by `UITestMode.isActive` and behavior-preserving when false.** The fencing condition appears in exactly four production files: `UITestMode.swift` (defines it), `GrooApp.swift`, `ContentView.swift`, `LocalStore.swift`. The identifier-only view edits have no branches at all, and `Config.swift`/`CoinGeckoService.swift` gain no branch — the override pattern is the existing one and the default URL is byte-identical.
- **UI-test hygiene:** no `sleep`, no polling loops — `waitForExistence(timeout:)` (and the single predicate-expectation helper) only. Every test launches a fresh app process via `UITest.launchApp(...)` with `--uitest`; no test depends on another's state (the bootstrap wipe + fresh temp vault dir + per-process stub server guarantee it). Default wait: 15s; wallet keystore creation gets 60s (web3swift scrypt is slow in Debug).
- UI tests navigate to a flow's tab via the `-selectedTab <tab>` launch argument (NSArgumentDomain — highest-precedence, volatile, survives the bootstrap wipe) instead of tapping through the tab bar; only the tab-smoke test drives the tab bar itself, via a helper with a "More"-overflow fallback (9 tabs may not all fit).
- The stub master password (`uitest-master-1`), salt, and 10k KDF iterations are **test-vault-only** values served by the in-process stub; the production 600k default is untouched (`PassService.kdfIterations` is server-driven, and the stub *is* the server here — same mechanism as the real backend).
- Identifiers are API: if a UI test fails on a missing identifier, the production identifier was renamed — restore it, don't rewrite the test.
- Environment flake source (not code): `typeText` requires the simulator's hardware keyboard to be disconnected (Simulator → I/O → Keyboard → uncheck "Connect Hardware Keyboard"). If unlock tests fail with "Neither element nor any descendant has keyboard focus", fix the simulator setting.
- Before each commit: `bash scripts/test.sh --unit` green, and for Tasks 2–6 also `bash scripts/test.sh --ui` green and the full app build green (`xcodebuild build -project Groo.xcodeproj -scheme Groo -destination 'platform=iOS Simulator,name=iPhone 17 Pro'` — compiles all 6 targets).

---

### Task 1: Phase 4 fast-follows — matcher passkey query search + PadService scratchpad crypto

**Files:**
- Modify: `GrooTests/Shared/SharedCredentialMatcherTests.swift` (append one test)
- Modify: `GrooTests/Features/Pad/PadServiceTests.swift` (append three tests)

**Interfaces:**
- Consumes: existing `SharedCredentialMatcher.passkeys(_:matchingQuery:)` (`Shared/SharedCredentialMatcher.swift:75-90` — searches `name`, `userName`, `rpId`, case-insensitive, empty query = no filter), existing `Self.passkey(id:name:rpId:credentialId:)` fixture helper (fixed `userName: "user@example.com"`); `PadService.encryptScratchpadContent(_:)`/`decryptScratchpad(_:)` (`Groo/Features/Pad/PadService.swift:340-369`), `PadServiceTests.makeUnlockedEnv()`, `LocalScratchpad(id:encryptedContentJSON:createdAt:updatedAt:)`.
- Produces: nothing new — pure coverage of existing behavior.

- [ ] **Step 1: Append the matcher test**

In `GrooTests/Shared/SharedCredentialMatcherTests.swift`, after `mergingPendingPasskeysDedupesByCredentialIdVaultWins` (before the struct's closing brace), add:

```swift

    @Test func passkeyQuerySearchIsCaseInsensitiveAcrossNameUserNameAndRpId() {
        let passkeys = [
            Self.passkey(id: "by-name", name: "GitHub Passkey", rpId: "a.com"),
            Self.passkey(id: "by-rpid", name: "Work", rpId: "login.github.com"),
            Self.passkey(id: "no-hit", name: "Example", rpId: "c.com"),
        ]

        // name and rpId hit, case-insensitively; "no-hit" matches neither
        #expect(SharedCredentialMatcher.passkeys(passkeys, matchingQuery: "GITHUB").map(\.id) == ["by-name", "by-rpid"])
        // userName ("user@example.com" on every fixture) is the only field
        // containing this query — all three must match through it
        #expect(SharedCredentialMatcher.passkeys(passkeys, matchingQuery: "user@example").map(\.id) == ["by-name", "by-rpid", "no-hit"])
        // Empty query means "no filter"
        #expect(SharedCredentialMatcher.passkeys(passkeys, matchingQuery: "").count == 3)
    }
```

- [ ] **Step 2: Append the PadService scratchpad tests**

In `GrooTests/Features/Pad/PadServiceTests.swift`, inside the `PadServiceTests` struct (after the last existing test, before the closing braces — this suite lives under the `NetworkStubbedSuites` umbrella, so each test starts with `StubURLProtocol.reset()`):

```swift

    // MARK: - Scratchpad crypto (Phase 4 fast-follow)

    @Test func scratchpadContentRoundtripsThroughEncryptDecrypt() throws {
        StubURLProtocol.reset()
        let env = try Self.makeUnlockedEnv()

        let payload = try env.service.encryptScratchpadContent("secret scratchpad 📝")
        #expect(payload.ciphertext != "secret scratchpad 📝")

        let payloadJSON = try #require(String(data: JSONEncoder().encode(payload), encoding: .utf8))
        let scratchpad = LocalScratchpad(
            id: "sp-1",
            encryptedContentJSON: payloadJSON,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_060)
        )

        let decrypted = try env.service.decryptScratchpad(scratchpad)

        #expect(decrypted.id == "sp-1")
        #expect(decrypted.content == "secret scratchpad 📝")
        #expect(decrypted.files.isEmpty)
        #expect(decrypted.createdAt == 1_700_000_000_000)   // Date → ms
        #expect(decrypted.updatedAt == 1_700_000_060_000)
    }

    @Test func scratchpadWithUnparseablePayloadFailsLoudly() throws {
        StubURLProtocol.reset()
        let env = try Self.makeUnlockedEnv()
        let scratchpad = LocalScratchpad(
            id: "sp-bad",
            encryptedContentJSON: "garbage",
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 1)
        )

        // do/catch instead of #expect(performing:throws:) — the sync performing
        // closure is not MainActor-isolated, but decryptScratchpad is
        do {
            _ = try env.service.decryptScratchpad(scratchpad)
            Issue.record("decryptScratchpad must throw for an unparseable payload")
        } catch PadError.decryptionFailed {
            // expected: a nil payload is a loud failure, never empty content
        } catch {
            Issue.record("expected PadError.decryptionFailed, got \(error)")
        }
    }

    @Test func lockedServiceRejectsScratchpadCrypto() throws {
        StubURLProtocol.reset()
        let env = try Self.makeUnlockedEnv()
        env.service.lock()

        do {
            _ = try env.service.encryptScratchpadContent("x")
            Issue.record("encryptScratchpadContent must throw when locked")
        } catch PadError.noEncryptionKey {
            // expected
        } catch {
            Issue.record("expected PadError.noEncryptionKey, got \(error)")
        }
    }
```

- [ ] **Step 3: Run to verify pass**

Run: `bash scripts/test.sh --unit 2>&1 | tail -5`
Expected: PASS — **284 tests** (280 + 4), 37 suites. These are coverage tests over existing behavior: if any fails, production deviates from the recon'd contract — STOP and report, don't adjust assertions.

- [ ] **Step 4: Commit**

```bash
git add GrooTests
git commit -m "test: SharedCredentialMatcher passkey query search + PadService scratchpad crypto roundtrips (Phase 4 fast-follows)"
```

---

### Task 2: The `--uitest` production seam

**Files:**
- Create: `Groo/Core/UITestMode.swift` (synchronized folder — compiles automatically, app target only)
- Modify: `Groo/GrooApp.swift` (activation + push-prompt fence)
- Modify: `Groo/ContentView.swift` (auth bypass + hermetic services + keychain)
- Modify: `Groo/Core/Storage/LocalStore.swift` (`shared` becomes uitest-aware)
- Modify: `Groo/Core/Config.swift` (coinGecko override key — existing pattern)
- Modify: `Groo/Features/Crypto/Services/CoinGeckoService.swift` (read `Config.coinGeckoBaseURL`)

**Interfaces:**
- Consumes: `KeychainServicing` (`Groo/Core/Keychain/KeychainServicing.swift`), `KeychainError` (`.itemNotFound`, `.encodingFailed`), `CredentialIdentityProviding`, `CryptoService` (`deriveKey(password:salt:iterations:)`, `encryptData(_:using:)` → IV+ciphertext+tag combined), `PassVault.empty`, `PassKeyInfo`/`PassVaultResponse`/`PassVaultUpdateRequest` (Codable), `PassAPIClient(tokenProvider:forceRefresh:sessionConfiguration:)` (the Phase 1 session seam), `PassService(api:keychain:vaultStore:credentialService:)`, `PassVaultStore(directoryURL:)`, `PadService(api:keychain:)`, `SyncService(api:monitorsNetwork:)`, `APIClient(baseURL:tokenProvider:forceRefresh:)`, `LocalStore.schema`, `LocalStore(container:)`.
- Produces: `UITestMode` (`isActive`, `masterPassword`, `keySalt`, `kdfIterations`, `activateIfNeeded()`, `keychain`, `makeInMemoryModelContainer()`, `makePassService()`), `UITestInMemoryKeychain`, `UITestNoopCredentialService`, `UITestPassAPIProtocol`, `UITestVaultServer`.
- The stub server implements the real Pass API contract PassService already speaks: `GET /v1/vault/key-info`, `GET /v1/vault`, `PUT /v1/vault` with optimistic-locking 409s.

- [ ] **Step 1: Create `Groo/Core/UITestMode.swift`**

```swift
//
//  UITestMode.swift
//  Groo
//
//  Production seam for XCUITests. Every path in this file — and every branch
//  on UITestMode.isActive elsewhere — is inert unless the process was launched
//  with the "--uitest" argument (GrooUITests always passes it). Under --uitest
//  the app must never touch real local data or real APIs:
//    - UserDefaults: persistent domain wiped per launch (test independence),
//      overridable base URLs volatile-registered to an unroutable local port
//    - SwiftData: in-memory container (LocalStore.shared checks isActive)
//    - Keychain: in-process fake shared by ContentView/PadService/PassService
//    - Pass API: in-process URLProtocol stub with an in-memory vault, seeded
//      empty and encrypted under masterPassword (real PBKDF2 + AES-GCM)
//    - Pad/Sync/Accounts APIs: token provider always throws — requests die
//      before any network I/O
//  The seam swaps I/O boundaries only; all real crypto runs unmodified.
//

import CryptoKit
import Foundation
import LocalAuthentication
import SwiftData

enum UITestMode {
    /// The single fencing condition for every UI-test seam in the app.
    static let isActive = ProcessInfo.processInfo.arguments.contains("--uitest")

    /// Master password of the stub server's seeded vault. Mirrored as a
    /// constant in GrooUITests/UITestHelpers.swift — keep in sync.
    static let masterPassword = "uitest-master-1"

    /// Deterministic salt + low iteration count so unlock is near-instant in
    /// tests. kdfIterations is served by the stub exactly like the real
    /// server serves 600k — PassService's mechanism is identical either way.
    static let keySalt = Data(repeating: 0xAB, count: 16)
    static let kdfIterations = 10_000

    /// One shared in-process keychain so ContentView's global-lock check,
    /// PadService, and PassService all observe the same (empty-at-launch) state.
    static let keychain = UITestInMemoryKeychain()

    /// Called once from GrooApp.init, before any store/service singleton is
    /// first touched. (AuthService/GrooAuth are constructed before this runs
    /// but read only their own keychain storage, never UserDefaults.standard.)
    static func activateIfNeeded() {
        guard isActive else { return }

        // Fresh UserDefaults every launch: erases anything a previous UI-test
        // launch wrote (wallet address cache, selected tab) and detaches the
        // run from developer state on the same simulator.
        if let bundleId = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundleId)
        }

        // Defense-in-depth: point every overridable base URL at an unroutable
        // local port so any request that escapes a stub fails fast without
        // leaving the machine. register(defaults:) is volatile — never persisted.
        let dead = "http://127.0.0.1:9"
        UserDefaults.standard.register(defaults: [
            "padAPIBaseURL": dead,
            "passAPIBaseURL": dead,
            "accountsAPIBaseURL": dead,
            "ethereumRPCURL": dead,
            "blockscoutBaseURL": dead,
            "coinGeckoBaseURL": dead,
        ])
    }

    /// In-memory SwiftData container; LocalStore.shared wraps this under
    /// --uitest so every LocalStore.shared caller (Home, Azan, Portfolio,
    /// Settings, Stocks) is isolated without threading a store through views.
    static func makeInMemoryModelContainer() -> ModelContainer {
        let config = ModelConfiguration(schema: LocalStore.schema, isStoredInMemoryOnly: true)
        do {
            return try ModelContainer(for: LocalStore.schema, configurations: [config])
        } catch {
            // UI-test-only path: crash loudly; a fallback would hide the break
            fatalError("UITestMode: in-memory ModelContainer creation failed: \(error)")
        }
    }

    /// PassService wired to the in-process stub API, the fake keychain, a
    /// per-launch temp-directory vault store (never the App Group), and a
    /// no-op credential-identity service (never ASCredentialIdentityStore).
    @MainActor
    static func makePassService() -> PassService {
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.protocolClasses = [UITestPassAPIProtocol.self]
        let api = PassAPIClient(
            tokenProvider: { "uitest-token" },
            forceRefresh: { "uitest-token" },
            sessionConfiguration: sessionConfiguration
        )
        let vaultDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("uitest-vault-\(UUID().uuidString)", isDirectory: true)
        return PassService(
            api: api,
            keychain: keychain,
            vaultStore: PassVaultStore(directoryURL: vaultDirectory),
            credentialService: UITestNoopCredentialService()
        )
    }
}

// MARK: - In-memory keychain

/// Deterministic KeychainServicing fake for --uitest. Biometric items never
/// prompt. (Deliberate near-duplicate of GrooTests/Support/InMemoryKeychain —
/// test-target code cannot be compiled into the app target.)
final class UITestInMemoryKeychain: KeychainServicing, @unchecked Sendable {
    private let lock = NSLock()
    private var plain: [String: Data] = [:]
    private var biometric: [String: Data] = [:]

    func save(_ value: String, for key: String) throws {
        try save(Data(value.utf8), for: key)
    }

    func loadString(for key: String) throws -> String {
        guard let string = String(data: try load(for: key), encoding: .utf8) else {
            throw KeychainError.encodingFailed
        }
        return string
    }

    func save(_ data: Data, for key: String) throws {
        lock.lock(); defer { lock.unlock() }
        plain[key] = data
    }

    func load(for key: String) throws -> Data {
        lock.lock(); defer { lock.unlock() }
        guard let data = plain[key] else { throw KeychainError.itemNotFound }
        return data
    }

    func delete(for key: String) throws {
        lock.lock(); defer { lock.unlock() }
        plain[key] = nil
    }

    func exists(for key: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return plain[key] != nil
    }

    func saveBiometricProtected(_ data: Data, for key: String) throws {
        lock.lock(); defer { lock.unlock() }
        biometric[key] = data
    }

    func loadBiometricProtected(for key: String, prompt: String, context: LAContext?) throws -> Data {
        lock.lock(); defer { lock.unlock() }
        guard let data = biometric[key] else { throw KeychainError.itemNotFound }
        return data
    }

    func deleteBiometricProtected(for key: String) throws {
        lock.lock(); defer { lock.unlock() }
        biometric[key] = nil
    }

    func biometricProtectedKeyExists(for key: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return biometric[key] != nil
    }
}

// MARK: - No-op credential identity service

/// Keeps --uitest runs out of the (global, entitlement-gated) system
/// ASCredentialIdentityStore.
final class UITestNoopCredentialService: CredentialIdentityProviding {
    func updateCredentialIdentities(from items: [PassVaultItem]) async {}
    func clearCredentialIdentities() async -> Bool { true }
}

// MARK: - In-process Pass API stub

/// In-memory Pass "server": GET /v1/vault/key-info, GET /v1/vault,
/// PUT /v1/vault with the real optimistic-locking contract (409 on a stale
/// expectedVersion). Seeded lazily with an empty vault encrypted — via the
/// app's own CryptoService — under UITestMode.masterPassword.
final class UITestVaultServer: @unchecked Sendable {
    static let shared = UITestVaultServer()

    private let lock = NSLock()
    private var encryptedData: String   // base64 (ciphertext+tag, no IV)
    private var iv: String              // base64 (12 bytes)
    private var version = 1
    private var updatedAt = Int(Date().timeIntervalSince1970 * 1000)

    private init() {
        let crypto = CryptoService()
        do {
            let key = try crypto.deriveKey(
                password: UITestMode.masterPassword,
                salt: UITestMode.keySalt,
                iterations: UInt32(UITestMode.kdfIterations)
            )
            let vaultJSON = try JSONEncoder().encode(PassVault.empty)
            // encryptData returns IV + ciphertext + tag; the API contract
            // splits the 12-byte IV out (mirrors PassService.saveVault)
            let combined = try crypto.encryptData(vaultJSON, using: key)
            self.iv = combined.prefix(12).base64EncodedString()
            self.encryptedData = combined.dropFirst(12).base64EncodedString()
        } catch {
            fatalError("UITestVaultServer: vault seeding failed: \(error)")
        }
    }

    func response(for request: URLRequest) -> (status: Int, body: Data) {
        lock.lock(); defer { lock.unlock() }
        let path = request.url?.path ?? ""
        let method = request.httpMethod ?? "GET"

        switch (method, path) {
        case ("GET", "/v1/vault/key-info"):
            return (200, encode(PassKeyInfo(
                keySalt: UITestMode.keySalt.base64EncodedString(),
                kdfIterations: UITestMode.kdfIterations
            )))
        case ("GET", "/v1/vault"):
            return (200, encode(PassVaultResponse(
                encryptedData: encryptedData, iv: iv, version: version, updatedAt: updatedAt
            )))
        case ("PUT", "/v1/vault"):
            guard let body = request.uitestBodyData,
                  let update = try? JSONDecoder().decode(PassVaultUpdateRequest.self, from: body) else {
                return (400, Data(#"{"error":"bad request"}"#.utf8))
            }
            guard update.expectedVersion == version else {
                return (409, Data(#"{"error":"VERSION_CONFLICT"}"#.utf8))
            }
            encryptedData = update.encryptedData
            iv = update.iv
            version += 1
            updatedAt = Int(Date().timeIntervalSince1970 * 1000)
            return (200, encode(PassVaultResponse(
                encryptedData: encryptedData, iv: iv, version: version, updatedAt: updatedAt
            )))
        default:
            return (404, Data(#"{"error":"not found"}"#.utf8))
        }
    }

    private func encode<T: Encodable>(_ value: T) -> Data {
        (try? JSONEncoder().encode(value)) ?? Data()
    }
}

/// Installed only on the PassAPIClient session UITestMode.makePassService
/// builds — it intercepts every request on that session and answers from
/// UITestVaultServer. No other session in the app sees this class.
final class UITestPassAPIProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let (status, body) = UITestVaultServer.shared.response(for: request)
        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "http://uitest.invalid")!,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private extension URLRequest {
    /// URLSession hands URLProtocol the body as a stream, not httpBody.
    var uitestBodyData: Data? {
        if let body = httpBody { return body }
        guard let stream = httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 4096
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: bufferSize)
            guard read > 0 else { break }
            data.append(buffer, count: read)
        }
        return data
    }
}
```

- [ ] **Step 2: Wire `GrooApp.swift`**

(a) Add an explicit init to `struct GrooApp` (after the `@State` properties, before `var body`):

```swift
    init() {
        // UI-test isolation must engage before any store/service singleton
        // (LocalStore.shared, Config URL reads) is first touched.
        UITestMode.activateIfNeeded()
    }
```

(b) Fence the push prompt — in `setupPushNotifications()`, add as the first line of the function body:

```swift
        // Never pop the push-permission system alert under UI tests
        guard !UITestMode.isActive else { return }
```

- [ ] **Step 3: Wire `ContentView.swift`**

(a) Replace the keychain property:

```swift
    private let keychain = KeychainService()
```

with:

```swift
    // Under --uitest the global-lock check must consult the same fake
    // keychain the services write to, never the developer's real keychain.
    private let keychain: any KeychainServicing =
        UITestMode.isActive ? UITestMode.keychain : KeychainService()
```

(b) In `initializeServices()`, insert at the top of the function body (before `let api = APIClient(`):

```swift
        if UITestMode.isActive {
            // Hermetic services: Pad/Sync API calls die at the token provider
            // (no network I/O ever starts); Pass talks to the in-process stub;
            // stores are in-memory (LocalStore.shared is uitest-aware).
            let api = APIClient(
                baseURL: Config.padAPIBaseURL,
                tokenProvider: { throw APIError.unauthorized },
                forceRefresh: { throw APIError.unauthorized }
            )
            padService = PadService(api: api, keychain: UITestMode.keychain)
            syncService = SyncService(api: api, monitorsNetwork: false)
            passService = UITestMode.makePassService()
            return
        }
```

(c) In `updateState()`, replace:

```swift
        isLoggedIn = authService.isAuthenticated
```

with:

```swift
        // --uitest bypasses OAuth entirely; services never ask AuthService
        // for tokens in that mode (see initializeServices)
        isLoggedIn = authService.isAuthenticated || UITestMode.isActive
```

- [ ] **Step 4: Wire `LocalStore.swift`**

Replace:

```swift
    static let shared = LocalStore()
```

with:

```swift
    // Under --uitest every LocalStore.shared caller gets an in-memory store;
    // the real App Group store is never opened in that mode.
    static let shared: LocalStore = UITestMode.isActive
        ? LocalStore(container: UITestMode.makeInMemoryModelContainer())
        : LocalStore()
```

- [ ] **Step 5: CoinGecko URL override (existing Config pattern)**

In `Groo/Core/Config.swift`, replace:

```swift
    static var coinGeckoBaseURL: URL {
        URL(string: "https://api.coingecko.com/api/v3")!
    }
```

with:

```swift
    /// CoinGecko API base URL. Override via UserDefaults "coinGeckoBaseURL"
    /// (UI tests register a dead-end override so price lookups never leave
    /// the machine).
    static var coinGeckoBaseURL: URL {
        if let url = overrideURL(forKey: "coinGeckoBaseURL") {
            return url
        }
        return URL(string: "https://api.coingecko.com/api/v3")!
    }
```

In `Groo/Features/Crypto/Services/CoinGeckoService.swift`, replace:

```swift
    private let baseURL = URL(string: "https://api.coingecko.com/api/v3")!
```

with:

```swift
    // Same default URL; Config adds the UserDefaults override seam
    private let baseURL = Config.coinGeckoBaseURL
```

- [ ] **Step 6: Verify**

Run: `bash scripts/test.sh --unit 2>&1 | tail -5`
Expected: PASS — **284 tests** (the seam adds none; `UITestMode.isActive` is false in the unit-test host, so `LocalStore.shared` and everything else behave exactly as before).

Run: `bash scripts/test.sh --ui 2>&1 | tail -5`
Expected: PASS — 1 UI test (the old smoke launches *without* `--uitest`; all seams dormant).

Run: `xcodebuild build -project Groo.xcodeproj -scheme Groo -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **` (all 6 targets; `UITestMode.swift` is app-target-only via the synchronized `Groo/` folder).

Manual smoke (seam engaged): `xcrun simctl launch booted dev.groo.ios.debug --uitest` after installing a fresh build (or run the app from Xcode with `--uitest` in the scheme's arguments — remove it afterwards). The app must open on the tab bar with no login screen; the Pass tab must show "Pass is Locked" and accept `uitest-master-1`. Also launch once *without* the argument and confirm normal behavior (login/session state unchanged).

- [ ] **Step 7: Commit**

```bash
git add Groo/Core/UITestMode.swift Groo/GrooApp.swift Groo/ContentView.swift Groo/Core/Storage/LocalStore.swift Groo/Core/Config.swift Groo/Features/Crypto/Services/CoinGeckoService.swift
git commit -m "feat: --uitest launch-argument seam for hermetic UI tests (in-memory storage, in-process Pass API stub, dead-end URLs)"
```

---

### Task 3: Accessibility identifiers + UI-test helpers + smoke rewrite + unlock/lock tests

**Files:**
- Modify: `Groo/Features/Pass/Views/PassUnlockView.swift`, `PassView.swift`, `PassItemListView.swift`, `PassItemFormView.swift`, `PassItemDetailView.swift`, `PasswordGeneratorView.swift` (identifiers only)
- Modify: `Groo/Features/Crypto/Views/WalletOnboardingView.swift`, `PortfolioView.swift` (identifiers only)
- Create: `GrooUITests/UITestHelpers.swift`
- Modify: `GrooUITests/SmokeUITests.swift` (full-file replacement)
- Create: `GrooUITests/PassUnlockUITests.swift`

**Interfaces:**
- Produces: the full identifier namespace all Phase 5 tests use (added once, here, so Tasks 4–5 are test-code-only): `pass.unlock.password/submit/error`, `pass.menu`, `pass.add`, `pass.form.name/username/password/generate`, `pass.detail.close/showPassword`, `passgen.value/length/length.value/regenerate/copy/use`, `wallet.create/import/address/mnemonic.confirm/portfolio`. Every edit is a pure `.accessibilityIdentifier(...)` chain append — zero behavior.

- [ ] **Step 1: Add the identifiers (exact edits)**

**`PassUnlockView.swift`** — three edits in `passwordSection`:

(1) On the SecureField, after `.textContentType(.password)`:

```swift
                SecureField("Enter master password", text: $password)
                    .font(.body)
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
                    .textContentType(.password)
                    .accessibilityIdentifier("pass.unlock.password")
                    .focused($isPasswordFocused)
                    .onSubmit {
                        unlockWithPassword()
                    }
```

(2) In the error block, on the `Text`:

```swift
            if let error = errorMessage {
                HStack(spacing: Theme.Spacing.xs) {
                    Image(systemName: "exclamationmark.circle.fill")
                    Text(error)
                        .accessibilityIdentifier("pass.unlock.error")
                }
```

(3) On the Unlock button, after `.disabled(password.isEmpty || isLoading)`:

```swift
            .disabled(password.isEmpty || isLoading)
            .accessibilityIdentifier("pass.unlock.submit")
```

**`PassView.swift`** — on the toolbar `Menu`, after its `label:` closure's closing brace:

```swift
                            } label: {
                                Image(systemName: "ellipsis.circle")
                            }
                            .accessibilityIdentifier("pass.menu")
```

**`PassItemListView.swift`** — on the add button:

```swift
                Button {
                    onAddItem()
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityIdentifier("pass.add")
```

**`PassItemFormView.swift`** — four edits:

```swift
                Section {
                    TextField("Name", text: $name)
                        .accessibilityIdentifier("pass.form.name")
                }
```

```swift
                TextField("Username", text: $username)
                    .textContentType(.username)
                    .autocapitalization(.none)
                    .accessibilityIdentifier("pass.form.username")
```

```swift
                    SecureField("Password", text: $password)
                        .textContentType(.password)
                        .accessibilityIdentifier("pass.form.password")
```

```swift
                    Button {
                        showPasswordGenerator = true
                    } label: {
                        Image(systemName: "wand.and.stars")
                            .foregroundStyle(Theme.Brand.primary)
                    }
                    .accessibilityIdentifier("pass.form.generate")
```

**`PassItemDetailView.swift`** — two edits:

(1) Toolbar close button:

```swift
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .accessibilityIdentifier("pass.detail.close")
            }
```

(2) The show/hide-password trailing button inside `passwordContent`'s `fieldRow`:

```swift
                trailing: {
                    Button {
                        showPassword.toggle()
                    } label: {
                        Image(systemName: showPassword ? "eye.slash.fill" : "eye.fill")
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityIdentifier("pass.detail.showPassword")
                }
```

**`PasswordGeneratorView.swift`** — six edits:

```swift
            Text(password)
                .font(.system(.title3, design: .monospaced))
                .multilineTextAlignment(.center)
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
                .accessibilityIdentifier("passgen.value")
```

```swift
                    Text("\(Int(length))")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .accessibilityIdentifier("passgen.length.value")
```

```swift
                Slider(value: $length, in: minLength...maxLength, step: 1) { _ in
                    generatePassword()
                }
                .tint(Theme.Brand.primary)
                .accessibilityIdentifier("passgen.length")
```

```swift
                Button {
                    generatePassword()
                } label: {
                    Label("Regenerate", systemImage: "arrow.clockwise")
                        .font(.subheadline)
                }
                .accessibilityIdentifier("passgen.regenerate")
```

On the copy button (the one whose label flips to "Copied!"), after its `label:` closure:

```swift
                }
                .accessibilityIdentifier("passgen.copy")
```

On the "Use Password" button, after the closing brace of its `label:` closure:

```swift
                Button {
                    onPasswordGenerated(password)
                    dismiss()
                } label: {
                    Text("Use Password")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Theme.Brand.primary)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
                }
                .accessibilityIdentifier("passgen.use")
```

**`WalletOnboardingView.swift`** — four edits:

On the create button (after its `label:` closing brace): `.accessibilityIdentifier("wallet.create")`
On the import button: `.accessibilityIdentifier("wallet.import")`
On the address text:

```swift
                            Text(address)
                                .font(.caption.monospaced())
                                .textSelection(.enabled)
                                .accessibilityIdentifier("wallet.address")
```

On the "I've Saved My Recovery Phrase" button, after `.padding()`:

```swift
                    .padding()
                    .accessibilityIdentifier("wallet.mnemonic.confirm")
```

**`PortfolioView.swift`** — one edit, on the `List`'s modifier chain (line ~186):

```swift
            }
            .accessibilityIdentifier("wallet.portfolio")
            .navigationTitle("")
```

- [ ] **Step 2: Create `GrooUITests/UITestHelpers.swift`**

```swift
//
//  UITestHelpers.swift
//  GrooUITests
//
//  Shared launch + flow helpers. Every test launches a fresh app process with
//  --uitest (hermetic storage and stubs; see Groo/Core/UITestMode.swift).
//  No sleeps anywhere: waitForExistence + one predicate-expectation helper.
//

import XCTest

enum UITest {
    /// Must match UITestMode.masterPassword in the app target.
    static let masterPassword = "uitest-master-1"
    static let timeout: TimeInterval = 15

    /// Fresh, hermetic app instance. `selectedTab` uses the NSArgumentDomain
    /// UserDefaults override for @AppStorage("selectedTab") — the app opens
    /// directly on that tab, no tab-bar navigation needed.
    static func launchApp(selectedTab: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--uitest"]
        if let selectedTab {
            app.launchArguments += ["-selectedTab", selectedTab]
        }
        app.launch()
        return app
    }

    /// Unlock the Pass vault with the stub master password. Precondition:
    /// PassUnlockView is on screen (launch with selectedTab: "pass").
    static func unlockPass(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let field = app.secureTextFields["pass.unlock.password"]
        XCTAssertTrue(field.waitForExistence(timeout: timeout), "Pass unlock password field never appeared", file: file, line: line)
        field.tap()
        field.typeText(masterPassword)
        app.buttons["pass.unlock.submit"].tap()
        XCTAssertTrue(app.buttons["pass.add"].waitForExistence(timeout: timeout), "vault did not unlock into the item list", file: file, line: line)
    }

    /// Select a tab by title, falling back to the tab bar's "More" overflow
    /// (9 tabs may not all fit on an iPhone tab bar).
    static func openTab(_ app: XCUIApplication, _ title: String, file: StaticString = #filePath, line: UInt = #line) {
        let direct = app.tabBars.buttons[title]
        if direct.exists {
            direct.tap()
            return
        }
        let more = app.tabBars.buttons["More"]
        if more.exists {
            more.tap()
            let entry = app.buttons[title].firstMatch
            if entry.waitForExistence(timeout: timeout) {
                entry.tap()
                return
            }
        }
        XCTFail("Tab \(title) not reachable from the tab bar", file: file, line: line)
    }

    /// Dismiss a system permission alert (e.g. location on the Azan tab) if
    /// one appears. waitForExistence keeps this sleep-free; if no alert shows
    /// within `timeout`, this is a no-op.
    static func dismissSystemAlertIfPresent(timeout: TimeInterval = 3) {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let alert = springboard.alerts.firstMatch
        guard alert.waitForExistence(timeout: timeout) else { return }
        for label in ["Don’t Allow", "Don't Allow", "Allow Once", "OK"] {
            let button = alert.buttons[label]
            if button.exists {
                button.tap()
                return
            }
        }
    }

    /// Wait (run-loop, not sleep) for an element attribute change that can't
    /// be expressed as existence — e.g. a button label flipping to "Copied!".
    static func waitForLabel(_ element: XCUIElement, equals expected: String, timeout: TimeInterval = 5) -> Bool {
        let predicate = NSPredicate(format: "label == %@", expected)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }
}

extension XCUIElement {
    /// Replace a text field's current value. Taps near the trailing edge so
    /// the caret lands at the end, then deletes backwards before typing.
    func clearAndTypeText(_ text: String) {
        coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        let current = (value as? String) ?? ""
        if !current.isEmpty {
            typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count + 5))
        }
        typeText(text)
    }
}
```

- [ ] **Step 3: Replace `GrooUITests/SmokeUITests.swift`**

```swift
//
//  SmokeUITests.swift
//  GrooUITests
//
//  Proves the --uitest bootstrap works: the app launches hermetically into
//  the main tab UI with no OAuth login and no lock screen.
//

import XCTest

final class SmokeUITests: XCTestCase {
    func testAppLaunchesIntoMainTabsWithoutLogin() {
        let app = UITest.launchApp(selectedTab: "home")

        XCTAssertEqual(app.state, .runningForeground)
        // --uitest bypasses OAuth: the tab bar must appear…
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: UITest.timeout))
        // …and the login screen must not
        XCTAssertFalse(app.buttons["Sign in with Groo"].exists)
    }
}
```

- [ ] **Step 4: Create `GrooUITests/PassUnlockUITests.swift`**

```swift
//
//  PassUnlockUITests.swift
//  GrooUITests
//
//  Pass vault unlock/lock: wrong master password rejected (real PBKDF2 +
//  AES-GCM against the stub vault), correct password reaches the item list,
//  Lock Vault re-locks. No biometrics under --uitest, so PassUnlockView
//  always shows the password field directly.
//

import XCTest

final class PassUnlockUITests: XCTestCase {
    func testWrongMasterPasswordIsRejected() {
        let app = UITest.launchApp(selectedTab: "pass")

        let field = app.secureTextFields["pass.unlock.password"]
        XCTAssertTrue(field.waitForExistence(timeout: UITest.timeout))
        field.tap()
        field.typeText("definitely-wrong-password")
        app.buttons["pass.unlock.submit"].tap()

        // Wrong key ⇒ AES-GCM open fails ⇒ error surfaces, vault stays locked
        XCTAssertTrue(app.staticTexts["pass.unlock.error"].waitForExistence(timeout: UITest.timeout))
        XCTAssertTrue(app.staticTexts["Pass is Locked"].exists)
        XCTAssertFalse(app.buttons["pass.add"].exists)
    }

    func testUnlockThenLockVaultRelocks() {
        let app = UITest.launchApp(selectedTab: "pass")

        UITest.unlockPass(app)
        // Seeded vault is empty — the empty state is the post-unlock screen
        XCTAssertTrue(app.staticTexts["No items in your vault"].waitForExistence(timeout: UITest.timeout))

        app.buttons["pass.menu"].tap()
        let lockButton = app.buttons["Lock Vault"]
        XCTAssertTrue(lockButton.waitForExistence(timeout: UITest.timeout))
        lockButton.tap()

        // Locked again: unlock screen back, list gone
        XCTAssertTrue(app.staticTexts["Pass is Locked"].waitForExistence(timeout: UITest.timeout))
        XCTAssertTrue(app.secureTextFields["pass.unlock.password"].waitForExistence(timeout: UITest.timeout))
        XCTAssertFalse(app.buttons["pass.add"].exists)
    }
}
```

- [ ] **Step 5: Verify**

Run: `bash scripts/test.sh --ui 2>&1 | tail -5`
Expected: PASS — **3 UI tests** (smoke + 2 unlock). If an element isn't found, get the live hierarchy with `print(app.debugDescription)` at the failure point and fix the *query*, never by adding waits beyond `waitForExistence`.

Run: `bash scripts/test.sh --unit 2>&1 | tail -3` → 284 tests (identifier edits are invisible to unit tests).

Run: `xcodebuild build -project Groo.xcodeproj -scheme Groo -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -3` → `** BUILD SUCCEEDED **`

- [ ] **Step 6: Commit**

```bash
git add Groo GrooUITests
git commit -m "test: Pass unlock/lock UI flows + hermetic smoke; accessibility identifiers on Pass/generator/wallet controls"
```

---

### Task 4: Pass CRUD lifecycle + password generator UI tests

**Files:**
- Create: `GrooUITests/PassCrudUITests.swift`
- Create: `GrooUITests/PasswordGeneratorUITests.swift`

**Interfaces:**
- Consumes: Task 3 identifiers; the stub server's PUT path (every CRUD save round-trips encrypt → PUT → version bump); SwiftUI `List` rows surface as `cells`, swipe actions as buttons after `swipeLeft()`/`swipeRight()`.
- CRUD is one journey test on purpose: each app launch + unlock costs ~10s, and the spec's flow (create → list → edit → detail → trash → restore) is a single user story whose steps depend on each other. Intermediate assertions make failures pinpointable.

- [ ] **Step 1: Create `GrooUITests/PassCrudUITests.swift`**

```swift
//
//  PassCrudUITests.swift
//  GrooUITests
//
//  The spec's Pass CRUD journey: create login item → visible in list → edit →
//  detail reflects change → trash → restore. Every mutation round-trips
//  through real AES-GCM encryption and the in-process stub server's
//  optimistic-locking PUT.
//

import XCTest

final class PassCrudUITests: XCTestCase {
    func testLoginItemLifecycleCreateEditDetailTrashRestore() {
        let app = UITest.launchApp(selectedTab: "pass")
        UITest.unlockPass(app)

        // ---- Create ----
        app.buttons["pass.add"].tap()
        let nameField = app.textFields["pass.form.name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: UITest.timeout))
        nameField.tap()
        nameField.typeText("GitHub Test")
        let usernameField = app.textFields["pass.form.username"]
        usernameField.tap()
        usernameField.typeText("octocat@example.com")
        let passwordField = app.secureTextFields["pass.form.password"]
        passwordField.tap()
        passwordField.typeText("hunter2-secret")
        app.buttons["Save"].tap()

        // ---- Visible in list ----
        let rowText = app.staticTexts["GitHub Test"]
        XCTAssertTrue(rowText.waitForExistence(timeout: UITest.timeout), "created item must appear in the list")

        // ---- Edit (leading swipe → Edit) ----
        let cell = app.cells.containing(.staticText, identifier: "GitHub Test").firstMatch
        cell.swipeRight()
        let editButton = app.buttons["Edit"]
        XCTAssertTrue(editButton.waitForExistence(timeout: UITest.timeout))
        editButton.tap()
        let editUsername = app.textFields["pass.form.username"]
        XCTAssertTrue(editUsername.waitForExistence(timeout: UITest.timeout))
        editUsername.clearAndTypeText("octocat+edited@example.com")
        app.buttons["Save"].tap()

        // ---- Detail reflects the edit ----
        XCTAssertTrue(rowText.waitForExistence(timeout: UITest.timeout))
        rowText.tap()
        XCTAssertTrue(app.staticTexts["octocat+edited@example.com"].waitForExistence(timeout: UITest.timeout),
                      "detail must show the edited username")
        app.buttons["pass.detail.close"].tap()

        // ---- Trash (trailing swipe → Delete) ----
        XCTAssertTrue(rowText.waitForExistence(timeout: UITest.timeout))
        cell.swipeLeft()
        let deleteButton = app.buttons["Delete"]
        XCTAssertTrue(deleteButton.waitForExistence(timeout: UITest.timeout))
        deleteButton.tap()
        XCTAssertTrue(app.staticTexts["No items in your vault"].waitForExistence(timeout: UITest.timeout),
                      "trashed item must leave the list")

        // ---- Restore from trash ----
        app.buttons["pass.menu"].tap()
        let trashMenuItem = app.buttons["Trash"]
        XCTAssertTrue(trashMenuItem.waitForExistence(timeout: UITest.timeout))
        trashMenuItem.tap()
        let trashedText = app.staticTexts["GitHub Test"]
        XCTAssertTrue(trashedText.waitForExistence(timeout: UITest.timeout), "item must be in the trash")
        let trashCell = app.cells.containing(.staticText, identifier: "GitHub Test").firstMatch
        trashCell.swipeRight()
        let restoreButton = app.buttons["Restore"]
        XCTAssertTrue(restoreButton.waitForExistence(timeout: UITest.timeout))
        restoreButton.tap()
        XCTAssertTrue(app.staticTexts["Trash is Empty"].waitForExistence(timeout: UITest.timeout),
                      "restore must empty the trash")
        app.buttons["Done"].tap()

        // ---- Restored item back in the list ----
        XCTAssertTrue(app.staticTexts["GitHub Test"].waitForExistence(timeout: UITest.timeout),
                      "restored item must reappear in the list")
    }
}
```

- [ ] **Step 2: Create `GrooUITests/PasswordGeneratorUITests.swift`**

```swift
//
//  PasswordGeneratorUITests.swift
//  GrooUITests
//
//  Generator sheet from the item form: generate, options respected
//  (charset + length), copy confirmation, and Use Password flowing into a
//  saved item (verified by revealing it in the detail view — SecureField
//  values are not readable from XCUITest).
//

import XCTest

final class PasswordGeneratorUITests: XCTestCase {
    func testGenerateOptionsCopyAndUsePassword() {
        let app = UITest.launchApp(selectedTab: "pass")
        UITest.unlockPass(app)

        // Open the form, then the generator
        app.buttons["pass.add"].tap()
        let nameField = app.textFields["pass.form.name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: UITest.timeout))
        nameField.tap()
        nameField.typeText("Generated Login")
        app.buttons["pass.form.generate"].tap()

        let valueText = app.staticTexts["passgen.value"]
        XCTAssertTrue(valueText.waitForExistence(timeout: UITest.timeout))
        let initial = valueText.label
        XCTAssertEqual(initial.count, 16, "default length is 16")

        // Regenerate produces a different password (16 random chars colliding
        // is ~2^-90 — equality means regenerate is broken)
        app.buttons["passgen.regenerate"].tap()
        XCTAssertNotEqual(valueText.label, initial)

        // Options respected: switch off everything but numbers
        app.switches["Uppercase (A-Z)"].firstMatch.tap()
        app.switches["Lowercase (a-z)"].firstMatch.tap()
        app.switches["Symbols (!@#$...)"].firstMatch.tap()
        let numericOnly = valueText.label
        XCTAssertTrue(numericOnly.allSatisfy(\.isNumber), "numbers-only charset violated: \(numericOnly)")

        // Length respected: slider to max, then compare against the displayed count
        app.sliders["passgen.length"].adjust(toNormalizedSliderPosition: 1.0)
        let displayedLength = Int(app.staticTexts["passgen.length.value"].label) ?? -1
        XCTAssertGreaterThan(displayedLength, 16, "slider at max must exceed the default")
        XCTAssertEqual(valueText.label.count, displayedLength, "generated length must match the length control")

        // Copy shows its confirmation (label flip, not pasteboard — see plan notes)
        let copyButton = app.buttons["passgen.copy"]
        copyButton.tap()
        XCTAssertTrue(UITest.waitForLabel(copyButton, equals: "Copied!"), "copy must confirm")

        // Use Password → back on the form → save → reveal in detail
        let finalPassword = valueText.label
        app.buttons["passgen.use"].tap()
        XCTAssertTrue(nameField.waitForExistence(timeout: UITest.timeout))
        app.buttons["Save"].tap()
        let row = app.staticTexts["Generated Login"]
        XCTAssertTrue(row.waitForExistence(timeout: UITest.timeout))
        row.tap()
        let reveal = app.buttons["pass.detail.showPassword"]
        XCTAssertTrue(reveal.waitForExistence(timeout: UITest.timeout))
        reveal.tap()
        XCTAssertTrue(app.staticTexts[finalPassword].waitForExistence(timeout: UITest.timeout),
                      "detail must reveal exactly the generated password")
    }
}
```

- [ ] **Step 3: Verify**

Run: `bash scripts/test.sh --ui 2>&1 | tail -5`
Expected: PASS — **5 UI tests**. Known query pitfalls if something fails: SwiftUI `Toggle` may surface the switch nested (hence `.firstMatch`); swipe-action buttons only exist after the swipe animation settles (`waitForExistence` covers it).

- [ ] **Step 4: Commit**

```bash
git add GrooUITests
git commit -m "test: Pass CRUD lifecycle + password generator UI tests"
```

---

### Task 5: Wallet onboarding + tab-navigation smoke

**Files:**
- Create: `GrooUITests/WalletOnboardingUITests.swift`
- Create: `GrooUITests/TabNavigationUITests.swift`

**Interfaces:**
- Consumes: Task 3 identifiers; `WalletOnboardingView` requires `passService.isUnlocked` (so the test unlocks Pass first); `WalletManager.createWallet` runs real BIP39 + BIP32 keystore derivation (slow in Debug — 60s wait) and stores the wallet item through the stub PUT; per-tab markers recon'd from the views (`StockOnboardingView` "Stock Portfolio", `WalletOnboardingView` "Ethereum Wallet", Azan's principal-toolbar `Text("Azan")` → `app.navigationBars.staticTexts["Azan"]`, `PadUnlockView` "Pad is Locked", `PassUnlockView` "Pass is Locked", `DrivePlaceholderView` "Coming Soon", `ScratchpadTabView` "Scratchpad Locked", `SettingsView` `.navigationTitle("Settings")`, `HomeView`'s empty stocks card "Add your first stock").

- [ ] **Step 1: Create `GrooUITests/WalletOnboardingUITests.swift`**

```swift
//
//  WalletOnboardingUITests.swift
//  GrooUITests
//
//  Create-wallet onboarding up to — not including — real network: real BIP39
//  mnemonic + BIP32 address derivation, wallet item persisted through the
//  stub vault PUT, recovery-phrase screen verified, then the portfolio view
//  must render (its RPC/price calls all hit dead-end/stubbed URLs and may
//  show error/empty states — rendering without crashing is the contract).
//

import XCTest

final class WalletOnboardingUITests: XCTestCase {
    func testCreateWalletShowsRecoveryPhraseThenPortfolio() {
        let app = UITest.launchApp(selectedTab: "pass")
        // Wallet creation stores keys in the Pass vault — unlock it first
        UITest.unlockPass(app)

        UITest.openTab(app, "Wallet")
        let createButton = app.buttons["wallet.create"]
        XCTAssertTrue(createButton.waitForExistence(timeout: UITest.timeout))
        createButton.tap()

        // Real BIP39/keystore derivation is slow in Debug — generous wait
        XCTAssertTrue(app.staticTexts["Recovery Phrase"].waitForExistence(timeout: 60))

        // 12 numbered words (indices 1…12, and no 13th)
        XCTAssertTrue(app.staticTexts["12"].exists, "12th mnemonic word index missing")
        XCTAssertFalse(app.staticTexts["13"].exists, "mnemonic must be exactly 12 words")

        // Derived address is shown and well-formed
        let address = app.staticTexts["wallet.address"]
        XCTAssertTrue(address.waitForExistence(timeout: UITest.timeout))
        XCTAssertTrue(address.label.hasPrefix("0x"), "address must be hex: \(address.label)")
        XCTAssertEqual(address.label.count, 42, "address must be 20 bytes hex: \(address.label)")

        // Confirm backup → onboarding is replaced by the portfolio
        app.buttons["wallet.mnemonic.confirm"].tap()
        let portfolio = app.descendants(matching: .any).matching(identifier: "wallet.portfolio").firstMatch
        XCTAssertTrue(portfolio.waitForExistence(timeout: UITest.timeout),
                      "portfolio must render after onboarding (network-dependent content may be empty/error)")
        XCTAssertEqual(app.state, .runningForeground)
    }
}
```

- [ ] **Step 2: Create `GrooUITests/TabNavigationUITests.swift`**

```swift
//
//  TabNavigationUITests.swift
//  GrooUITests
//
//  Every tab renders its known marker without crashing. First Azan visit may
//  pop the system location alert — dismissed via springboard, sleep-free.
//

import XCTest

final class TabNavigationUITests: XCTestCase {
    func testEveryTabRendersWithoutCrashing() {
        let app = UITest.launchApp(selectedTab: "home")
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: UITest.timeout))

        let visits: [(tab: String, marker: XCUIElement)] = [
            ("Stocks", app.staticTexts["Stock Portfolio"]),          // empty-portfolio onboarding
            ("Wallet", app.staticTexts["Ethereum Wallet"]),          // wallet onboarding
            ("Azan", app.navigationBars.staticTexts["Azan"]),        // principal toolbar title
            ("Pad", app.staticTexts["Pad is Locked"]),
            ("Pass", app.staticTexts["Pass is Locked"]),
            ("Drive", app.staticTexts["Coming Soon"]),
            ("Scratchpad", app.staticTexts["Scratchpad Locked"]),
            ("Settings", app.navigationBars["Settings"]),
        ]

        for (tab, marker) in visits {
            UITest.openTab(app, tab)
            if tab == "Azan" {
                UITest.dismissSystemAlertIfPresent()
            }
            XCTAssertTrue(marker.waitForExistence(timeout: UITest.timeout), "\(tab) tab did not render its marker")
            XCTAssertEqual(app.state, .runningForeground, "\(tab) tab crashed the app")
        }

        // And back to Home (empty-state stocks card)
        UITest.openTab(app, "Home")
        XCTAssertTrue(app.staticTexts["Add your first stock"].waitForExistence(timeout: UITest.timeout))
        XCTAssertEqual(app.state, .runningForeground)
    }
}
```

- [ ] **Step 3: Verify**

Run: `bash scripts/test.sh --ui 2>&1 | tail -5`
Expected: PASS — **7 UI tests**. If `openTab` can't reach a tab, dump `app.tabBars.firstMatch.debugDescription` — the iOS 26 `.sidebarAdaptable` tab bar may name its overflow differently than "More"; fix the helper's fallback query from the observed hierarchy (the helper is the single place to fix).

- [ ] **Step 4: Commit**

```bash
git add GrooUITests
git commit -m "test: wallet create-onboarding + tab-navigation smoke UI tests"
```

---

### Task 6: Full verification + docs

**Files:**
- Modify: `README.md` (Testing conventions: three lines)

- [ ] **Step 1: Both suites twice (definition of done)**

Run: `bash scripts/test.sh --unit 2>&1 | tail -3 && bash scripts/test.sh --unit 2>&1 | tail -3`
Expected: `** TEST SUCCEEDED **` twice — 284 unit tests both runs.

Run: `bash scripts/test.sh --ui 2>&1 | tail -3 && bash scripts/test.sh --ui 2>&1 | tail -3`
Expected: `** TEST SUCCEEDED **` twice — 7 UI tests both runs. Two consecutive green UI runs is the flakiness gate; a single intermittent failure is a bug in the test, not a re-run candidate.

- [ ] **Step 2: All targets build**

Run: `xcodebuild build -project Groo.xcodeproj -scheme Groo -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Manual smoke (seam does not leak into normal runs)**

Launch the app normally (no `--uitest`) in the simulator: sign-in state, vault, and preferences behave exactly as before this phase (the UserDefaults wipe from UI-test runs will have cleared in-app preferences on this simulator — expected, documented).

- [ ] **Step 4: README lines**

In `README.md`'s Testing conventions list (after the Phase 4 lines), append:

```markdown
- UI tests launch the app with `--uitest` (seam: `Groo/Core/UITestMode.swift`): OAuth bypassed, UserDefaults wiped per launch, SwiftData in-memory, keychain faked, Pass API served by an in-process stub, all other base URLs dead-ended — flows exercise real crypto (PBKDF2/AES-GCM/BIP39) but never real APIs or real local data. Stub vault master password: `uitest-master-1`.
- UI-test element hooks are `accessibilityIdentifier`s namespaced by feature (`pass.unlock.password`, `passgen.value`, `wallet.create`, …). Identifiers are API — renaming one breaks GrooUITests.
- UI tests: no sleeps (`waitForExistence` + one predicate-expectation helper); every test launches a fresh app process; simulator hardware keyboard must be disconnected for `typeText`.
```

- [ ] **Step 5: Commit**

```bash
git add README.md
git commit -m "docs: README UI-testing conventions (--uitest seam, identifier namespace)"
```

- [ ] **Step 6: Final report**

Include in the report to the user:
- Final totals: **284 unit tests (37 suites) + 7 UI tests**, both green twice.
- The exact production seam surface (the five fenced files + identifier-only view edits — list them).
- Deferred flows and reasons (from the spec-coverage notes): GlobalLockView/biometric unlock UI, backgrounding-relock (feature doesn't exist — spec/product mismatch to resolve), OAuth login UI, wallet import UI, clipboard-content assertions.
- Product gaps observed during planning (not introduced):
  1. **No relock on backgrounding** — nothing observes `scenePhase` except Azan; an unlocked vault stays unlocked until process death or manual lock. The spec's Phase 5 wording assumed otherwise.
  2. **`PassView`'s folder filter is a TODO** (`onSelectFolder` just dismisses) — folder UI exists but does nothing.
  3. **`GlobalLockView`/`PassUnlockView` sign-out dialogs still say "PAT token"** — stale copy from the pre-OAuth flow.
  4. **`Config.coinGeckoBaseURL` existed but `CoinGeckoService` didn't use it** (hardcoded duplicate) — aligned in Task 2; `YahooFinanceService` still hardcodes its URLs (fine today because all call sites are holdings-guarded; needs the override pattern before any stocks UI flow).

---

## Post-plan

Remaining spec phase: 6 (edge-case sweep — unicode/size/date-boundary passes per suite; `PrayerTimeService` `now` seam; `YahooFinanceService` sleep seam + 429 tests; consume-or-remove decision for the ShareExtension queue). Phase 5 fast-follow candidates for the Phase 6 plan: backgrounding-relock product decision (then a UI test for it); a `SharedPendingItemsStore` fileURL seam through `PassService` to close the last read-only App Group touch under `--uitest`; wallet-import UI test; stocks add-holding UI flow behind a Yahoo `Config` override.
