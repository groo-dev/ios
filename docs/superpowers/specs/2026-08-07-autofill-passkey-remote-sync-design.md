# AutoFill passkey remote sync — design

**Date:** 2026-08-07
**Status:** approved. Phase 1 implemented; Phases 2 and 4 partially superseded — see below.

> **Supersede note (2026-08-07).** After approval we established that
> `vaults.encrypted_data` is a single AES-GCM blob (`pass` `db/schema.ts:5-18`),
> so *every* client — including the existing app — must re-encrypt the whole
> vault to add one item. A separate design is being explored to migrate the
> personal vault to **per-item rows**, mirroring the `shared_items` table and its
> `/v1/shared-folders/:folderId/items` endpoints, which would remove whole-vault
> re-encryption for all clients.
>
> What that would change here: only the vault-mutation mechanism in Phases 2
> and 4 — `SharedRawJSON`, `SharedVaultDocument`, `SharedCrypto.encryptVault`,
> the whole-blob `PUT`, and the 409 retry.
>
> What still stands regardless: the problem statement, **Phase 1** (app-side
> drain, independent of storage model), **Phase 3** and every auth finding
> (15-minute tokens, refresh rotation with family revocation,
> `NonDestructiveTokenStore`, no `forceRefresh`, the 120s replay window), the
> lossy-`Shared`-models constraint, and the tooling traps.

## Problem

A passkey registered through the AutoFill extension does not reach the Pass
server until the main app is cold-started. Investigation found the delay is the
intended design, plus two defects that make it far worse than intended.

**Intended design.** The extension writes the new passkey to an encrypted queue
in the App Group (`pass/pending_passkeys.enc`, `SharedPendingItemsStore`). The
main app's `PassService.mergePendingPasskeys()` merges it into the vault,
pushes via `saveVault()` → `PUT /v1/vault`, then clears the queue. Documented at
`SharedPendingItemsStore.swift:5-8`.

**Defect 1 — the merge only runs on unlock.** Its call sites are
`PassService.swift:198`, `:267` and `:314`, all unlock paths. `sync()` (`:846`)
never calls it.

**Defect 2 — the app never re-locks on background.** There is no `scenePhase`
handling outside `AzanView`, and `needsGlobalUnlock` is set only on the
logged-out → logged-in transition (`ContentView.swift:108`). Backgrounding the
app, registering a passkey in Safari and returning does not merge anything.

Together these mean the merge effectively only happens on a **cold start**.

**Why it matters.** Until the merge runs, the passkey's *private key* exists only
in `pending_passkeys.enc`, while the relying party already recorded the
credential as successfully registered. If the app is uninstalled, the device is
lost, or the queue hits the `.corrupt` move-aside path
(`SharedPendingItemsStore.swift:71-75`), the passkey is unrecoverable and the
user is locked out of an account that believes the passkey works. Nothing in the
UI indicates the passkey is pending, so this is silent data loss rather than a
visible delay.

## Goal

The extension pushes the passkey to the server during the registration ceremony,
so it is durable and usable from other clients immediately. The queue is retained
as the offline / auth-failure fallback, and the app drains it promptly.

Non-goal: changing when the app locks.

## Constraints discovered

These shaped the design and are recorded because each one rules something out.

**The vault is a single opaque blob.** `PUT /v1/vault` takes
`{encryptedData, iv, expectedVersion}` and the server cannot decrypt it, so
server-side merging of an item is impossible without redesigning storage to
per-item rows across the API, web and browser extension. Out of scope.

**Optimistic locking.** `PUT /v1/vault` (`pass/apps/api/src/routes/vault.ts:138`)
returns `409` with code `VERSION_CONFLICT` and `currentVersion` when
`expectedVersion` does not match.

**`PUT /rekey` only rewraps.** It "never reads or writes encrypted_data, and
never changes version" — it replaces the passphrase-derived wrapping of the same
vault key. No vault-key rotation exists, so a stored vault key does not go stale.

**Access tokens live 15 minutes** (`ACCESS_TOKEN_TTL = 900`,
`accounts/api/src/services/token.service.ts:8`). The extension usually runs when
the app has not been used recently, so an extension that cannot refresh would
almost never hold a usable token. Pushing therefore requires the extension to
participate in token refresh.

**Refresh tokens rotate, with theft detection.** `rotateRefreshToken`
(`accounts/api/src/services/oauth.service.ts:181`) marks the presented token
revoked; presenting a revoked token calls `revokeRefreshTokenFamily`, signing the
user out everywhere. A KV replay cache keyed by the old token's hash tolerates
concurrent rotations of the *same* token for `REFRESH_REPLAY_TTL = 120` seconds.
Mitigating factor: `GrooAuthSession.accessToken()` reloads from the Keychain on
every call rather than trusting an in-memory cache, so a process holds a token
only for one round trip. The only way to fall outside the grace window is an
extension suspended mid-refresh that retries later.

**A rejected refresh clears the shared tokens.** `performRefresh` does
`try? tokenStore.clear()` + `publish(.signedOut)` on `invalid_grant`. Because the
extension would share that Keychain item, an extension-side rejection would sign
the user out of the whole app.

**Token sharing was already anticipated.** `GrooAuthConfig+iOS.swift` uses a
literal `keychainService` (`dev.groo.ios[.debug]`, not bundle-derived) and
`keychainAccessGroup: nil`, with a comment stating this is deliberate so the
AutoFill extension shares the group.

**The app already solved this problem — reuse its mechanism.** `PassRawJSON`
(`Groo/Features/Pass/Models/PassModels.swift:130`) is an
`indirect enum … Codable, Equatable` documented as a "Lossless JSON value — used
to preserve the original bytes of items that fail to decode, so they can be
re-encoded verbatim instead of destroyed", backing `PassCorruptedItem`. The
extension's vault mutation uses the same approach via a `Shared/` mirror, rather
than `JSONSerialization` and `[String: Any]`: it stays `Codable` and `Sendable`
(no `Any` crossing concurrency boundaries), and being `Equatable` it makes the
round-trip test a structural equality assertion.

**`Shared/` typed models are lossy — the highest-stakes constraint.**
`SharedPassVaultItem` (`Shared/SharedPassModels.swift:66-69`) collapses every
non-password, non-passkey item into a valueless `case other`, and its
`CodingKeys` are the subset `type, id, username, password, urls, rpId,
credentialId`. Decoding the vault into `SharedPassVault`, appending, and
re-encoding would **destroy every note, card, bank account, file and crypto
wallet**, plus unmodelled password fields. The extension must never round-trip
the vault through these models.

**`Shared/` is not a filesystem-synchronised pbxproj group.** Every new file
there must be registered with `scripts/register_shared_file.rb` or it compiles
into nothing.

## Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Extension auth | Link `GrooAuth` into the extension | 15-minute tokens make a non-refreshing extension useless |
| Push timing | Queue → push → complete ceremony | Preserves "never hand out a credential we didn't store"; registration still works offline |
| Vault mutation | Opaque JSON, never typed models | Typed models silently drop item types |
| Server-side staging table | Rejected | Would not make the passkey usable from web/Firefox without drain logic in every client |
| Lock-on-background | Out of scope | Security-posture change deserving its own decision |

## Architecture

One Pass client shared by both targets, not a second implementation.

| Component | Location | Purpose |
|---|---|---|
| `PassAPIClient` | moves `PassService.swift` → `Shared/SharedPassAPIClient.swift` | Already token-source-agnostic via `tokenProvider`/`forceRefresh` closures |
| `APIError` | moves to `Shared/` | `PassAPIClient` depends on it; already models `unauthorized` and the 409 case |
| `SharedConfig.passAPIBaseURL` | new | Mirrors `Config.passAPIBaseURL` including the UserDefaults override |
| `SharedRawJSON` | new, `Shared/` | Mirror of the app's existing `PassRawJSON` (`PassModels.swift:130`): an `indirect enum … Codable, Equatable` lossless JSON value |
| `SharedVaultDocument` | new, `Shared/` | The lossless core: decodes the vault into `SharedRawJSON`, appends to `items`, bumps `lastModified`, re-encodes |
| `SharedCrypto.encryptVault` | new | Byte-compatible counterpart to `CryptoService.encryptData` (IV ‖ ciphertext ‖ tag) |
| `SharedVaultStore.saveVault` | new | Lets the extension refresh the App Group cache and metadata |
| `SharedPendingItemsStore.remove(credentialId:)` | new | Targeted removal; `clear()` alone would discard other queued passkeys |
| `PasskeyPublisher` | new, `Shared/` | Orchestrates queue → push → cache → queue removal, behind protocol seams |
| `SharedGrooAuthFactory` | moves `GrooAuthConfig+iOS.swift` → `Shared/` | One `makeConfig()`; `makeSession()` for the app, `makeTokenOnlySession()` for the extension |
| `NonDestructiveTokenStore` | new, `Shared/` | `TokenStoring` decorator whose `clear()` is a logged no-op |
| `GrooAuth` | link into GrooAutoFill target | Supplies `tokenProvider` |

`PasskeyPublisher` lives in `Shared/`, not the extension, because `GrooTests`
cannot compile extension-target sources. The file in `GrooAutoFill/` is
construction only.

Moving `PassAPIClient` also removes ~120 lines from `PassService.swift`, which is
1054 lines and currently holds both the service and its HTTP client.

## Data flow

In `completePasskeyRegistration`, after Face ID unlock and `createRegistration`:

1. **Queue** — `savePendingPasskey(item)`. Unchanged, still first.
2. **Obtain a base vault** — decrypt the App Group cache if present, else
   `GET /v1/vault`. Absence of a cache must not abort the push.
3. **Mutate as opaque JSON** — `SharedVaultDocument` appends the passkey object to
   `items` and bumps `lastModified`. The appended object must match
   `PassPasskeyItem`'s encoded shape exactly, including its stored
   `type: "passkey"` discriminator (`PassModels.swift:547`) and the optional
   `folderId` / `favorite` / `deletedAt` fields, or other clients will not parse
   it. Nothing else in the document is touched.
4. **Encrypt and push** — `PUT /v1/vault` with `expectedVersion` = base version.
5. **On success** — write the returned version/IV via
   `SharedVaultStore.saveVault`, then `remove(credentialId:)` from the queue.
6. **On 409** — `GET /v1/vault`, re-apply steps 3–4 against the fresh version.
   Exactly one retry.
7. **On anything else** — log, leave queued.
8. **Complete the ceremony** — always, regardless of push outcome.

**Push deadline: 5 seconds** covering all attempts including the 409 retry,
overridable via the UserDefaults key `passkeyPushDeadlineSeconds` in the App
Group defaults (matching how `Config` overrides base URLs). `PassAPIClient` sets
`timeoutIntervalForRequest = 30`, which would hold the sheet open far too long.

**Double-merge is safe.** `mergePendingPasskeys` dedupes on `credentialId`
against `existingCredentialIds`, so a failed queue removal produces a no-op
rather than a duplicate.

**Accepted imprecision.** If the app is running with the vault in memory when the
extension pushes, the app's copy goes stale until its next sync or unlock. It
cannot corrupt anything, because the app's own writes carry `expectedVersion` and
would 409 into a refetch.

## Auth wiring and failure semantics

`makeTokenOnlySession()` uses the shared config with a `WebAuthenticating` stub
that throws: the extension must never present sign-in UI from an AutoFill sheet.

`NonDestructiveTokenStore` passes `load` and `save` through — `save` must persist
the rotated token, or the app would later present a revoked one — but suppresses
`clear()`. Deciding the user is signed out is not the extension's call; the app
discovers the real state on its next refresh and signs out properly, with UI.

The extension's `forceRefresh` closure throws immediately, so
`withUnauthorizedRetry` turns a 401 into a plain failure. `accessToken()` still
refreshes when genuinely expired. One refresh attempt, no retry loops — combined
with the 5s deadline this makes a 120s-late replay structurally impossible.

Every row below ends with the ceremony completing and the passkey staying queued:

| Failure | Behaviour |
|---|---|
| Offline / GET fails / deadline exceeded | Queue, log `.error` |
| Cache decrypt fails | Fall back to `GET`, then as above |
| 401 (no force-refresh) | Queue, log. No sign-out |
| Refresh rejected / signed out | Queue, log `.error`. Tokens left intact |
| 409 twice | Queue, log |
| `PUT` ok, cache write fails | Log. Harmless — app refetches |
| `PUT` ok, queue removal fails | Log. Harmless — merge dedupes |

No new UI: registration succeeded, so a sync warning would be noise. But every
path logs at `.error` — silent `cancelRequest` calls are what made the two
preceding AutoFill bugs undiagnosable.

## App-side drain

Required regardless of the extension push, since the queue remains the fallback.

1. **`mergePendingPasskeys()` at the end of `sync()`** — after the reconcile, so
   the merge applies on top of the freshest `vault`/`serverVersion`, mirroring the
   ordering already used at `:267`.
2. **On foreground** — a `scenePhase` observer in `ContentView`, following the
   pattern `AzanView` uses.

The existing `guard let key = encryptionKey, var vault = vault else { return }`
makes the locked case a safe no-op.

Result: when the push succeeded the queue is already empty; when it failed the
window shrinks from "next cold start" to "next foreground or sync".

Deliberately excluded: retry-on-409 inside `mergePendingPasskeys` (the publisher
already handles conflicts; revisit only if conflicts appear in logs).

## Testing

**The test that retires the data-loss risk:** a fixture vault containing every
item type — password, passkey, note, card, `bank_account`, file, `crypto_wallet`
— plus folders, per-item TOTP and a deliberately unknown future field.
Round-trip it: decode → `SharedVaultDocument` append → re-encode → decode.

Because `SharedRawJSON` is `Equatable`, this asserts **structural equality**
rather than spot-checking fields: the result must equal the input except for the
appended passkey and the bumped `lastModified`. Removing the appended item from
the result must yield a document equal to the original. That is a far stronger
guarantee than field-by-field comparison, and it is the exact failure found in
`SharedPassVaultItem.other`, pinned so it cannot return.

| Test | Asserts |
|---|---|
| Crypto interop | `SharedCrypto.encryptVault` output decrypts via `CryptoService.decryptData` and vice versa |
| Publisher happy path | Pushes, updates cache, removes only that item from the queue |
| 409 retry | First `PUT` 409 → `GET` → second `PUT` succeeds |
| 409 twice | Gives up, item remains queued, no throw escapes |
| Offline / deadline exceeded | Item remains queued; publisher never throws into the ceremony |
| Targeted queue removal | Two queued items, one pushes — the other survives |
| `NonDestructiveTokenStore` | `clear()` never reaches the underlying store; `load`/`save` pass through |
| App-side drain | `mergePendingPasskeys` runs from `sync()` and on foreground |

New API-level tests join the existing `NetworkStubbedSuites(.serialized)`
umbrella, since `StubURLProtocol` carries shared static state.

**Regression guard:** `PassAPIClientTests` and `PassServiceIntegrationTests` must
pass unchanged after `PassAPIClient` relocates.

**Known gaps.** The wiring inside `GrooAutoFill/` and the `GrooAuth` link are not
reachable from `GrooTests` and need on-device verification. The unit suite has 16
pre-existing failures (view snapshots plus one date-dependent
`PrayerTimeServiceTests` case) as of 2026-08-07 — diff against that baseline
rather than treating them as regressions.

## Implementation phasing

Four phases, ordered so each is independently verifiable and safe to stop at.

**Phase 1 — app-side drain.** `mergePendingPasskeys()` from `sync()` and on
foreground, plus tests. Touches only app-target code. Independently shippable and
fixes the originally reported symptom on its own.

**Phase 2 — `Shared/` plumbing, no behaviour change.** Move `PassAPIClient` and
`APIError`; add `SharedConfig.passAPIBaseURL`, `SharedRawJSON`,
`SharedVaultDocument`, `SharedCrypto.encryptVault`, `SharedVaultStore.saveVault`,
`SharedPendingItemsStore.remove(credentialId:)`. The lossless round-trip and
crypto-interop tests land here. Nothing changes at runtime; existing app tests are
the regression guard.

**Phase 3 — auth reachable from the extension.** Move `GrooAuthConfig+iOS.swift`
to `Shared/`, add `makeTokenOnlySession()` and `NonDestructiveTokenStore`, link
`GrooAuth` into the GrooAutoFill target. Still no push — verify only that the
extension can obtain a token.

**Phase 4 — wire the publisher.** `PasskeyPublisher` into
`completePasskeyRegistration`, then on-device verification of the full ceremony
including offline and conflict behaviour.

## Risks

| Risk | Mitigation |
|---|---|
| Vault data loss via lossy re-encode | Opaque JSON only; all-item-types round-trip test |
| Extension signs the user out | `NonDestructiveTokenStore`; no `forceRefresh`; one refresh attempt |
| Refresh-token family revocation | 5s deadline and no retry loops keep replays inside the 120s window |
| `PassAPIClient` relocation breaks the app | Existing app-side tests are the guard |
| Unregistered `Shared/` file compiles into nothing | `scripts/register_shared_file.rb` |
| Stale embedded appex masks plist/entitlement changes | Clean build before device verification (see `ios/CLAUDE.md`) |

## Out of scope

- Lock-on-background.
- Per-item vault storage / server-side merge.
- Making `auth-swift` explicitly multi-process safe (cross-process refresh lock).
  Revisit if sign-outs are observed.
- The browser extension emitting `0x45`/`0x05` authenticator flags without BE/BS.
