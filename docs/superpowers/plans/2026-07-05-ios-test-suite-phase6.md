# iOS Test Suite — Phase 6 (FINAL: Edge-Case Sweep) + Accumulated Fast-Follows Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close out the test-suite retrofit with the spec's deliberate edge-case pass — unicode/emoji in every vault string field, maximum sizes, date boundaries (epoch counter-0 TOTP, year/leap/DST day-walks, Ramadan hijri detection), locale/currency formatting in the stocks math, and deterministic concurrent-actor races — plus every fast-follow the phase ledger accumulated: the pre-adjudicated cancel-mid-creation production fix for `pendingRecoveryPhraseReveal`, the `#if DEBUG` fence on `UITestMode`, per-toggle accessibility identifiers in the password generator, a `now` clock seam for `PrayerTimeService` (assessed cheap — included), and the injected-sleep seam + 429 retry tests `YahooFinanceService` was owed since Phase 2 gave one to CoinGecko.

**Architecture:** Three small production seams/fixes, all behavior-preserving in production:

1. **`WalletManager.createWallet` cooperative cancellation** (production FIX, pre-adjudicated in the P5 ledger): the create sheet's `.task` is the caller, so dismissing the sheet cancels it — but `createWallet` never checks. If the PUT completes after the sheet's `onDismiss` already fired `completeRecoveryPhraseReveal()`, the later `pendingRecoveryPhraseReveal = true` sticks forever: CryptoView never advances past onboarding and a second Create mints a second wallet. Fix: `try Task.checkCancellation()` before the vault write (cancelled users get nothing persisted) + an `if !Task.isCancelled` guard on the flag (covers a cancel landing while the PUT was in flight). Two lines of logic, pinned by unit tests.
2. **`UITestMode.isActive` compiled to `false` in Release** (pre-adjudicated): UI tests always run Debug builds; a shipped binary must not carry a `--uitest` auth/keychain/API bypass. The constant becomes `#if DEBUG`-gated; every downstream `isActive` branch folds to dead code in Release. No call site changes.
3. **`YahooFinanceService` gets the exact seam `CoinGeckoService` got in Phase 2**: an injected `sleep` closure (default: real `Task.sleep`) so 429 backoff is testable under the no-sleeps rule, including the same `attempt < maxAttempts - 1` guard CoinGecko received as an approved P2 deviation (today Yahoo wastes a 4s hang *after* the final failed attempt before throwing).
4. **`PrayerTimeService` gains `init(now: @escaping () -> Date = Date.init)`** — the Phase-4-flagged seam, assessed during recon as a mechanical 6-call-site `Date()` → `now()` substitution with zero behavior change (`PrayerTimeService()` call sites in `AzanView`/`HomeView` untouched). Its Adhan-wrapper logic (adjustments, sunrise-skip, qaza cutoffs, tomorrow-fajr rollover, Ramadan hijri math) becomes deterministically testable with *relational* assertions that hold in any host timezone.
5. **Everything else is test-only**: unicode fixture twins beside the canonical ones, TaskGroup concurrency races with invariant (not timing) assertions, and locale-robust currency assertions (digit-sequence projections, not separator-exact strings).

**Tech Stack:** Swift Testing (`@Test`/`#expect`/`#require`, `withThrowingTaskGroup` for races — no sleeps anywhere); `StubURLProtocol` under the `NetworkStubbedSuites` serialized umbrella for stubbed-network suites; XCUITest for the generator-toggle test update; `scripts/test.sh`.

**Spec:** `docs/superpowers/specs/2026-07-05-ios-test-suite-design.md` (Phase 6 section). Ledger: `.superpowers/sdd/progress.md` (P2/P4/P5 fast-follow notes).

## Spec-coverage notes (read before implementing)

The sweep is deliberate, not exhaustive — these areas were checked during recon and intentionally get nothing:

- **CryptoService / SharedCrypto (huge payloads, emoji)** — already covered since Phase 1: `CryptoServiceTests` parameterizes roundtrips over `["hello", "", "påsswörd 🔑🧨 中文", String(repeating: "x", count: 1_000_000)]`. Nothing to add.
- **TOTP far-future boundary** — already covered: the RFC 6238 vectors include `t = 20_000_000_000` (year 2603) and `t = 59`. Only the epoch counter-0 case (`t = 0`, eight `0x00` counter bytes — RFC 4226's `HOTP(0) = 755224`) is missing and added here.
- **EthereumService concurrency** — skipped. It is an actor whose only cross-call state is its injected session/cache; a TaskGroup race would re-test Swift's actor guarantees, not our code. `PassVaultStore` (multi-file writes that must stay paired) and `APICache` (in-flight dedup racing eviction) are where torn-state failure modes actually live — they get the races.
- **True DST-matrix testing of `PrayerTrackingService`** — its `yyyy-MM-dd` formatter uses the process-global timezone, which tests cannot vary without a formatter seam that isn't worth the surface. The date-boundary tests instead use fixed instants around the 2026 US spring-forward, the 2028 leap day, and the 2026 year boundary with assertions valid in **any** host timezone (uniqueness/consecutiveness/streak counts, never absolute date strings — except leap day, which is inside the 7-day window for every timezone within ±14h of UTC).
- **`PasswordGeneratorView.generatePassword` unit tests** — it is a private method on a `View`; the charset/length contracts are already pinned end-to-end by the generator UI test. Extracting a generator type would be a refactor without a driving defect. Skipped.
- **`StockPortfolioManager.displayCurrency` defaults seam** — still `UserDefaults.standard`-backed (P4 gap note). Rather than adding a production seam, the new currency suite pins the key to `USD` and restores the previous value around each test, inside the serialized umbrella. Documented, deliberate.
- **Wallet-import UI test, stocks add-holding UI flow, ShareExtension consume-or-remove, backgrounding-relock** — P5 post-plan candidates that are product/priority decisions, not edge-case sweep work. Restated in the final report (Task 7), not implemented.
- **`PrayerTimeService` timer paths** — `configure` schedules a 1s repeating `Timer`; in the test host the main run loop doesn't spin it, and with a fixed clock `tickCountdown`/`recalculate` are idempotent, so leftover timers cannot flake. The tick path itself stays untested (it only re-derives state already pinned).
- **Ramadan label first-pass lag (observed product quirk, not fixed):** `recalculate()` builds `todayPrayers` (whose rows read `ramadanInfo` for their labels) *before* `updateRamadanInfo()` runs, so the first calculation after `configure` has `ramadanInfo` set but row labels still `nil`; they appear on the next recalculation. The Ramadan test documents this by asserting after an explicit second `recalculate()`. Flag in the final report — cosmetic, one-line fix candidate (`updateRamadanInfo` before the row build), left for a product decision.

## Global Constraints

- Working directory: `/Users/groo/work/gr/ios`, branch `ios-test-suite-phase6` off `main` (per prior phases). Runner: `bash scripts/test.sh --unit` / `--ui` → `** TEST SUCCEEDED **`.
- **Baseline: 284 unit tests in 37 suites + 7 UI tests**, all green. Running totals (verify in the xcodebuild summary; if a count differs, find out why before committing):
  - After Task 1: **286 unit** (+2, WalletManager cancellation)
  - After Task 2: 286 unit + **7 UI** (both suites must stay green; Release config must build)
  - After Task 3: **289 unit** (+3, Yahoo 429 retry)
  - After Task 4: **297 unit, 38 suites** (+8, new `PrayerTimeServiceTests`)
  - After Task 5: **304 unit** (+7, unicode/size/epoch sweep)
  - After Task 6: **316 unit, 39 suites** (+12, currency/date-boundary/concurrency; new `StockPortfolioCurrencyTests`)
- `GrooTests/` and `GrooUITests/` are synchronized folders — new `.swift` files compile automatically. **`Shared/` and the pbxproj are untouched this phase.**
- Production edits are confined to five files: `WalletManager.swift`, `UITestMode.swift`, `PasswordGeneratorView.swift` (identifier-only), `YahooFinanceService.swift`, `PrayerTimeService.swift`. Every one is behavior-preserving for production callers (default parameters, identifier chains, a compile-time Release constant, and the two-line cancellation fix whose branches are unreachable outside a cancelled task).
- **No sleeps, no timing assertions.** Backoff is recorded via injected sleep closures; concurrency tests assert *invariants over every interleaving* (torn pairs, wrong bodies, inconsistent terminal state), never orderings or durations.
- Locale rule for currency tests: never assert a separator- or symbol-exact string unless the formatter pins its own locale (the INR/en_IN branch does). Everywhere else project to the digit sequence (`s.filter(\.isNumber)`).
- Money math in tests uses dyadic values (…, 0.0078125 = 2⁻⁷, 150, 20 000) so `Double` sums compare with `==` — the established suite convention.
- Tests are coverage over recon'd contracts (and TDD for the seams/fix): if an assertion fails against production, **STOP and report** — never adjust the assertion to match observed behavior without adjudication. (Exception: the two TDD tests in Tasks 1 and 3 are *expected* red before their production edit lands.)
- Before each commit: `bash scripts/test.sh --unit` green; Tasks 1–4 additionally build the app (`xcodebuild build -project Groo.xcodeproj -scheme Groo -destination 'platform=iOS Simulator,name=iPhone 17 Pro'` — compiles all 6 targets); Task 2 additionally runs `bash scripts/test.sh --ui` and a Release-configuration build.

---

### Task 1: Production fix — cooperative cancellation in `WalletManager.createWallet` (TDD)

**Files:**
- Modify: `GrooTests/Features/Crypto/WalletManagerTests.swift` (append two tests)
- Modify: `Groo/Features/Crypto/Services/WalletManager.swift` (two edits inside `createWallet`)

**Interfaces:**
- Consumes: `WalletManagerTests.makeWalletEnv()/tearDown(_:)` (unlocked stubbed vault + isolated defaults), `WalletManager.pendingRecoveryPhraseReveal` (`private(set)`, readable), `completeRecoveryPhraseReveal()`, `Task.checkCancellation()`/`Task.isCancelled`.
- Produces: `createWallet` that (a) throws `CancellationError` before persisting anything when its task is already cancelled, and (b) never sets `pendingRecoveryPhraseReveal` from a cancelled task. Uncancelled behavior byte-identical.
- Bug provenance: P5 Task 5 ledger — "P6 fast-follow: cancel-mid-creation stuck pendingRecoveryPhraseReveal state". The sheet's `onDismiss` (`WalletOnboardingView.swift:111-115`) is the *only* thing that clears the flag; it fires at dismissal, which is *before* a still-running `createWallet` reaches `pendingRecoveryPhraseReveal = true` (`WalletManager.swift:166`).

- [ ] **Step 1: Write the failing test (RED)**

In `GrooTests/Features/Crypto/WalletManagerTests.swift`, after `deleteWalletRemovesItemCacheAndReassignsActive` (before the struct's closing braces), append:

```swift

    // MARK: - Cancellation (Phase 6 production fix)

    /// P5 ledger bug: dismissing the create sheet cancels its .task (our
    /// caller), but onDismiss has already fired completeRecoveryPhraseReveal —
    /// so a createWallet that keeps running and then sets
    /// pendingRecoveryPhraseReveal = true strands the flag true forever:
    /// CryptoView never advances past onboarding, and tapping Create again
    /// mints a second wallet.
    @Test func cancelledCreateWalletThrowsAndStrandsNoState() async throws {
        let walletEnv = try await Self.makeWalletEnv()
        defer { Self.tearDown(walletEnv) }

        // Enqueue the child on the MainActor, then cancel before it can
        // start: this test is MainActor-isolated and does not suspend before
        // cancel(), so the child's first instruction observes isCancelled.
        let create = Task { @MainActor in
            try await walletEnv.manager.createWallet()
        }
        create.cancel()

        await #expect(throws: CancellationError.self) {
            _ = try await create.value
        }
        #expect(walletEnv.manager.pendingRecoveryPhraseReveal == false)
        #expect(walletEnv.manager.hasWallets == false)
        #expect(walletEnv.manager.getWalletItems().isEmpty)   // nothing persisted
        #expect(walletEnv.manager.isLoading == false)          // defer reset ran
    }

    @Test func completedCreateSetsRevealFlagUntilCompleted() async throws {
        let walletEnv = try await Self.makeWalletEnv()
        defer { Self.tearDown(walletEnv) }

        _ = try await walletEnv.manager.createWallet()

        // The flag is what holds CryptoView on the onboarding flow until the
        // recovery phrase has been shown (P5 fix badc2e4); the sheet's
        // onDismiss clears it via completeRecoveryPhraseReveal.
        #expect(walletEnv.manager.pendingRecoveryPhraseReveal)
        walletEnv.manager.completeRecoveryPhraseReveal()
        #expect(walletEnv.manager.pendingRecoveryPhraseReveal == false)
    }
```

Run: `bash scripts/test.sh --unit 2>&1 | tail -5`
Expected: **FAIL** — `cancelledCreateWalletThrowsAndStrandsNoState` is red. The exact failing assertion depends on how far the cancelled task got before an incidental error (a wrapped `URLError.cancelled` instead of `CancellationError`, a persisted vault item, or the stuck flag) — *any* of those is the bug's signature. `completedCreateSetsRevealFlagUntilCompleted` should already pass (it pins existing behavior so the fix can't regress it). If the cancellation test *passes* before the fix, STOP and report — the recon'd failure mode doesn't reproduce and the fix needs re-adjudication.

- [ ] **Step 2: The fix (GREEN)**

In `Groo/Features/Crypto/Services/WalletManager.swift`, inside `createWallet()`:

(a) Immediately before `try await passService.addItem(.cryptoWallet(walletItem))`, insert:

```swift
        // The create sheet's .task is our caller — dismissing the sheet
        // cancels it. Past this point we mutate shared state (vault, reveal
        // flag, address cache); if the user already cancelled, stop cleanly
        // instead of persisting a wallet they never saw.
        try Task.checkCancellation()

```

(b) Replace:

```swift
        // Hold CryptoView on the onboarding flow until the recovery phrase
        // has been shown — set before the walletAddresses append flips
        // hasWallets.
        pendingRecoveryPhraseReveal = true
```

with:

```swift
        // Hold CryptoView on the onboarding flow until the recovery phrase
        // has been shown — set before the walletAddresses append flips
        // hasWallets. Skipped when the sheet was dismissed while the vault
        // PUT was in flight: its onDismiss (completeRecoveryPhraseReveal)
        // has already fired, so setting the flag now would strand it true
        // with nothing left to clear it.
        if !Task.isCancelled {
            pendingRecoveryPhraseReveal = true
        }
```

Note the two layers: the `checkCancellation` handles cancel-before-persist (the deterministic test path and the common user path — derivation is the slow part); the `isCancelled` guard handles a cancel that lands during the PUT suspension when `URLSession` happens not to throw. In that residual window the wallet *is* persisted (correct — the write completed) but the flag is not set, so CryptoView advances to the portfolio and the seed phrase remains viewable in the Pass vault item.

- [ ] **Step 3: Verify**

Run: `bash scripts/test.sh --unit 2>&1 | tail -5`
Expected: PASS — **286 tests** (284 + 2). The pre-existing create/import tests prove uncancelled behavior is unchanged.

Run: `xcodebuild build -project Groo.xcodeproj -scheme Groo -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add Groo/Features/Crypto/Services/WalletManager.swift GrooTests/Features/Crypto/WalletManagerTests.swift
git commit -m "fix: cooperative cancellation in WalletManager.createWallet (stuck pendingRecoveryPhraseReveal) + tests"
```

---

### Task 2: Release hardening (`#if DEBUG` on UITestMode) + per-toggle generator identifiers

**Files:**
- Modify: `Groo/Core/UITestMode.swift` (one edit)
- Modify: `Groo/Features/Pass/Views/PasswordGeneratorView.swift` (identifier plumbing, zero behavior)
- Modify: `GrooUITests/PasswordGeneratorUITests.swift` (full-file replacement — drop label-coupled switch queries)

**Interfaces:**
- Consumes: `UITestMode.isActive` (the single fencing condition — all four fenced production files branch on it), SwiftUI `Toggle`, XCUITest `XCTNSPredicateExpectation`.
- Produces: `isActive` that is compile-time `false` in Release; toggle identifiers `passgen.toggle.uppercase/lowercase/numbers/symbols` (new namespace entries — identifiers are API from the moment they land).

- [ ] **Step 1: Fence `UITestMode.isActive` to Debug**

In `Groo/Core/UITestMode.swift`, replace:

```swift
    /// The single fencing condition for every UI-test seam in the app.
    static let isActive = ProcessInfo.processInfo.arguments.contains("--uitest")
```

with:

```swift
    /// The single fencing condition for every UI-test seam in the app.
    /// Compile-time false in Release: UI tests always run Debug builds, and
    /// a shipped binary must not carry a "--uitest" auth/keychain/API bypass.
    #if DEBUG
    static let isActive = ProcessInfo.processInfo.arguments.contains("--uitest")
    #else
    static let isActive = false
    #endif
```

(The rest of the file still compiles in Release — `activateIfNeeded()` guards on `isActive`, and the stub types become unreachable dead code. Only the activation condition needs the fence; wrapping the whole file would break the four fenced call sites' compilation.)

- [ ] **Step 2: Per-toggle identifiers in `PasswordGeneratorView`**

Replace the `characterToggle` helper:

```swift
    private func characterToggle(title: String, isOn: Binding<Bool>, disabled: Bool) -> some View {
        Toggle(title, isOn: isOn)
            .disabled(disabled)
            .onChange(of: isOn.wrappedValue) { _, _ in
                generatePassword()
            }
    }
```

with:

```swift
    private func characterToggle(title: String, identifier: String, isOn: Binding<Bool>, disabled: Bool) -> some View {
        Toggle(title, isOn: isOn)
            .disabled(disabled)
            .accessibilityIdentifier(identifier)
            .onChange(of: isOn.wrappedValue) { _, _ in
                generatePassword()
            }
    }
```

and update the four call sites in `optionsSection`:

```swift
            // Character type toggles
            VStack(spacing: Theme.Spacing.sm) {
                characterToggle(
                    title: "Uppercase (A-Z)",
                    identifier: "passgen.toggle.uppercase",
                    isOn: $includeUppercase,
                    disabled: !includeLowercase && !includeNumbers && !includeSymbols
                )

                characterToggle(
                    title: "Lowercase (a-z)",
                    identifier: "passgen.toggle.lowercase",
                    isOn: $includeLowercase,
                    disabled: !includeUppercase && !includeNumbers && !includeSymbols
                )

                characterToggle(
                    title: "Numbers (0-9)",
                    identifier: "passgen.toggle.numbers",
                    isOn: $includeNumbers,
                    disabled: !includeUppercase && !includeLowercase && !includeSymbols
                )

                characterToggle(
                    title: "Symbols (!@#$...)",
                    identifier: "passgen.toggle.symbols",
                    isOn: $includeSymbols,
                    disabled: !includeUppercase && !includeLowercase && !includeNumbers
                )
            }
```

- [ ] **Step 3: Replace `GrooUITests/PasswordGeneratorUITests.swift`**

Full-file replacement (the toggle block moves from label-addressed, fire-and-hope coordinate taps to identifier-addressed taps that *verify the flip* — a hit-target regression now fails at the toggle, loudly, instead of three assertions later):

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
    /// Flip a Toggle by accessibility identifier. SwiftUI renders the row as
    /// a wide switch element whose center is the label area, so the tap
    /// lands near the trailing edge where the actual control sits — but the
    /// flip is verified by value (run-loop wait, not a sleep), so a
    /// hit-target regression fails here instead of corrupting later asserts.
    private func flipToggle(_ app: XCUIApplication, _ identifier: String) {
        let toggle = app.switches[identifier].firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: UITest.timeout), "toggle \(identifier) not found")
        let before = (toggle.value as? String) ?? ""
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        let flipped = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value != %@", before),
            object: toggle
        )
        XCTAssertEqual(XCTWaiter().wait(for: [flipped], timeout: 5), .completed,
                       "toggle \(identifier) did not flip from \(before)")
    }

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

        // Options respected: switch off everything but numbers, addressed by
        // identifier (Phase 6 fast-follow — no more label-text coupling)
        flipToggle(app, "passgen.toggle.uppercase")
        flipToggle(app, "passgen.toggle.lowercase")
        flipToggle(app, "passgen.toggle.symbols")
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

If `app.switches[identifier]` matches nothing, the identifier landed on a different element type in the tree — dump `app.debugDescription` at the failure and fix the *query* (e.g. `app.otherElements[identifier].switches.firstMatch`), never by reverting to label text.

- [ ] **Step 4: Verify (Debug + Release + UI)**

Run: `bash scripts/test.sh --unit 2>&1 | tail -3`
Expected: PASS — 286 tests (`isActive` is unchanged in the Debug test host).

Run: `bash scripts/test.sh --ui 2>&1 | tail -5`
Expected: PASS — **7 UI tests** (UI tests build Debug; the seam is intact; the generator test now drives identifier-addressed toggles).

Run: `xcodebuild build -project Groo.xcodeproj -scheme Groo -configuration Release -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **` — this is the point of the task: the Release binary compiles with `isActive == false` and no `--uitest` surface.

Run: `xcodebuild build -project Groo.xcodeproj -scheme Groo -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **` (Debug, all 6 targets).

- [ ] **Step 5: Commit**

```bash
git add Groo/Core/UITestMode.swift Groo/Features/Pass/Views/PasswordGeneratorView.swift GrooUITests/PasswordGeneratorUITests.swift
git commit -m "fix: compile UITestMode.isActive to false in Release; test: identifier-addressed generator toggles"
```

---

### Task 3: `YahooFinanceService` injected-sleep seam + 429 retry tests (TDD)

**Files:**
- Modify: `GrooTests/Features/Stocks/YahooFinanceServiceTests.swift` (append recorder + three tests; update header comment)
- Modify: `Groo/Features/Stocks/Services/YahooFinanceService.swift` (seam + `withRetry` alignment)

**Interfaces:**
- Consumes: `CoinGeckoService`'s seam as the template (`Groo/Features/Crypto/Services/CoinGeckoService.swift:16,24-31,33-61` — injected `@Sendable (Double) async throws -> Void` sleep, `attempt < maxAttempts - 1` guards), `StubURLProtocol` last-response-repeats semantics, `APICacheError.httpError(statusCode:data:)` (what `cache.fetch` throws for a 429), existing `YahooFinanceServiceTests.chartJSON(price:previousClose:currency:)` fixture.
- Produces: `YahooFinanceService(cache:sleep:)` — production callers (`YahooFinanceService(cache:)` / `YahooFinanceService()`) unchanged via the default. Behavior delta (approved, mirrors the P2 CoinGecko deviation): the final failed attempt no longer sleeps 4s before throwing.

- [ ] **Step 1: Write the failing tests (RED — they don't compile without the seam)**

In `GrooTests/Features/Stocks/YahooFinanceServiceTests.swift`:

(a) Replace the header comment lines:

```swift
//  Quote/search/exchange-rate parsing over a stubbed APICache session.
//  The 429 retry path uses real Task.sleep and is deliberately untested
//  (no-sleeps rule) — flagged in the phase plan.
```

with:

```swift
//  Quote/search/exchange-rate parsing over a stubbed APICache session,
//  plus 429 retry/backoff with recorded (never slept) delays.
```

(b) After the last existing test (before the struct's closing braces), append:

```swift

    // MARK: - 429 retry/backoff (Phase 6 fast-follow — mirrors CoinGeckoServiceTests)

    /// Records backoff delays instead of sleeping — the no-sleeps rule.
    final class SleepRecorder: @unchecked Sendable {
        private let lock = NSLock()
        private var _delays: [Double] = []
        var delays: [Double] { lock.lock(); defer { lock.unlock() }; return _delays }
        func record(_ delay: Double) { lock.lock(); defer { lock.unlock() }; _delays.append(delay) }
    }

    static func makeRetryService() -> (service: YahooFinanceService, sleeps: SleepRecorder) {
        let recorder = SleepRecorder()
        let cache = APICache(sessionConfiguration: StubURLProtocol.stubbedConfiguration())
        return (YahooFinanceService(cache: cache) { recorder.record($0) }, recorder)
    }

    @Test func rateLimitRetriesWithExponentialBackoffThenThrows() async {
        StubURLProtocol.reset()
        StubURLProtocol.enqueue(method: "GET", pathSuffix: "/chart/AAPL", status: 429, json: "{}")
        // last-response-repeats: every attempt sees 429
        let (service, sleeps) = Self.makeRetryService()

        await #expect {
            _ = try await service.getQuote(symbol: "AAPL")
        } throws: { error in
            guard case YahooFinanceError.httpError(429) = error else { return false }
            return true
        }

        // 2^0, 2^1 between three attempts — and NO terminal sleep after the
        // last failure (the pre-existing 4s hang this seam also removes)
        #expect(sleeps.delays == [1.0, 2.0])
        #expect(StubURLProtocol.recordedRequests.count == 3)   // maxAttempts
    }

    @Test func rateLimitRecoversOnLaterAttempt() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.enqueue(method: "GET", pathSuffix: "/chart/AAPL", status: 429, json: "{}")
        StubURLProtocol.enqueue(method: "GET", pathSuffix: "/chart/AAPL",
                                json: Self.chartJSON(price: "150.0", previousClose: "200.0"))
        let (service, sleeps) = Self.makeRetryService()

        let quote = try await service.getQuote(symbol: "AAPL")

        #expect(quote.price == 150)
        #expect(sleeps.delays == [1.0])
    }

    @Test func non429HttpErrorDoesNotRetry() async {
        StubURLProtocol.reset()
        StubURLProtocol.enqueue(method: "GET", pathSuffix: "/chart/AAPL", status: 500, json: "{}")
        let (service, sleeps) = Self.makeRetryService()

        await #expect {
            _ = try await service.getQuote(symbol: "AAPL")
        } throws: { error in
            guard case YahooFinanceError.httpError(500) = error else { return false }
            return true
        }

        #expect(sleeps.delays.isEmpty)
        #expect(StubURLProtocol.recordedRequests.count == 1)
    }
```

Run: `bash scripts/test.sh --unit 2>&1 | tail -5`
Expected: **FAIL to compile** (`YahooFinanceService` has no `sleep` parameter). That is the red step.

- [ ] **Step 2: The seam (GREEN)**

In `Groo/Features/Stocks/Services/YahooFinanceService.swift`:

(a) Replace:

```swift
    /// Testing seam: inject an APICache over a stubbed session. Production
    /// callers share the process-wide cache.
    init(cache: APICache = .shared) {
        self.decoder = JSONDecoder()
        self.cache = cache
    }
```

with:

```swift
    private let sleep: @Sendable (Double) async throws -> Void

    /// Testing seams: inject an APICache over a stubbed session, and a
    /// recorded sleep for 429 backoff (same shape as CoinGeckoService's).
    /// Production callers share the process-wide cache and really sleep.
    init(
        cache: APICache = .shared,
        sleep: @escaping @Sendable (Double) async throws -> Void = { try await Task.sleep(for: .seconds($0)) }
    ) {
        self.decoder = JSONDecoder()
        self.cache = cache
        self.sleep = sleep
    }
```

(The new `private let sleep` property sits with the other stored properties; keep it adjacent to the init for readability, matching CoinGeckoService's layout.)

(b) Replace the whole `withRetry` with the CoinGecko-aligned version (injected sleep + no terminal sleep):

```swift
    private func withRetry<T>(maxAttempts: Int = 3, _ operation: () async throws -> T) async throws -> T {
        var lastError: Error = YahooFinanceError.invalidResponse
        for attempt in 0..<maxAttempts {
            do {
                return try await operation()
            } catch YahooFinanceError.httpError(let code) where code == 429 {
                lastError = YahooFinanceError.httpError(429)
                if attempt < maxAttempts - 1 {
                    let delay = pow(2.0, Double(attempt))
                    logger.info("Rate limited, retrying in \(delay)s (attempt \(attempt + 1)/\(maxAttempts))")
                    try await sleep(delay)
                }
            } catch let error as APICacheError {
                if case .httpError(let code, _) = error, code == 429 {
                    lastError = YahooFinanceError.httpError(429)
                    if attempt < maxAttempts - 1 {
                        let delay = pow(2.0, Double(attempt))
                        logger.info("Rate limited, retrying in \(delay)s (attempt \(attempt + 1)/\(maxAttempts))")
                        try await sleep(delay)
                    }
                } else if case .httpError(let code, _) = error {
                    throw YahooFinanceError.httpError(code)
                } else {
                    throw error
                }
            } catch {
                throw error
            }
        }
        throw lastError
    }
```

- [ ] **Step 3: Verify**

Run: `bash scripts/test.sh --unit 2>&1 | tail -5`
Expected: PASS — **289 tests** (286 + 3). All pre-existing Yahoo tests still green (parsing paths untouched).

Run: `xcodebuild build -project Groo.xcodeproj -scheme Groo -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add Groo/Features/Stocks/Services/YahooFinanceService.swift GrooTests/Features/Stocks/YahooFinanceServiceTests.swift
git commit -m "feat: injected-sleep seam for YahooFinanceService 429 backoff + retry tests (drops terminal sleep)"
```

---

### Task 4: `PrayerTimeService` clock seam + deterministic Adhan-wrapper tests

**Files:**
- Modify: `Groo/Features/Azan/Services/PrayerTimeService.swift` (`now` seam — mechanical)
- Create: `GrooTests/Features/Azan/PrayerTimeServiceTests.swift`

**Interfaces:**
- Consumes: `LocalAzanPreferences(asrAdjustment:)`-style memberwise init (constructible standalone — the `AzanPreferencesTests` pattern), `PrayerTimeService.configure(latitude:longitude:preferences:)`, `todayPrayers`/`nextPrayer`/`currentPrayerDeadline`/`ramadanInfo`, `calculatePrayerTimes(forDays:)`, `Prayer` case order `fajr, sunrise, dhuhr, asr, sunset, maghrib, isha` (verified in `AzanModels.swift:14`).
- Produces: `PrayerTimeService(now:)` with `Date.init` default — `PrayerTimeService()` call sites (`AzanView.swift:14`, `HomeView.swift:30`) untouched.
- Determinism strategy: fixed epoch instants + **relational** assertions (ordering, exact deltas, cross-service equality of same-day times) that hold in any host timezone; the only absolute-calendar assertions are the Hijri-month checks, placed mid-Ramadan with a ±2-day guard band. `configure`'s 1s `Timer` never fires in the test host (main run loop isn't spun) and would be idempotent under a fixed clock anyway.

- [ ] **Step 1: The seam (mechanical `Date()` → injected clock)**

In `Groo/Features/Azan/Services/PrayerTimeService.swift`:

(a) After `private var preferences: LocalAzanPreferences?`, add:

```swift

    /// Injected clock. Tests pass fixed instants so "today", next-prayer
    /// selection, qaza deadlines, and Ramadan detection are deterministic;
    /// production uses the real clock. Zero behavior change.
    private let now: () -> Date

    init(now: @escaping () -> Date = Date.init) {
        self.now = now
    }
```

(b) In `recalculate()`, replace:

```swift
        let cal = Calendar.current
        let today = cal.dateComponents([.year, .month, .day], from: Date())
```

with:

```swift
        let now = self.now()
        let cal = Calendar.current
        let today = cal.dateComponents([.year, .month, .day], from: now)
```

and delete the later, now-redundant line inside the same function:

```swift
        let now = Date()
```

(c) In `calculatePrayerTimes(forDays:)`, replace `cal.date(byAdding: .day, value: dayOffset, to: Date())` with `cal.date(byAdding: .day, value: dayOffset, to: now())`.

(d) In `jumuahReminderTime(minutesBefore:)`, replace `var date = Date()` with `var date = now()`.

(e) In `qazaCutoff(for:from:)`, replace the isha fallback `?? Date())` with `?? now())` and the default case `return Date()` with `return now()`.

(f) In `updateRamadanInfo(prayerTimes:)`, replace `let now = Date()` with `let now = self.now()`.

(g) In `tickCountdown()`, replace `let now = Date()` with `let now = self.now()`.

Grep check before moving on: `grep -n "Date()" Groo/Features/Azan/Services/PrayerTimeService.swift` must return no matches (only `now()`/`self.now()` remain; `Date` as a type and `Date(timeIntervalSince...)` constructions don't exist in this file).

- [ ] **Step 2: Create `GrooTests/Features/Azan/PrayerTimeServiceTests.swift`**

```swift
//
//  PrayerTimeServiceTests.swift
//  GrooTests
//
//  Adhan-wrapper logic over an injected clock: chronology, minute
//  adjustments, sunrise-skip, qaza deadlines, tomorrow-fajr rollover,
//  multi-day calculation, Ramadan hijri detection. All assertions are
//  relational (orderings, exact deltas, cross-service equality) so they
//  hold in any host timezone; absolute times are Adhan's business and the
//  library itself is out of scope (spec: we test our usage of it).
//

import Foundation
import Testing
@testable import Groo

@MainActor
struct PrayerTimeServiceTests {
    // Dubai — low latitude, so all prayer times exist and stay well-ordered
    // year-round in every timezone's rendering of "today".
    static let latitude = 25.2048
    static let longitude = 55.2708

    static let julyNoon = Date(timeIntervalSince1970: 1_783_252_800)      // 2026-07-05T12:00:00Z
    static let ramadanMidMonth = Date(timeIntervalSince1970: 1_772_355_600) // 2026-03-01T09:00:00Z (≈ Ramadan 11, 1447 AH)

    static func makeService(nowAt instant: Date,
                            preferences: LocalAzanPreferences = LocalAzanPreferences()) -> PrayerTimeService {
        let service = PrayerTimeService(now: { instant })
        service.configure(latitude: latitude, longitude: longitude, preferences: preferences)
        return service
    }

    static func time(of prayer: Prayer, in service: PrayerTimeService) throws -> Date {
        try #require(service.todayPrayers.first(where: { $0.prayer == prayer }), "no \(prayer.rawValue) row").time
    }

    // MARK: - Chronology & visibility

    @Test func defaultVisiblePrayersAreChronological() {
        let service = Self.makeService(nowAt: Self.julyNoon)

        // Default prefs: sunrise shown, sunset hidden → 6 rows in case order
        #expect(service.todayPrayers.map(\.prayer) == [.fajr, .sunrise, .dhuhr, .asr, .maghrib, .isha])
        let times = service.todayPrayers.map(\.time)
        #expect(zip(times, times.dropFirst()).allSatisfy { $0 < $1 },
                "prayer times must be strictly increasing: \(times)")
    }

    // MARK: - Minute adjustments

    @Test func asrAdjustmentShiftsExactlyThirtyMinutes() throws {
        let baseline = Self.makeService(nowAt: Self.julyNoon)
        let adjusted = Self.makeService(nowAt: Self.julyNoon,
                                        preferences: LocalAzanPreferences(asrAdjustment: 30))

        let baseAsr = try Self.time(of: .asr, in: baseline)
        let shiftedAsr = try Self.time(of: .asr, in: adjusted)
        #expect(shiftedAsr == baseAsr.addingTimeInterval(30 * 60))

        // And an unadjusted prayer is untouched
        let baseFajr = try Self.time(of: .fajr, in: baseline)
        let adjustedFajr = try Self.time(of: .fajr, in: adjusted)
        #expect(adjustedFajr == baseFajr)
    }

    // MARK: - Next prayer selection

    /// Sunrise is not a prayer: between fajr and sunrise the "next prayer"
    /// countdown must point at Dhuhr, not sunrise.
    @Test func nextPrayerSkipsSunriseToDhuhr() throws {
        let baseline = Self.makeService(nowAt: Self.julyNoon)
        let sunrise = try Self.time(of: .sunrise, in: baseline)
        let dhuhr = try Self.time(of: .dhuhr, in: baseline)

        let betweenFajrAndSunrise = Self.makeService(nowAt: sunrise.addingTimeInterval(-60))
        let next = try #require(betweenFajrAndSunrise.nextPrayer)
        #expect(next.prayer == .dhuhr)
        #expect(next.time == dhuhr)
    }

    /// After Isha the day is over: next is TOMORROW's Fajr, and Isha stays
    /// the active prayer with tomorrow's Fajr as its qaza deadline.
    @Test func afterIshaNextIsTomorrowsFajrAndIshaRunsUntilIt() throws {
        let baseline = Self.makeService(nowAt: Self.julyNoon)
        let isha = try Self.time(of: .isha, in: baseline)
        let afterIshaInstant = isha.addingTimeInterval(60)

        let afterIsha = Self.makeService(nowAt: afterIshaInstant)
        let next = try #require(afterIsha.nextPrayer)
        #expect(next.prayer == .fajr)
        #expect(next.time > afterIshaInstant, "tomorrow's fajr must be in the future")

        let deadline = try #require(afterIsha.currentPrayerDeadline)
        #expect(deadline.prayer == .isha)
        #expect(deadline.deadline == next.time, "isha's qaza cutoff is tomorrow's fajr")
    }

    // MARK: - Qaza deadlines

    @Test func fajrQazaDeadlineEndsAtSunrise() throws {
        let baseline = Self.makeService(nowAt: Self.julyNoon)
        let fajr = try Self.time(of: .fajr, in: baseline)
        let sunrise = try Self.time(of: .sunrise, in: baseline)

        let justAfterFajr = Self.makeService(nowAt: fajr.addingTimeInterval(60))
        let deadline = try #require(justAfterFajr.currentPrayerDeadline)
        #expect(deadline.prayer == .fajr)
        #expect(deadline.deadline == sunrise)
        #expect(deadline.remaining > 0)
    }

    // MARK: - Multi-day calculation (notification scheduling)

    @Test func multiDayCalculationCoversConsecutiveDays() {
        let service = Self.makeService(nowAt: Self.julyNoon)

        let days = service.calculatePrayerTimes(forDays: 3)

        #expect(days.count == 3)
        #expect(days.allSatisfy { $0.prayers.count == Prayer.allCases.count })
        let fajrs = days.compactMap { day in day.prayers.first(where: { $0.0 == .fajr })?.1 }
        #expect(fajrs.count == 3)
        for (earlier, later) in zip(fajrs, fajrs.dropFirst()) {
            let gap = later.timeIntervalSince(earlier)
            // Consecutive local days: ~24h apart (DST/solar drift stays well inside ±3h)
            #expect(gap > 21 * 3600 && gap < 27 * 3600, "fajr gap \(gap)s is not one day")
        }
    }

    // MARK: - Ramadan (hijri boundary)

    @Test func ramadanMidMonthDetectedWithIftarAtMaghrib() throws {
        let service = Self.makeService(nowAt: Self.ramadanMidMonth)

        let info = try #require(service.ramadanInfo, "2026-03-01 is mid-Ramadan 1447 in every timezone within ±14h")
        #expect(info.isRamadan)
        // 1 Ramadan 1447 (Umm al-Qura) ≈ 2026-02-19; the host timezone shifts
        // the local date ±1 and the after-Maghrib rule adds +1 → guard band.
        #expect((8...15).contains(info.day), "expected mid-Ramadan, got day \(info.day)")
        let maghrib = try Self.time(of: .maghrib, in: service)
        let fajr = try Self.time(of: .fajr, in: service)
        #expect(info.iftarTime == maghrib)
        #expect(info.suhoorTime == fajr)
        #expect(info.fastingDuration == maghrib.timeIntervalSince(fajr))

        // Product quirk (observed, not fixed here): the first recalculate
        // builds the rows BEFORE updateRamadanInfo runs, so row labels lag
        // one pass. Assert them after an explicit second recalculation, and
        // flag the lag in the final report.
        service.recalculate()
        let fajrLabel = service.todayPrayers.first(where: { $0.prayer == .fajr })?.ramadanLabel
        let maghribLabel = service.todayPrayers.first(where: { $0.prayer == .maghrib })?.ramadanLabel
        #expect(fajrLabel == "Suhoor ends")
        #expect(maghribLabel == "Iftar")
    }

    @Test func nonRamadanDateHasNilRamadanInfo() {
        let service = Self.makeService(nowAt: Self.julyNoon)   // Muharram/Dhu al-Hijjah territory
        #expect(service.ramadanInfo == nil)
        #expect(service.todayPrayers.allSatisfy { $0.ramadanLabel == nil })
    }
}
```

- [ ] **Step 3: Verify**

Run: `bash scripts/test.sh --unit 2>&1 | tail -5`
Expected: PASS — **297 tests, 38 suites** (289 + 8). If `ramadanMidMonthDetectedWithIftarAtMaghrib` fails on the `day` band, print the actual hijri day and STOP — that means the Umm-al-Qura assumption is off, and the fixture instant (not the band) should be re-derived, with adjudication.

Run: `xcodebuild build -project Groo.xcodeproj -scheme Groo -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **` (WidgetExtension has its own copy of the deadline logic — untouched).

- [ ] **Step 4: Commit**

```bash
git add Groo/Features/Azan/Services/PrayerTimeService.swift GrooTests/Features/Azan/PrayerTimeServiceTests.swift
git commit -m "feat: injected clock for PrayerTimeService + deterministic prayer-time tests"
```

---

### Task 5: Edge sweep A — unicode/size/epoch across vault models, shared models, TOTP, password health

**Files:**
- Modify: `GrooTests/Fixtures/VaultItemFixtures.swift` (unicode fixture twins)
- Modify: `GrooTests/Features/Pass/PassModelsTests.swift` (append three tests)
- Modify: `GrooTests/Shared/SharedPassModelsTests.swift` (append one test)
- Modify: `GrooTests/Features/Pass/TotpServiceTests.swift` (append one test)
- Modify: `GrooTests/Features/Pass/PasswordHealthAnalyzerTests.swift` (append two tests)

**Interfaces:**
- Consumes: `PassVaultItem` Codable + `Equatable` (roundtrip equality covers every field), `PassNoteItem.content`, `SharedPassPasswordItem` (`password`/`username`/`primaryDomain`/`domains`), `VaultItemFixtures.samplePasswordItem(id:password:updatedAt:)`, `PasswordHealthAnalyzer.calculateStrength(_:)`/`analyze(items:now:)`, RFC 4226 Appendix D (`HOTP(counter 0) = 755224` for the 20-byte SHA1 secret).
- Produces: unicode fixtures as a parallel schema contract (`unicodeItemJSONs` must stay 1:1 with `PassVaultItemType.allCases`, enforced by a count check).

- [ ] **Step 1: Unicode fixture twins in `VaultItemFixtures.swift`**

Append inside `enum VaultItemFixtures` (after `allItemJSONs`, before `samplePasswordItem`):

```swift

    // MARK: - Unicode/emoji twins (Phase 6 edge sweep)

    /// Every user-controlled string field carries multi-byte content — CJK,
    /// RTL Arabic, combining marks (the ́ below is a JSON escape for a
    /// combining acute), and multi-scalar ZWJ emoji. Structural fields
    /// (base64 keys, card numbers, hex addresses, mime types) stay valid:
    /// production never receives emoji there. Keep 1:1 with allItemJSONs.
    static let unicodePasswordItemJSON = """
    {"id":"pw-u","type":"password","name":"🔐 パスワード مثال","username":"ユーザー@例え.jp","password":"påsswörd🧨👨‍👩‍👧‍👦","urls":["https://例え.jp/ログイン"],"notes":"ملاحظة 📝 caf\\u00e9 vs cafe\\u0301","totp":{"secret":"JBSWY3DPEHPK3PXP","algorithm":"SHA1","digits":6,"period":30},"folderId":"📁-1","favorite":true,"createdAt":1700000000000,"updatedAt":1700000000000}
    """

    static let unicodePasskeyItemJSON = """
    {"id":"pk-u","type":"passkey","name":"🗝️ 通行キー","rpId":"example.com","rpName":"مثال — Beispiel","credentialId":"Y3JlZC1pZA","publicKey":"cHVi","privateKey":"cHJpdg==","userHandle":"dXNlcg","userName":"ユーザー🙂","signCount":0,"createdAt":1700000000000,"updatedAt":1700000000000}
    """

    static let unicodeNoteItemJSON = """
    {"id":"n-u","type":"note","name":"📝 ملاحظات سرية","content":"秘密 🤫 mixed مع النص Ω≈ç√ — e\\u0301 combining","createdAt":1700000000000,"updatedAt":1700000000000}
    """

    static let unicodeCardItemJSON = """
    {"id":"c-u","type":"card","name":"💳 бизнес карта","cardholderName":"JOSÉ GARCÍA-ÑOÑO","number":"4111111111111111","expMonth":"12","expYear":"2030","cvv":"123","brand":"visa","createdAt":1700000000000,"updatedAt":1700000000000}
    """

    static let unicodeBankAccountItemJSON = """
    {"id":"b-u","type":"bank_account","name":"🏦 حساب جاري","bankName":"بنك الإمارات دبي الوطني","accountType":"checking","accountNumber":"12345678","routingNumber":"021000021","createdAt":1700000000000,"updatedAt":1700000000000}
    """

    static let unicodeFileItemJSON = """
    {"id":"fl-u","type":"file","name":"📄 書類","fileName":"税務書類 2025 📎.pdf","fileSize":1024,"mimeType":"application/pdf","r2Key":"files/例え","encryptionIv":"aXY=","createdAt":1700000000000,"updatedAt":1700000000000}
    """

    static let unicodeCryptoWalletItemJSON = """
    {"id":"w-u","type":"crypto_wallet","name":"🪙 المحفظة الرئيسية","address":"0xabc","seedPhrase":"legal winner thank year wave sausage worth useful legal winner thank yellow","derivationPath":"m/44'/60'/0'/0/0","createdAt":1700000000000,"updatedAt":1700000000000}
    """

    static var unicodeItemJSONs: [String] {
        [unicodePasswordItemJSON, unicodePasskeyItemJSON, unicodeNoteItemJSON, unicodeCardItemJSON,
         unicodeBankAccountItemJSON, unicodeFileItemJSON, unicodeCryptoWalletItemJSON]
    }
```

- [ ] **Step 2: Append to `PassModelsTests.swift`** (after `minimalPasswordItemDecodes`, before the closing brace):

```swift

    // MARK: Unicode / size sweep (Phase 6)

    @Test(arguments: VaultItemFixtures.unicodeItemJSONs)
    func unicodeItemRoundtripsLosslessly(_ json: String) throws {
        let item = try decoder.decode(PassVaultItem.self, from: Data(json.utf8))
        if case .corrupted = item { Issue.record("unicode fixture decoded as corrupted: \(json)") }
        let redecoded = try decoder.decode(PassVaultItem.self, from: try encoder.encode(item))
        #expect(redecoded == item)
    }

    @Test func unicodeFieldsSurviveWithExactScalars() throws {
        // Fixture parity: the unicode twins must track the type list
        #expect(VaultItemFixtures.unicodeItemJSONs.count == PassVaultItemType.allCases.count)

        let item = try decoder.decode(PassVaultItem.self, from: Data(VaultItemFixtures.unicodePasswordItemJSON.utf8))
        guard case .password(let pwd) = item else { Issue.record("expected .password, got \(item)"); return }
        #expect(pwd.name == "🔐 パスワード مثال")
        #expect(pwd.password == "påsswörd🧨👨‍👩‍👧‍👦")   // ZWJ family survives as one grapheme run
        #expect(pwd.username == "ユーザー@例え.jp")
        #expect(pwd.urls == ["https://例え.jp/ログイン"])
        #expect(pwd.folderId == "📁-1")
    }

    /// Max-size sweep: a pathological but user-reachable note (a pasted
    /// document). ~100KB of multi-byte content must roundtrip untruncated.
    @Test func largeMultibyteNoteContentRoundtrips() throws {
        let bigContent = String(repeating: "секрет🗒️", count: 12_000)   // 7 Characters × 12k
        let json = #"{"id":"n-big","type":"note","name":"big","content":"\#(bigContent)","createdAt":1,"updatedAt":1}"#
        let item = try decoder.decode(PassVaultItem.self, from: Data(json.utf8))
        guard case .note(let note) = item else { Issue.record("expected .note, got \(item)"); return }
        #expect(note.content == bigContent)
        let redecoded = try decoder.decode(PassVaultItem.self, from: try encoder.encode(item))
        #expect(redecoded == item)
    }
```

- [ ] **Step 3: Append to `SharedPassModelsTests.swift`** (after `primaryDomainIsNilForEmptyUrls`, before the closing brace):

```swift

    // MARK: Unicode sweep (Phase 6)

    /// AutoFill fills what the app stored: multi-byte credentials must cross
    /// the extension-side decode with exact scalar fidelity, and unicode
    /// URLs must never crash domain extraction (the exact host rendering —
    /// punycode or bail — is Foundation's business, so it is not pinned).
    @Test func unicodeCredentialSurvivesSharedDecode() throws {
        let item = try decoder.decode(SharedPassPasswordItem.self,
                                      from: Data(VaultItemFixtures.unicodePasswordItemJSON.utf8))
        #expect(item.password == "påsswörd🧨👨‍👩‍👧‍👦")
        #expect(item.username == "ユーザー@例え.jp")
        #expect(item.name == "🔐 パスワード مثال")
        _ = item.primaryDomain   // crash-freedom pin on the unicode URL
        _ = item.domains
    }
```

- [ ] **Step 4: Append to `TotpServiceTests.swift`** (inside `TotpServiceTests`, after `base32DecodingIsCaseAndPaddingTolerant`):

```swift

    // MARK: Epoch boundary (Phase 6)

    /// t = 0 → counter 0 → HMAC over eight 0x00 bytes. RFC 4226 Appendix D:
    /// HOTP(0) for the 20-byte SHA1 test secret is 755224. A
    /// counter-encoding bug (skipping leading zero bytes, wrong endianness
    /// at zero) breaks exactly here and nowhere in the RFC 6238 vectors.
    @Test func epochCounterZeroMatchesRfc4226AndRotatesAt30() {
        let config = PassTotpConfig(secret: Self.sha1Secret, algorithm: .sha1, digits: 6, period: 30)
        let atEpoch = TotpService.generateCode(config: config, time: Date(timeIntervalSince1970: 0))
        #expect(atEpoch == "755224")
        #expect(TotpService.generateCode(config: config, time: Date(timeIntervalSince1970: 29)) == "755224")
        #expect(TotpService.generateCode(config: config, time: Date(timeIntervalSince1970: 30)) != "755224")
    }
```

- [ ] **Step 5: Append to `PasswordHealthAnalyzerTests.swift`** (after the last existing test, before the closing brace — the suite constructs items via `VaultItemFixtures.samplePasswordItem`; match its `.password(...)` wrapping style):

```swift

    // MARK: Unicode / boundary sweep (Phase 6)

    /// Swift Strings count Characters, not bytes: 8 family-ZWJ emoji are
    /// ~200 UTF-8 bytes but 8 Characters — byte-based length scoring would
    /// wrongly rate this a 16+-length password.
    @Test func strengthCountsGraphemesNotBytes() {
        let familyEmoji = String(repeating: "👨‍👩‍👧‍👦", count: 8)
        #expect(familyEmoji.count == 8)
        #expect(PasswordHealthAnalyzer.calculateStrength(familyEmoji) == .weak)

        // 16 varied unicode Characters (case + digit + symbol variety,
        // no sequential/repeat runs) still rate strong
        let unicodeStrong = "Påsswörd-Ω997🧨ab"
        #expect(unicodeStrong.count == 16)
        #expect(PasswordHealthAnalyzer.calculateStrength(unicodeStrong) == .strong)
    }

    /// Swift String equality is canonical: "é" precomposed equals
    /// "e" + combining acute. Two items whose passwords differ only in
    /// normalization ARE the same secret — the analyzer must group them as
    /// reused (dictionary keys hash canonically, so this pins that the
    /// grouping key stays a String and never becomes raw bytes).
    @Test func canonicallyEquivalentPasswordsCountAsReused() {
        let precomposed = VaultItemFixtures.samplePasswordItem(id: "a", password: "caf\u{00E9}-secret-991")
        let decomposed = VaultItemFixtures.samplePasswordItem(id: "b", password: "cafe\u{0301}-secret-991")

        let report = PasswordHealthAnalyzer.analyze(
            items: [.password(precomposed), .password(decomposed)],
            now: Date(timeIntervalSince1970: 1_700_000_000)
        )

        #expect(report.reusedCount == 2)
    }
```

- [ ] **Step 6: Verify**

Run: `bash scripts/test.sh --unit 2>&1 | tail -5`
Expected: PASS — **304 tests** (297 + 7). These pin existing behavior: a failure means production mishandles unicode/size/epoch input — STOP and report (that would be a real Phase 6 catch, not a fixture problem).

- [ ] **Step 7: Commit**

```bash
git add GrooTests
git commit -m "test: unicode/size/epoch edge sweep — vault models, shared models, TOTP counter zero, password health"
```

---

### Task 6: Edge sweep B — currency/locale math, date-boundary walks, actor concurrency races

**Files:**
- Modify: `GrooTests/Features/Stocks/StockModelsTests.swift` (append `CurrencyFormatter` tests)
- Create: `GrooTests/Features/Stocks/StockPortfolioCurrencyTests.swift`
- Modify: `GrooTests/Features/Azan/PrayerTrackingServiceTests.swift` (append date-boundary tests)
- Modify: `GrooTests/Core/Storage/PassVaultStoreTests.swift` (append concurrency races)
- Modify: `GrooTests/Core/Network/APICacheTests.swift` (append one race)

**Interfaces:**
- Consumes: `CurrencyFormatter.format(_:currencyCode:showSign:)` (`StockModels.swift:216-231` — pins its own `en_IN` locale for INR only; everything else follows the machine locale, hence digit-projection assertions), `StockPortfolioManager` (`addHolding`/`addTransaction`/`loadCachedHoldings`/`refreshExchangeRates`/`exchangeRate(for:)`/`totalValue`/`totalCostBasis`/`staleReason`; `displayCurrency` reads UserDefaults.standard), `LocalStockHolding` (settable `currency`/`cachedPrice`, default currency `"USD"`), `YahooFinanceServiceTests.chartJSON` (same `NetworkStubbedSuites` namespace), `PrayerTrackingService(store:now:)` + existing `formatter`, `PassVaultStore` actor (paired `vault.enc` + `vault.meta.json` writes), `APICache` (`clearAll()` evicts the cache dict but never touches in-flight tasks — verified in source).
- Produces: nothing new in production.

- [ ] **Step 1: Append `CurrencyFormatter` tests to `StockModelsTests.swift`** (after the last existing test, before the closing brace):

```swift

    // MARK: - CurrencyFormatter (Phase 6 locale sweep)

    /// Digits-only projection: grouping separators and symbol placement vary
    /// with the machine locale; the digit sequence must not.
    private func digits(_ s: String) -> String { s.filter(\.isNumber) }

    /// INR pins its own en_IN locale inside the formatter, so the Indian
    /// lakh grouping is asserted exactly — on any machine.
    @Test func inrUsesIndianGroupingRegardlessOfMachineLocale() {
        let formatted = CurrencyFormatter.format(1_234_567.89, currencyCode: "INR")
        #expect(formatted.contains("12,34,567.89"), "expected lakh grouping, got \(formatted)")
    }

    @Test func zeroDecimalCurrenciesRoundToWholeUnits() {
        #expect(digits(CurrencyFormatter.format(1234.56, currencyCode: "JPY")) == "1235")
        #expect(digits(CurrencyFormatter.format(999.6, currencyCode: "KRW")) == "1000")
    }

    @Test func subUnitValuesKeepFourFractionDigitsAndUnitValuesTwo() {
        #expect(digits(CurrencyFormatter.format(0.1234, currencyCode: "USD")) == "01234")
        #expect(digits(CurrencyFormatter.format(1.2345, currencyCode: "USD")) == "123")   // 1.23
    }

    @Test func showSignPrefixesOnlyNonNegatives() {
        #expect(CurrencyFormatter.format(5, currencyCode: "USD", showSign: true).hasPrefix("+"))
        #expect(CurrencyFormatter.format(0, currencyCode: "USD", showSign: true).hasPrefix("+"))
        #expect(!CurrencyFormatter.format(-5, currencyCode: "USD", showSign: true).hasPrefix("+"))
    }
```

- [ ] **Step 2: Create `GrooTests/Features/Stocks/StockPortfolioCurrencyTests.swift`**

```swift
//
//  StockPortfolioCurrencyTests.swift
//  GrooTests
//
//  Multi-currency portfolio totals: conversion through fetched Yahoo rates,
//  and holdings with unavailable rates EXCLUDED from totals (never a silent
//  1:1) with the gap surfaced via staleReason. Rates are dyadic (2^-7) so
//  converted sums compare with ==. displayCurrency is
//  UserDefaults.standard-backed (P4 gap note) — pinned to USD and restored
//  around each test; the suite is serialized so nothing else observes the
//  temporary value.
//

import Foundation
import Testing
@testable import Groo

extension NetworkStubbedSuites {
@MainActor
@Suite(.serialized)
struct StockPortfolioCurrencyTests {

    static func withDisplayCurrencyUSD(_ body: () async throws -> Void) async rethrows {
        let key = "displayCurrency"
        let previous = UserDefaults.standard.string(forKey: key)
        defer {
            if let previous {
                UserDefaults.standard.set(previous, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        UserDefaults.standard.set("USD", forKey: key)
        try await body()
    }

    /// One USD holding (AAPL: 10 sh @ $150, cost $1000) and one JPY holding
    /// (7203.T: 5 sh @ ¥20,000, cost ¥50,000) — both transacted, so both
    /// count toward totals.
    static func makeEnv() throws -> (manager: StockPortfolioManager, service: YahooFinanceService) {
        let store = try InMemoryLocalStore.make()
        let manager = StockPortfolioManager(store: store)

        manager.addHolding(symbol: "AAPL", companyName: "Apple", exchange: "NMS")
        manager.addTransaction(to: "AAPL", type: .buy, shares: 10, totalCost: 1000,
                               date: Date(timeIntervalSince1970: 1_700_000_000))
        manager.addHolding(symbol: "7203.T", companyName: "Toyota", exchange: "JPX")
        manager.addTransaction(to: "7203.T", type: .buy, shares: 5, totalCost: 50_000,
                               date: Date(timeIntervalSince1970: 1_700_000_000))

        let aapl = try #require(store.getStockHolding(symbol: "AAPL"))
        aapl.cachedPrice = 150
        let toyota = try #require(store.getStockHolding(symbol: "7203.T"))
        toyota.currency = "JPY"
        toyota.cachedPrice = 20_000
        store.saveStockChanges()
        manager.loadCachedHoldings()

        let service = YahooFinanceService(cache: APICache(sessionConfiguration: StubURLProtocol.stubbedConfiguration()))
        return (manager, service)
    }

    @Test func totalsConvertThroughFetchedDyadicRates() async throws {
        StubURLProtocol.reset()
        try await Self.withDisplayCurrencyUSD {
            let (manager, service) = try Self.makeEnv()
            // JPY→USD at a dyadic 2^-7 = 0.0078125 → exact double sums
            StubURLProtocol.enqueue(method: "GET", pathSuffix: "/chart/JPYUSD=X",
                                    json: YahooFinanceServiceTests.chartJSON(price: "0.0078125", previousClose: "0.0078125"))

            await manager.refreshExchangeRates(using: service)

            #expect(manager.exchangeRate(for: "JPY") == 0.0078125)
            #expect(manager.exchangeRate(for: "USD") == 1.0)      // same-currency short-circuit
            #expect(manager.totalValue == 1500 + 100_000 * 0.0078125)     // 2281.25
            #expect(manager.totalCostBasis == 1000 + 50_000 * 0.0078125)  // 1390.625
            #expect(manager.staleReason == nil)
        }
    }

    @Test func missingRateExcludesHoldingAndSurfacesStaleReason() async throws {
        StubURLProtocol.reset()
        try await Self.withDisplayCurrencyUSD {
            let (manager, service) = try Self.makeEnv()
            // Rate fetch fails hard (500 → no retry, no sleeps)
            StubURLProtocol.enqueue(method: "GET", pathSuffix: "/chart/JPYUSD=X", status: 500, json: "{}")

            await manager.refreshExchangeRates(using: service)

            #expect(manager.exchangeRate(for: "JPY") == nil)
            // The JPY holding is EXCLUDED — a silent 1:1 conversion here
            // would inflate the portfolio by ~¥100,000-as-dollars
            #expect(manager.totalValue == 1500)
            #expect(manager.totalCostBasis == 1000)
            let reason = try #require(manager.staleReason)
            #expect(reason.contains("JPY"))
        }
    }
}
}
```

- [ ] **Step 3: Append date-boundary tests to `PrayerTrackingServiceTests.swift`** (after the last existing test, before the closing brace):

```swift

    // MARK: - Date-boundary sweep (Phase 6)

    static func makeService(now fixedNow: Date) throws -> PrayerTrackingService {
        let store = try InMemoryLocalStore.make()
        return PrayerTrackingService(store: store, now: { fixedNow })
    }

    static func dateString(daysAgo: Int, from now: Date) -> String {
        let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: now)!
        return formatter.string(from: date)
    }

    static func logFullDay(_ service: PrayerTrackingService, daysAgo: Int, from now: Date) {
        for prayer in Prayer.notifiable {
            service.logPrayer(dateString: Self.dateString(daysAgo: daysAgo, from: now),
                              prayer: prayer, status: .onTime)
        }
    }

    /// The streak walk crosses Dec 31 → Jan 1 via Calendar day arithmetic +
    /// string round-trips; an off-by-one at the year boundary breaks here.
    @Test func streakWalksAcrossTheYearBoundary() throws {
        let newYear = Date(timeIntervalSince1970: 1_767_268_800)   // 2026-01-01T12:00:00Z
        let service = try Self.makeService(now: newYear)

        for daysAgo in 0...2 { Self.logFullDay(service, daysAgo: daysAgo, from: newYear) }

        // In every timezone within ±14h these three days straddle the year
        // boundary (local "today" is Jan 1 or Jan 2)
        #expect(service.currentStreak == 3)
        #expect(service.bestStreak == 3)
    }

    @Test func weeklyGridIsSevenUniqueConsecutiveDaysAcrossLeapDay() throws {
        let afterLeap = Date(timeIntervalSince1970: 1_835_611_200)   // 2028-03-02T12:00:00Z
        let service = try Self.makeService(now: afterLeap)
        service.recalculate()

        let dates = service.weeklyGrid.map(\.dateString)
        #expect(dates.count == 7)
        #expect(Set(dates).count == 7, "grid duplicated a day: \(dates)")
        // Oldest-first, derived through the same calendar walk the service uses
        let expected = (0..<7).reversed().map { Self.dateString(daysAgo: $0, from: afterLeap) }
        #expect(dates == expected)
        // The 7-day window straddles the leap day for local "today" of
        // either Mar 2 or Mar 3 (every timezone within ±14h of UTC)
        #expect(dates.contains("2028-02-29"), "leap day missing from \(dates)")
    }

    /// US DST 2026 springs forward on Mar 8: local-midnight day arithmetic
    /// must neither skip nor duplicate a date string across the jump.
    @Test func streakSurvivesTheSpringForwardWeek() throws {
        let afterDst = Date(timeIntervalSince1970: 1_773_144_000)   // 2026-03-10T12:00:00Z
        let service = try Self.makeService(now: afterDst)

        for daysAgo in 0...4 { Self.logFullDay(service, daysAgo: daysAgo, from: afterDst) }

        let walked = (0...4).map { Self.dateString(daysAgo: $0, from: afterDst) }
        #expect(Set(walked).count == 5, "day walk skipped/duplicated a date: \(walked)")
        #expect(service.currentStreak == 5)
    }
```

(The `makeService(now:)`, `dateString(daysAgo:from:)`, and `logFullDay(_:daysAgo:from:)` statics are overloads of the existing helpers — different signatures, no collisions.)

- [ ] **Step 4: Append concurrency races to `PassVaultStoreTests.swift`** (inside `PassVaultStoreTests`, after `corruptMetadataThrowsInsteadOfGarbage`):

```swift

    // MARK: - Concurrency sweep (Phase 6)

    /// saveVault writes the data blob then the metadata with no suspension
    /// point between them — actor isolation makes the pair atomic. 32 racing
    /// writers with interleaved readers must never observe a torn pair
    /// (blob from writer A, metadata from writer B). This is the invariant
    /// that breaks if PassVaultStore ever stops being an actor or saveVault
    /// gains an await between the two writes.
    @Test func concurrentSaveAndLoadNeverTearDataMetadataPairs() async throws {
        let (store, dir) = Self.makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        try await withThrowingTaskGroup(of: Void.self) { group in
            for i in 0..<32 {
                group.addTask {
                    try await store.saveVault(
                        encryptedData: Data("payload-\(i)".utf8),
                        metadata: PassVaultMetadata(version: i, iv: "iv", updatedAt: i, lastSyncedAt: i)
                    )
                }
                group.addTask {
                    // Reads race the writes; nil (nothing written yet) is
                    // fine — a mismatched pair is the failure being hunted
                    if let loaded = try await store.loadVault() {
                        #expect(loaded.data == Data("payload-\(loaded.metadata.version)".utf8),
                                "torn pair: \(String(decoding: loaded.data, as: UTF8.self)) with metadata v\(loaded.metadata.version)")
                    }
                }
            }
            try await group.waitForAll()
        }

        // Terminal state is some writer's complete pair
        let final = try #require(await store.loadVault())
        #expect(final.data == Data("payload-\(final.metadata.version)".utf8))
    }

    @Test func concurrentClearAndSaveLeaveAConsistentTerminalState() async throws {
        let (store, dir) = Self.makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        try await withThrowingTaskGroup(of: Void.self) { group in
            for i in 0..<16 {
                group.addTask {
                    try await store.saveVault(
                        encryptedData: Data("payload-\(i)".utf8),
                        metadata: PassVaultMetadata(version: i, iv: "iv", updatedAt: i, lastSyncedAt: i)
                    )
                }
                if i.isMultiple(of: 4) {
                    group.addTask { try await store.clear() }
                }
            }
            try await group.waitForAll()
        }

        // Whichever interleaving won, the store must agree with itself:
        // fully present (a matched pair) or fully absent — never vaultExists
        // without loadable metadata (that state breaks unlock at launch)
        let exists = await store.vaultExists()
        let loaded = try await store.loadVault()
        #expect((loaded != nil) == exists)
        if let loaded {
            #expect(loaded.data == Data("payload-\(loaded.metadata.version)".utf8))
        }
    }
```

- [ ] **Step 5: Append the eviction race to `APICacheTests.swift`** (after `clearMatchingEvictsSelectively`, before the closing braces):

```swift

    // MARK: - Concurrency sweep (Phase 6)

    /// clearAll evicts the cache dictionary but must never touch in-flight
    /// tasks: 16 fetches racing periodic clearAlls must all resolve to the
    /// stubbed body (cache hit, in-flight join, or post-eviction refetch —
    /// all legal), with no deadlock and no torn data.
    @Test func clearAllRacingConcurrentFetchesStaysConsistent() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.enqueue(method: "GET", pathSuffix: "/prices/eth", json: #"{"v":1}"#)
        // last-response-repeats: post-eviction refetches see the same body
        let cache = Self.makeCache()

        try await withThrowingTaskGroup(of: Data?.self) { group in
            for i in 0..<16 {
                group.addTask { try await cache.fetch(Self.url, ttl: 300) }
                if i.isMultiple(of: 4) {
                    group.addTask {
                        await cache.clearAll()
                        return nil
                    }
                }
            }
            for try await result in group {
                if let result {
                    #expect(result == Data(#"{"v":1}"#.utf8))
                }
            }
        }
    }
```

- [ ] **Step 6: Verify**

Run: `bash scripts/test.sh --unit 2>&1 | tail -5`
Expected: PASS — **316 tests, 39 suites** (304 + 12). Run it **twice** — the concurrency tests must be green on both runs before committing (a single intermittent failure is a real finding, not a re-run candidate: STOP and report which invariant broke).

- [ ] **Step 7: Commit**

```bash
git add GrooTests
git commit -m "test: currency/locale math, prayer-tracking date boundaries, actor concurrency races (edge sweep B)"
```

---

### Task 7: Final verification + coverage snapshot + README + FINAL PROJECT SUMMARY

**Files:**
- Modify: `README.md` (Testing conventions: two lines)

- [ ] **Step 1: Full suites twice (definition of done)**

Run: `bash scripts/test.sh --unit 2>&1 | tail -3 && bash scripts/test.sh --unit 2>&1 | tail -3`
Expected: `** TEST SUCCEEDED **` twice — **316 unit tests** both runs (the two-consecutive-greens gate matters most this phase: the concurrency races are the likeliest flake source and must not be).

Run: `bash scripts/test.sh --ui 2>&1 | tail -3 && bash scripts/test.sh --ui 2>&1 | tail -3`
Expected: `** TEST SUCCEEDED **` twice — **7 UI tests** both runs.

- [ ] **Step 2: All targets build, both configurations**

Run: `xcodebuild build -project Groo.xcodeproj -scheme Groo -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`

Run: `xcodebuild build -project Groo.xcodeproj -scheme Groo -configuration Release -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **` (Release carries no `--uitest` surface — Task 2's guarantee, re-verified at the end).

- [ ] **Step 3: Manual smoke of touched features**

In the simulator (normal launch, no `--uitest`): create a wallet and cancel the sheet mid-"Creating wallet..." — the onboarding view must remain usable and no phantom wallet may appear in the Pass vault; then create one to completion — recovery phrase shows, confirm advances to the portfolio. Open the password generator — toggles still flip and regenerate. Open the Azan tab — prayer times render as before (clock seam default path).

- [ ] **Step 4: Coverage snapshot**

Run: `bash scripts/test.sh --unit --coverage 2>&1 | tail -60`
Record in the final report: `WalletManager.swift` (should rise above the 87.88% P2 mark — cancellation branches now covered), `YahooFinanceService.swift` (expected well above the 53% P4 shortfall — `withRetry` is now fully exercised), `PrayerTimeService.swift` (new — expect >70%; the timer/tick and `jumuahReminderTime`/`suhoorReminderTime` paths are the uncovered remainder), `StockPortfolioManager.swift` (should rise above 53% — exchange-rate/totals paths now covered), `PasswordHealthAnalyzer.swift`, `PassVaultStore.swift`, `APICache.swift` (all expected >95%).

- [ ] **Step 5: README lines**

In `README.md`'s Testing conventions list (after the Phase 5 UI-test lines), append:

```markdown
- Edge-case fixtures: unicode/emoji twins of every vault item type live beside the canonical ones in `GrooTests/Fixtures/VaultItemFixtures.swift` (keep both lists 1:1 with `PassVaultItemType`). Concurrency is tested as TaskGroup races asserting invariants (torn pairs, wrong bodies) — never orderings or timings.
- `UITestMode.isActive` is compile-time `false` in Release: the `--uitest` seam exists only in Debug binaries.
```

- [ ] **Step 6: Commit**

```bash
git add README.md
git commit -m "docs: README Phase 6 conventions (unicode fixtures, concurrency invariants, Release uitest fence)"
```

- [ ] **Step 7: Final report — including the FINAL PROJECT SUMMARY**

The report to the user has two parts.

**Phase 6 report:**
- Final totals: **316 unit tests (39 suites) + 7 UI tests**, both green twice; Debug and Release builds green.
- Production changes shipped this phase (all five files, one paragraph each): the createWallet cancellation fix, the Release fence on `UITestMode.isActive`, generator toggle identifiers, the Yahoo sleep seam (+ terminal-sleep removal), the PrayerTimeService clock seam.
- Coverage numbers from Step 4.
- Product quirks observed during planning/execution (not fixed — need product decisions):
  1. **Ramadan label first-pass lag** — `recalculate()` builds prayer rows before `updateRamadanInfo()`, so Suhoor/Iftar labels miss the first calculation after `configure` (one-line reorder candidate).
  2. **`WalletOnboardingView.createWallet` runs scrypt-heavy derivation on the MainActor** — the UI freezes during "Creating wallet..." (why the P5 UI test needed a 60s wait); a detached-derivation refactor is the fix, out of scope here.
  3. **Cancel-during-PUT residual** (by design of the minimal fix): if the sheet is dismissed in the narrow window where the vault write completes anyway, the wallet exists but the phrase was never shown — it remains viewable in the Pass vault item, and CryptoView correctly advances.

**FINAL PROJECT SUMMARY (whole test-suite retrospective — this closes the spec):**
- **Scale:** 0 → **316 unit tests in 39 suites + 7 UI tests** across 6 phases (P1 vault/crypto: 0→~110; P2 wallet: →~130; P3 sync/offline: →191; P4 extensions/features: →280; P5 UI + fast-follows: →284 + 7 UI; P6 edge sweep + fast-follows: →316). All local (`scripts/test.sh`), no CI by design.
- **Seams built (all default-parameter, zero production behavior change):** injected `URLSession`/`URLSessionConfiguration` (APIClient, PassAPIClient, APICache → every network service), `KeychainServicing` + in-memory fakes, injected clocks (`now:` on APICache, PrayerTrackingService, PrayerTimeService; TOTP takes explicit `time:`), injected sleeps (CoinGecko, Yahoo), in-memory SwiftData (`InMemoryLocalStore`), `PassVaultStore(directoryURL:)`, scriptable `FakeWebSocketConnection`, and the Debug-only `--uitest` bootstrap (`UITestMode`).
- **Real production bugs found and fixed by the retrofit:** GrooAutoFill debug bundle-id (P1); StubURLProtocol-exposed empty-pathSuffix crash (P2, latent P1 bug); CoinGecko `withRetry` terminal 4s hang (P2); WebSocket URLSession delegate-retain leak on cancel (P4); recovery-phrase sheet torn down before the mnemonic rendered (P5, badc2e4); stuck `pendingRecoveryPhraseReveal` on cancel-mid-creation (P6, this plan); Yahoo terminal-sleep hang (P6). Plus the Release `--uitest` surface removed (P6).
- **Product gaps logged for decisions (not test work):** no sync backoff/coalescing + unknown-op-type→create fallback (P3); ShareExtension queue is write-only — consume or remove (P4); no relock on backgrounding — spec/product mismatch, **USER DECISION still pending** (P5); WebSocket drop/401 paths still churn sessions (P4); AzanWidget duplicates deadline logic (P4); PassView folder filter is a TODO and "PAT token" sign-out copy is stale (P5); MainActor scrypt derivation and Ramadan label lag (P6).
- **Deliberately untested and why (stable list):** biometric/`LAContext` system UI, OAuth browser flow, out-of-process pasteboard reads, adhan-swift/web3swift internals, `PrayerTimeService` timer ticks, extension-target-only glue (`ExtensionConfig`), true DST-timezone matrices (formatter timezone is process-global).
- **Suggested next steps if the suite ever grows:** CI once flakiness data exists (spec deferred it), wallet-import + stocks UI flows behind the established seams, a Yahoo `Config` URL override before any stocks UI test, and the SPM extraction the tests were written to survive.

---

## Post-plan

This is the final phase of `docs/superpowers/specs/2026-07-05-ios-test-suite-design.md` — the spec's coverage plan (Phases 1–6) is complete after this plan executes. Remaining items are product decisions listed in the FINAL PROJECT SUMMARY, not test work. If a Phase 7 ever exists, it should start from the "suggested next steps" list above.
