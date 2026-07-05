# iOS Test Suite Design

**Date:** 2026-07-05
**Status:** Approved
**Goal:** Retrofit comprehensive automated testing (unit + integration + UI) onto the Groo iOS app to protect reliability and stability. The app currently has zero tests.

## Context

- ~29k lines of Swift across 6 targets: Groo (main app), Shared, ShareExtension, GrooAutoFill, WidgetExtension, KeyboardExtension.
- Services are actor-based with few singletons (`APICache.shared`, `LocalStore.shared`, `RecitationAudioService.shared`); SwiftData is used for local storage. Both make retrofit testing tractable.
- Build/run environment: Xcode project at `ios/Groo.xcodeproj`, scheme `Groo`, simulator `iPhone 17 Pro` (iOS 26.2).
- No CI exists and none is planned for now — tests run locally.

## Decisions

| Decision | Choice |
|---|---|
| Scope | Unit + integration + UI tests ("everything") |
| Priority order | Vault/crypto → wallet → sync/offline → extensions & remaining features → UI flows → edge-case sweep |
| Refactoring tolerance | Refactor where needed for testability (DI seams; zero behavior change) |
| CI | Local only; `scripts/test.sh` wrapper |
| Frameworks | Swift Testing (`@Test`/`#expect`) for unit + integration; XCUITest for UI |
| Structure | Test targets inside `Groo.xcodeproj` (Approach A). No SPM extraction — tests port unchanged if core logic is ever extracted into a package later. |

## Architecture

### Test targets

- **GrooTests** — unit + integration tests, Swift Testing framework, host application = Groo. Reaches app code and all `Shared/` files directly (Shared files are compiled into the app target).
- **GrooUITests** — XCUITest runner target for end-to-end flows.

### Test doubles & seams

All seams are default-parameter injections — production call sites are unchanged.

| Dependency | Seam | Test double |
|---|---|---|
| Network | Services (`APIClient`, `EthereumService`, `CoinGeckoService`, …) accept an injected `URLSession` (default `.shared`) | `StubURLProtocol` returning canned responses/errors per request matcher |
| Keychain | `KeychainServicing` protocol extracted from `KeychainService`/`SharedKeychain` | In-memory fake (real keychain is unavailable/flaky in test hosts) |
| Time | TOTP and sync-retry logic accept `now: () -> Date` (default `Date.init`) | Fixed/advanceable clock |
| SwiftData | `LocalStore` gains an initializer accepting a `ModelContainer` (existing `shared` singleton unchanged) | `ModelConfiguration(isStoredInMemoryOnly: true)` |
| UserDefaults | Existing config-override pattern | Suite-named `UserDefaults` instance per test |
| WebSocket | Socket layer behind a small protocol | Scriptable fake socket |

### Conventions

- Test files mirror source paths: `GrooTests/Features/Pass/TotpServiceTests.swift` tests `Groo/Features/Pass/TotpService.swift`.
- One `@Suite` per service/type under test.
- Shared fixtures (RFC test vectors, sample vault items, canned API payloads) live in `GrooTests/Fixtures/`.
- No `sleep`/arbitrary waits anywhere: injected clocks and Swift Testing `confirmation`/async expectations only. This is the flakiness firewall.

### Running

```bash
scripts/test.sh            # unit + integration (GrooTests)
scripts/test.sh --ui       # UI tests (GrooUITests)
scripts/test.sh --all      # everything
```

Wrapper around: `xcodebuild test -project ios/Groo.xcodeproj -scheme Groo -destination 'platform=iOS Simulator,name=iPhone 17 Pro'` with `-only-testing` filters.

## Coverage plan (phased)

Each phase lands as: seams refactor (if needed) → tests → full suite green → manual smoke of touched feature.

### Phase 1 — Vault & crypto (highest stakes)

- **SharedCrypto / CryptoService**: encrypt→decrypt roundtrips; wrong-key and tampered-ciphertext rejection; key derivation against known test vectors; empty/large/unicode payloads.
- **SharedTotp / TotpService**: RFC 6238 test vectors (SHA1/SHA256, 6/8 digits); code rotation at period boundaries via injected clock; malformed `otpauth://` URI parsing.
- **SharedPasskeyCrypto**: sign/verify roundtrips; sign count stays 0 (AutoFill rule); credential ID encoding.
- **PassModels / SharedPassModels**: Codable roundtrips for every item type (guards the multi-file switch statements that must stay in sync); decoding items with missing/unknown fields.
- **PassVaultStore / SharedVaultStore + PassService** (integration): create→encrypt→persist→reload→decrypt for every item type; trash/restore; folder moves; wrong unlock password fails cleanly.
- **PasswordHealthAnalyzer**: weak/reused/old detection; empty vault.
- **Keychain contract tests**: protocol semantics (overwrite, delete-missing, access groups) against the in-memory fake.

### Phase 2 — Wallet

- **WalletManager**: BIP39 mnemonic generation/import vectors; address derivation; private-key import; persistence via fake keychain/PassService.
- **EthereumService** (stubbed RPC): balance parsing; transaction building (nonce/gas/chain ID); wei↔ETH decimal conversion edge cases; malformed RPC responses.
- **CoinGeckoService + APICache**: price parsing; cache hit/expiry/staleness; API-down fallback to cache.

### Phase 3 — Sync & offline

- **SyncState / PendingOperation**: queue ordering; retry/backoff via injected clock; conflict cases; operation coalescing.
- **SyncService** (integration, stubbed API): offline enqueue→reconnect→flush; partial failure; dedupe.
- **WebSocketService**: connect/drop/reconnect state machine via fake socket.
- **APIClient**: auth-header injection; 401→token-refresh path; decode failures surface as typed errors.

### Phase 4 — Extensions & remaining features

- **AutoFill** (`CredentialIdentityService` + GrooAutoFill logic): domain↔credential matching; pending-passkey queue semantics; identity-store payload building.
- **SharedPendingItemsStore, SharedConfig**: roundtrips; UserDefaults overrides.
- **Widget/Keyboard/Share**: pure logic (data formatting, snapshot building) — extracted into `Shared/` where currently inline in extension targets.
- **Azan, Stocks, Pad, Scratchpad**: calculation/model/persistence logic (e.g., `StockPortfolioManager` cost-basis math, prayer-time preferences, pad/scratchpad persistence).

### Phase 5 — UI tests (GrooUITests)

Critical-path flows only; logic regressions belong to Phases 1–4.

- **Unlock/lock**: fresh launch → unlock screen → wrong password rejected → correct password reaches home; global lock re-engages on backgrounding.
- **Pass CRUD**: create login item → visible in list → edit → detail reflects change → trash → restore.
- **Password generator**: generate, copy, options respected.
- **Wallet onboarding**: create-wallet path, stopping before real network dependency.
- **Tab navigation smoke**: every tab renders without crashing.

Infrastructure: a `--uitest` launch argument switches the app to in-memory storage + stubbed config so UI tests never touch real local data or real APIs. Accessibility identifiers added to key controls as needed.

### Phase 6 — Edge-case sweep

Deliberate pass per suite once baseline coverage exists: empty states; maximum sizes; unicode/emoji in every string field; concurrent actor access (Swift Testing's parallel execution stresses this by default); date boundaries (DST, epoch); locale/currency formatting in stocks/crypto math.

## Error-handling standards for tests

- Every stubbed-network suite includes the failure matrix: timeout, 4xx, 5xx, malformed JSON, empty body.
- Crypto suites assert failures fail loudly — wrong key must throw, never return garbage.
- Sync suites assert no silent drops: a failed operation is either retried or surfaced.

## Definition of done (per phase)

1. Suite green twice consecutively via `scripts/test.sh`.
2. All 6 targets still build.
3. Quick manual smoke of the touched feature in the simulator.

## Out of scope

- CI/GitHub Actions (revisit once the suite is stable).
- SPM package extraction (Approach B — deferred; tests are written to port unchanged).
- Performance/load testing; snapshot testing.
- Testing third-party libraries themselves (web3swift, adhan-swift) — we test our usage of them.
