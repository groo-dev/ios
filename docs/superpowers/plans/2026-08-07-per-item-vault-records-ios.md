# Per-item vault records — iOS implementation plan (Phases 4–6 of 7)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the Groo iOS app read and write per-item vault records, and let the AutoFill extension push a newly registered passkey to the server during the ceremony as a single record `POST`.

**Architecture:** `PassService` branches on `formatVersion` from key-info: the existing whole-vault path at `1`, delta sync at `2`. `PassAPIClient` and record crypto move to `Shared/` so `GrooAutoFill` can use them. The passkey push becomes one `POST /v1/vault/records` with a brand-new id — no base vault, no conflict path.

**Tech Stack:** Swift 6, SwiftUI, Swift Testing, CryptoKit, `GrooAuth`.

**Source spec:** `~/work/gr/pass/docs/superpowers/specs/2026-08-07-per-item-vault-records-design.md`
**Depends on:** Phase 1 (API) — complete and merged on branch `per-item-vault-records` in the `pass` repo.

**Supersedes** Phases 2 and 4 of `docs/superpowers/specs/2026-08-07-autofill-passkey-remote-sync-design.md`; **absorbs** its Phase 3 unchanged as Task 6 here. Its Phase 1 (app-side drain) is already implemented and untouched.

## Global Constraints

- **The record payload envelope is `{"kind":"item"|"folder","data":{…}}`**, where `data` is the item object byte-for-byte as the web app writes it. Decode `data` losslessly (`PassRawJSON`) wherever a typed model would drop fields.
- **Never round-trip a record through `SharedPassVaultItem`.** Its `case other` is valueless and its `CodingKeys` are a subset. This no longer risks whole-vault loss — no client rewrites a record it did not author — but it would still corrupt the one record being written.
- **`formatVersion` is read, never written.** iOS never converts. At `1`, behaviour is exactly as today.
- **`signCount` merges as `max()`** on a same-record conflict. A monotonic authenticator counter must never go backwards.
- **The AutoFill push must not advance the sync cursor.** Inserting the new record into the App Group cache is correct; moving the cursor past a seq we did not sync would skip every record written in between.
- **Every new `Shared/` file must be registered** with `scripts/register_shared_file.rb` for every consuming target, or it compiles into nothing.
- **Clean-build before any on-device verification** that touches an extension `Info.plist` or entitlements — the embedded `.appex` copy goes stale otherwise.
- Test baseline as of 2026-08-07 is **16 pre-existing failures** (view snapshots plus one date-dependent `PrayerTimeServiceTests` case). Diff against that, do not treat them as regressions.
- Build: `xcodebuild -project Groo.xcodeproj -scheme Groo -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build`. Tests: `scripts/test.sh --unit`.

---

### Task 1: Record models and envelope crypto in `Shared/`

**Files:**
- Create: `Shared/SharedRecordModels.swift`
- Create: `Shared/SharedRecordCrypto.swift`
- Test: `GrooTests/Shared/SharedRecordCryptoTests.swift`
- Register: both new files via `scripts/register_shared_file.rb`

**Interfaces:**
- Produces:
  - `struct SharedServerRecord: Codable` — `id, encryptedData: String?, iv: String?, wrappedRecordKey: String?, wrapIv: String?, version: Int, seq: Int, isDeleted: Bool, createdAt: Int, updatedAt: Int`
  - `struct SharedRecordsResponse: Codable` — `records: [SharedServerRecord], nextSeq: Int, hasMore: Bool, formatVersion: Int`
  - `struct SharedRecordWriteRequest: Codable` — `id, encryptedData, iv, wrappedRecordKey, wrapIv, expectedVersion: Int?`
  - `enum SharedRecordKind: String, Codable { case item, folder }`
  - `SharedRecordCrypto.encryptRecord(id:kind:payload:vaultKey:) throws -> SharedRecordWriteRequest`
  - `SharedRecordCrypto.decryptRecord(_:vaultKey:) throws -> (kind: SharedRecordKind, data: Data)` — returns the raw `data` JSON bytes, so callers decode losslessly.

- [ ] **Step 1: Write the failing test**

`GrooTests/Shared/SharedRecordCryptoTests.swift`:

```swift
import Testing
import Foundation
import CryptoKit
@testable import Groo

@Suite("SharedRecordCrypto")
struct SharedRecordCryptoTests {
    @Test("round-trips an item payload byte-for-byte")
    func roundTrip() throws {
        let vaultKey = SymmetricKey(size: .bits256)
        let payload = #"{"id":"a","type":"password","name":"A","futureField":{"nested":[1,2]}}"#
        let data = Data(payload.utf8)

        let enc = try SharedRecordCrypto.encryptRecord(
            id: "a", kind: .item, payload: data, vaultKey: vaultKey
        )
        let out = try SharedRecordCrypto.decryptRecord(enc, vaultKey: vaultKey)

        #expect(out.kind == .item)
        // Unknown fields must survive: the web app and iOS share this envelope.
        let round = try JSONSerialization.jsonObject(with: out.data) as? [String: Any]
        #expect((round?["futureField"] as? [String: Any])?["nested"] as? [Int] == [1, 2])
    }

    @Test("uses a distinct record key per record")
    func distinctKeys() throws {
        let vaultKey = SymmetricKey(size: .bits256)
        let a = try SharedRecordCrypto.encryptRecord(id: "a", kind: .item, payload: Data("{}".utf8), vaultKey: vaultKey)
        let b = try SharedRecordCrypto.encryptRecord(id: "b", kind: .item, payload: Data("{}".utf8), vaultKey: vaultKey)
        #expect(a.wrappedRecordKey != b.wrappedRecordKey)
    }

    @Test("fails under a different vault key")
    func wrongKey() throws {
        let enc = try SharedRecordCrypto.encryptRecord(
            id: "a", kind: .item, payload: Data("{}".utf8), vaultKey: SymmetricKey(size: .bits256)
        )
        #expect(throws: (any Error).self) {
            try SharedRecordCrypto.decryptRecord(enc, vaultKey: SymmetricKey(size: .bits256))
        }
    }
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `scripts/test.sh --unit 2>&1 | grep SharedRecordCrypto`
Expected: compile failure — the types do not exist.

- [ ] **Step 3: Implement the models and crypto**

`SharedRecordCrypto` mirrors the TypeScript exactly: generate a random 256-bit record key, AES-GCM the envelope `{"kind":…,"data":…}` under it, then wrap the raw key bytes under the vault key using the **same byte layout as `CryptoService.encryptData`** (IV ‖ ciphertext ‖ tag), base64 each field.

Build `data` by embedding the caller's JSON bytes verbatim rather than re-encoding a typed model — that is what keeps unknown fields alive.

- [ ] **Step 4: Register the files and build**

```bash
ruby scripts/register_shared_file.rb Shared/SharedRecordModels.swift
ruby scripts/register_shared_file.rb Shared/SharedRecordCrypto.swift
xcodebuild -project Groo.xcodeproj -scheme Groo -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

- [ ] **Step 5: Run the tests**

Run: `scripts/test.sh --unit 2>&1 | grep SharedRecordCrypto`
Expected: 3 passing.

- [ ] **Step 6: Cross-client interop check**

This is the check that matters most and the one a Swift-only test cannot make. Produce a record with the web implementation and open it with the Swift one:

```bash
cd ~/work/gr/pass/packages/crypto
node -e '
const { webcrypto } = require("crypto"); globalThis.crypto = webcrypto;
// encrypt a known payload under a known key, print base64 fields + key
' > /tmp/record-fixture.json
```

Commit the fixture to `GrooTests/Fixtures/web-record.json` and add a test that decrypts it with `SharedRecordCrypto` and asserts the payload. A byte-format drift between the two implementations is otherwise invisible until a real device cannot open a real vault.

- [ ] **Step 7: Commit**

```bash
git add Shared/SharedRecordModels.swift Shared/SharedRecordCrypto.swift GrooTests Groo.xcodeproj
git commit -m "feat(pass): record envelope crypto in Shared/"
```

---

### Task 2: Move `PassAPIClient` and `APIError` to `Shared/`, add record endpoints

**Files:**
- Move: `PassService.swift` (the ~120-line client) → `Shared/SharedPassAPIClient.swift`
- Move: `APIError` → `Shared/SharedAPIError.swift`
- Create: `Shared/SharedConfig.passAPIBaseURL` (mirrors `Config.passAPIBaseURL`, including the UserDefaults override)
- Modify: `ios/Groo/Features/Pass/Models/PassModels.swift`
- Register: all new `Shared/` files

**Interfaces:**
- Produces on the client: `getRecords(since:limit:)`, `createRecord(_:)`, `updateRecord(_:expectedVersion:)`, `deleteRecord(id:)`, `bulkUpsertRecords(_:)`, `getPrivateKey()`, `putPrivateKey(_:)`.
- `PassKeyInfo` gains `formatVersion: Int?` (optional — an older server omits it, and `nil` must mean `1`).
- `PassVaultSetupRequest` gains `encryptedPrivateKey` and `privateKeyIv`, both required by the API now.

**Why the move:** `PasskeyPublisher` must live in `Shared/` because `GrooTests` cannot compile extension-target sources. Moving the client also removes ~120 lines from `PassService.swift`, which is 1064 lines and holds both the service and its HTTP client.

- [ ] **Step 1: Move with no behaviour change**

Relocate the files, register them, build. `PassAPIClientTests` and `PassServiceIntegrationTests` are the regression guard and must pass **unchanged**.

- [ ] **Step 2: Add the record endpoints**

Each mirrors the API's contract; decode `409 RECORD_CONFLICT` into a typed error carrying the server's `current` record, so the caller can field-merge rather than re-parse JSON.

- [ ] **Step 3: Verify**

```bash
scripts/test.sh --unit 2>&1 | sed -n '/^Failing tests:/,/^\*\* TEST/p'
```
Expected: the 16-failure baseline, unchanged.

- [ ] **Step 4: Commit**

```bash
git commit -m "refactor(pass): move the API client to Shared/ and add record endpoints"
```

---

### Task 3: Delta sync in `PassService`

**Files:**
- Modify: `ios/Groo/Features/Pass/PassService.swift`
- Modify: `ios/Shared/SharedVaultStore.swift` (cache records + cursor)
- Test: `GrooTests/Features/Pass/PassRecordSyncTests.swift`

**Interfaces:**
- Produces: `PassService.formatVersion: Int`, private `syncRecords()`, `records: [String: DecodedRecord]`, `cursor: Int`.

- [ ] **Step 1: Write the failing tests**

Cover, using the existing `NetworkStubbedSuites(.serialized)` umbrella (`StubURLProtocol` carries shared static state):

| Test | Asserts |
|---|---|
| unlock at `formatVersion` 2 | syncs records; `GET /v1/vault` is never called |
| unlock at `formatVersion` 1 | uses the blob path exactly as today |
| pagination | loops on `hasMore`, not on a short page |
| tombstone | a record with `isDeleted` is removed locally |
| `CURSOR_TOO_OLD` | discards local state and resyncs from `0` |
| cursor never rewinds | a stale `nextSeq` does not lower it |
| unknown `kind` | the record is skipped, not fatal |

- [ ] **Step 2: Implement**

`unlock`/`unlockWithBiometric` read `keyInfo.formatVersion ?? 1`. At `2`, replace the whole-vault fetch with a paginated `getRecords(since:)` loop, decrypt each into `PassRawJSON`, and rebuild `vault` from the decoded items and folders.

Biometric unlock currently proves the stored key still works by decrypting the blob. **That returns `410` after the cutover and would be misread as a network failure, silently keeping a stale enrolment alive.** Verify against `GET /v1/vault/private-key` instead — it is encrypted under the vault key and exists in both formats. This is the same fix already applied on web.

- [ ] **Step 3: Cache records in the App Group**

`SharedVaultStore` gains record + cursor persistence alongside the existing blob cache, so AutoFill keeps working offline.

- [ ] **Step 4: Verify and commit**

```bash
scripts/test.sh --unit
git commit -m "feat(pass): delta sync for per-item vault records"
```

---

### Task 4: Per-record writes in `PassService`

**Files:**
- Modify: `ios/Groo/Features/Pass/PassService.swift`
- Test: `GrooTests/Features/Pass/PassRecordWriteTests.swift`

- [ ] **Step 1: Write the failing tests**

| Test | Asserts |
|---|---|
| save new item | one `POST /v1/vault/records`; no `PUT /v1/vault` |
| save existing item | `PUT` carries the last-synced version |
| trash | writes the payload with `deletedAt`; **never** calls `DELETE` |
| permanent delete | calls `DELETE` (a tombstone) |
| same-record conflict | field-merges onto the server copy and retries once |
| passkey `signCount` conflict | merged value is `max(local, server)` |

- [ ] **Step 2: Implement**

Route `saveItem`/`deleteItem`/`permanentlyDelete`/folder writes through a `writeRecord(id:kind:payload:)` helper at `formatVersion == 2`, keeping the existing `saveVault()` path for `1`.

- [ ] **Step 3: Verify and commit**

```bash
scripts/test.sh --unit
git commit -m "feat(pass): per-record writes replace whole-vault saves"
```

---

### Task 5: Wire the app UI and confirm the format gate

**Files:**
- Modify: the Pass settings view

- [ ] **Step 1: Surface the unconverted state**

At `formatVersion == 1`, show "Open the Pass web app to finish upgrading." iOS has no conversion code by design — the riskiest logic exists in exactly one client.

- [ ] **Step 2: Handle `410 FORMAT_MIGRATED`**

If any legacy call returns `410`, show "Update required" and refuse to render a cached vault. A stale-but-readable vault is how a passkey registered after the cutover gets lost.

- [ ] **Step 3: Commit**

---

### Task 6: Auth reachable from the AutoFill extension

Carried over unchanged from the AutoFill spec's Phase 3, which this plan absorbs.

**Files:**
- Move: `GrooAuthConfig+iOS.swift` → `Shared/SharedGrooAuthFactory.swift`
- Create: `Shared/NonDestructiveTokenStore.swift`
- Modify: `GrooAutoFill` target — link `GrooAuth`
- Test: `GrooTests/Shared/NonDestructiveTokenStoreTests.swift`

**Interfaces:**
- `SharedGrooAuthFactory.makeConfig()`, `.makeSession()` (app), `.makeTokenOnlySession()` (extension).
- `NonDestructiveTokenStore`: a `TokenStoring` decorator whose `clear()` is a logged no-op.

**Why:** access tokens live 15 minutes, so a non-refreshing extension would almost never hold a usable one. But a rejected refresh calls `tokenStore.clear()` + `publish(.signedOut)`, and the extension shares that Keychain item — so an extension-side rejection would sign the user out of the whole app. `save` must still pass through, or the app would later present a revoked token.

`makeTokenOnlySession()` uses a `WebAuthenticating` stub that throws: the extension must never present sign-in UI from an AutoFill sheet.

- [ ] **Step 1: Test that `clear()` never reaches the underlying store, while `load`/`save` pass through**
- [ ] **Step 2: Implement, register, link `GrooAuth` into `GrooAutoFill`**
- [ ] **Step 3: Verify the extension can obtain a token** (on-device; extension logs need a device log archive, so surface state in the extension's own UI for a quick check)
- [ ] **Step 4: Commit**

---

### Task 7: The AutoFill passkey push

**Files:**
- Create: `Shared/PasskeyPublisher.swift`
- Modify: `GrooAutoFill/CredentialProviderViewController.swift` (construction only)
- Modify: `ios/Shared/SharedPendingItemsStore.swift` — add `remove(credentialId:)`
- Test: `GrooTests/Shared/PasskeyPublisherTests.swift`

**`PasskeyPublisher` lives in `Shared/`, not the extension**, because `GrooTests` cannot compile extension-target sources. The file in `GrooAutoFill/` is construction only.

**The push exists only at `formatVersion == 2`.** At `1` the extension behaves exactly as today: queue, and let the already-shipped app-side drain merge it. The blob-based push from the superseded spec is **never built**.

- [ ] **Step 1: Write the failing tests**

| Test | Asserts |
|---|---|
| happy path | one `POST /v1/vault/records`; record added to cache; only that item removed from the queue |
| **cursor untouched** | the App Group sync cursor is unchanged after a push |
| no base vault needed | the push succeeds with an empty/absent cache — no `GET` at all |
| offline | item stays queued; publisher never throws into the ceremony |
| deadline exceeded | same, within 5s |
| 401 | queued, logged, **no sign-out** |
| format 1 | no push attempted; item stays queued |
| targeted removal | two queued, one pushes, the other survives |

- [ ] **Step 2: Implement**

In `completePasskeyRegistration`, after Face ID and `createRegistration`:

1. `savePendingPasskey(item)` — unchanged, still first. Never hand out a credential we did not store.
2. Build one record from the passkey's encoded shape, matching `PassPasskeyItem` exactly — including the stored `type: "passkey"` discriminator and the optional `folderId`/`favorite`/`deletedAt` — or other clients will not parse it.
3. `POST /v1/vault/records`. The id is brand new, so **no conflict is possible**: no 409 path, no retry, no base-vault fetch.
4. On success, insert into the App Group cache but **leave the cursor alone** (see Global Constraints).
5. `remove(credentialId:)` from the queue.
6. **Complete the ceremony regardless of outcome.**

Deadline 5s total, overridable via `passkeyPushDeadlineSeconds` in the App Group defaults. `PassAPIClient` sets `timeoutIntervalForRequest = 30`, which would hold the sheet open far too long.

`forceRefresh` throws immediately so a 401 becomes a plain failure; one refresh attempt, no retry loops. Combined with the 5s deadline this makes a 120s-late refresh replay structurally impossible.

Every failure path logs at `.error` — silent `cancelRequest` calls are what made the two preceding AutoFill bugs undiagnosable.

- [ ] **Step 3: On-device verification**

Not reachable from `GrooTests`. Clean-build first (the embedded `.appex` goes stale), then register a passkey in Safari against a real relying party and confirm it appears in the web app **without cold-starting the iOS app**. Repeat in airplane mode and confirm the ceremony still completes with the passkey queued.

- [ ] **Step 4: Commit**

---

## Self-review notes

- **Spec coverage:** envelope crypto with cross-client fixture (T1), client relocation + endpoints (T2), delta sync incl. the biometric-verification fix (T3), per-record writes incl. `signCount` max() (T4), format gate + `410` handling (T5), extension auth (T6), passkey push with the cursor rule (T7).
- **Deliberately not built:** conversion (web only), and the blob-based passkey push from the superseded spec.
- **Highest residual risk:** byte-format drift between `SharedRecordCrypto` and `@pass/crypto`. T1 Step 6's committed fixture is the only thing that catches it before a device fails to open a real vault — do not skip it.
