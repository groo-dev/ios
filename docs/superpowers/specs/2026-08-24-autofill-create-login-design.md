# Creating a login from the AutoFill sheet — design

**Date:** 2026-08-24
**Status:** approved (design), not implemented
**Repo:** `ios`

## Problem

The AutoFill sheet is read-only for passwords. A user who taps a password
field on a **sign-up** screen, or on a **sign-in** screen for an account Groo
does not yet hold, has nowhere to put a password: the sheet lists what exists
and offers no way to add. The user must leave the flow, open the Groo app,
create the item, return, and start the field over.

iOS offers no hook for this. The system "save this password?" prompt writes to
iCloud Keychain only; a third-party credential provider is never consulted. The
only place a provider can offer creation is **inside its own sheet**, which is
what every other provider does.

The extension is not write-incapable — it already authors one kind of item.
Passkey registration writes to an encrypted App Group queue
(`Shared/SharedPendingItemsStore.swift`), best-effort pushes one record
(`Shared/PasskeyPublisher.swift`), and the main app drains the queue
(`PassService.mergePendingPasskeys()`, `Groo/Features/Pass/PassService.swift:1003`).
Nothing equivalent exists for passwords: the queue is typed
`[SharedPassPasskeyItem]` (`SharedPendingItemsStore.swift:33`) and the drain
only understands passkeys.

## Scope

**In:** creating one password item from the credential-list sheet — site,
username, password (typed or generated) — saving it durably, filling the field
with it, and getting it to the server and into the main app's vault.

**Out:** editing or updating an existing item from the sheet; notes, TOTP,
folders, favourites, multiple URLs on the new item; passkey creation (that is
relying-party driven and already exists); any change to the system save prompt.

## Decisions

### D1. Queue-then-push, merged at read time

Three options were considered for where a newly created item is written.

**Author into the local record cache** (`SharedRecordStore`) so it appears in
the list immediately. **Rejected:** that cache is a cursor-driven mirror of
server truth — `SharedRecordStore.apply(_:page:)` reconciles against fetched
pages — so a locally injected record with no server row has no defined
lifetime. It is either dropped on the next refresh or persists as a phantom.

**Push-only, refuse to save when offline.** **Rejected** on the product call:
it strands the user mid-sign-up with a password and nowhere to put it.

**Queue-then-push (chosen).** Write locally first, push best-effort, merge the
queue into what the sheet reads, and let the app drain it — the exact shape
passkey registration already uses and the app already understands.

### D2. A second queue file, not a widened one

`pending_passwords.enc` alongside `pending_passkeys.enc`, both under
`pass/` in the App Group container.

The existing file holds **unsynced passkey private keys** — material that, until
the app drains it, exists nowhere else on earth. Any format migration on that
file risks losing it. A second file has no migration and no shared failure mode.
The *store code* is generalized over the element type; the passkey file's bytes
are never touched, and its `.corrupt` move-aside behaviour is preserved
verbatim.

### D3. The push is awaited, bounded, before the request completes

`extensionContext.completeRequest` tears the extension process down. A push
still in flight dies with it. So the save awaits the push under a deadline
(`SharedConfig.passwordPushDeadlineSeconds`, defaulting to 5s exactly as
`passkeyPushDeadlineSeconds` does at `SharedConfig.swift:48`) and completes
regardless of the outcome — a failed push leaves a queued item, never a lost
one.

### D4. The payload is hand-built JSON

`SharedPassPasswordItem` (`Shared/SharedPassModels.swift:153`) does not model
`createdAt` or `updatedAt`. Both are **required** by every other client:
`PassPasswordItem.init(from:)` decodes them non-optionally
(`Groo/Features/Pass/Models/PassModels.swift:460`), and the web/extension
`PasswordItem` extends a `BaseItem` that declares them
(`~/work/gr/pass/apps/web/src/lib/types.ts:81-100`). Encoding the shared model
directly produces a record every other client fails to decode. This is the
identical trap `PasskeyPublisher` documents in its `payload(for:)` header.

The payload is therefore built as a dictionary and serialized with
`.sortedKeys`, matching `PasskeyPublisher.payload(for:)`. Optional fields
(`notes`, `totp`, `folderId`, `favorite`, `deletedAt`) are **omitted**, not sent
as null — matching how the web app encodes an item that has none.

### D5. Creation is offered only where a password credential is a valid answer

Whether `completeRequest(withSelectedCredential:)` is legal depends on which
entry point iOS used. It is valid for both `prepareCredentialList` overloads
(`CredentialProviderViewController.swift:186`, `:193`) and for the list
fallback when a requested password identity is missing from the vault
(`:176`). It is **not** valid on a passkey assertion request, which must be
answered with `completeAssertionRequest`.

The controller therefore sets an explicit `allowsCreatingPassword` flag at each
entry point and passes it into the view. The view does not infer it from
`rpId`, `serviceIdentifiers`, or anything else — an inferred rule silently
becomes wrong the next time an entry point is added.

Note this means creation **is** offered during a combined passkey+password
list, which is correct: those sheets already display and fill password rows.

### D6. The drain is renamed, not duplicated

`mergePendingPasskeys()` becomes `mergePendingItems()`, draining both queues.
There are nine call sites (`PassService.swift:185, 234, 303, 325, 364, 1073,
1089, 1129` and `ContentView.swift:90`). Adding a parallel
`mergePendingPasswords()` would make a missed call site a silently un-drained
queue holding the user's password; renaming makes it a compile error.

### D7. Dedupe by `id`

The extension authors the item's UUID, and the pushed record keeps it, so an
item that was pushed *and* then drained is recognised as the same item. Name,
username or URL would not be — a user may legitimately hold two logins for the
same site with the same username.

### D8. The drain refreshes records before merging

Found while planning, and it applies to the existing passkey drain too.

`writeRecordIfChanged` (`Groo/Features/Pass/PassService.swift:951-989`) chooses
POST over PUT purely on whether `recordState` holds the id. When the extension
has already pushed a record and the app's `recordState` is stale — the
`ContentView.swift:90` foreground call reaches the merge with no preceding load
— the drain POSTs an id the server already holds. The server answers `409
RECORD_EXISTS`, which is **not** the `APIError.recordConflict` the PUT path
recovers from, so `saveVault()` throws and the drain fails until something else
refreshes the records.

`mergePendingItems()` therefore pulls records first when `formatVersion == 2`.
Combined with D4's envelope timestamps this makes the drain a genuine no-op for
an already-pushed item: `recordState` holds the record, the rebuilt payload is
byte-identical, and `writeRecordIfChanged` returns early. A failed refresh is
logged and the merge proceeds — an item that cannot be written just stays
queued.

## Components

### New — `Shared/SharedPasswordGenerator.swift`

Pure generation, extracted from the `private func generatePassword()` inside
`Groo/Features/Pass/Views/PasswordGeneratorView.swift:238`. It is currently
unreachable from the extension (app target) and untested (private, inside a
`View`).

```swift
struct SharedPasswordGeneratorOptions {
    var length: Int = 20
    var includeUppercase = true
    var includeLowercase = true
    var includeNumbers = true
    var includeSymbols = true
}

enum SharedPasswordGenerator {
    static func generate(_ options: SharedPasswordGeneratorOptions) -> String
}
```

Behaviour is preserved exactly, including the guarantee of at least one
character from each enabled class and the final shuffle. `PasswordGeneratorView`
is rewritten to call it, so the app and the extension cannot drift.

### New — `Shared/SharedNewLoginDraft.swift`

The form's pure logic, in `Shared/` so `GrooTests` can reach it — extension
sources are not compilable into the test bundle, which hosts the app.

```swift
struct SharedNewLoginDraft {
    var name: String
    var username: String
    var password: String
    var site: String

    /// Default item name from the request's host, with a leading "www."
    /// stripped: "www.github.com" -> "github.com". Nil host -> "New Login".
    static func defaultName(forHost host: String?) -> String

    /// "github.com" -> "https://github.com"; an already-schemed URL is kept.
    static func normalizedURL(_ site: String) -> String?

    var isSaveable: Bool          // non-empty password
    func pendingItem(id: String, now: Int) -> SharedPendingPasswordItem
}
```

### Changed — `Shared/SharedPassModels.swift`

`SharedPassPasswordItem` declares `init(from decoder:)` in its body
(`:190`) and no other initializer, which suppresses Swift's synthesized
memberwise init — today it can only be produced by decoding. It gains an
explicit memberwise `init`, exactly as `SharedPassPasskeyItem` already has one
(`:250`) for the same reason: the extension authors that item.

### New — `Shared/SharedPendingPasswordsStore.swift`

Same three operations as the passkey queue — `load`, `append`, `clear` — over
`pass/pending_passwords.enc`, AES-GCM under the vault key, with the same
"never overwrite an unreadable queue, move it aside as `.corrupt`" rule. The
shared mechanics are factored into a generic helper used by both stores;
`SharedPendingItemsStore`'s public API and file path are unchanged.

### New — `Shared/PasswordPublisher.swift`

Mirrors `PasskeyPublisher`: a `PasswordRecordPushing` seam, a format-2 gate
(at format 1 the blob is authoritative and app-owned, so the item stays
queued), one `POST /v1/vault/records` with a brand-new id — no version to
guess, no 409 path, no retry — and a `PasswordPublishOutcome` of
`.published` / `.queued(reason:)`. It never throws: a failure leaves the item
queued and logged.

Like the passkey publisher it is constructed with
`forceRefresh: { throw APIError.unauthorized }`. **This is load-bearing:** a
late token refresh from an extension revokes the refresh-token family and
signs the user out of every device.

As with passkeys, a successful push does **not** remove the item from the
queue. The queue means "not yet in the cache the extension reads"; the app
clears it after merging *and* refreshing.

### New — `GrooAutoFill/NewLoginView.swift`

Form over a `SharedNewLoginDraft`: site (prefilled from the request host or
rpId, editable), name (defaulting to the host), username (focused first,
`.textContentType(.username)`, no autocapitalization), password
(`SecureField` with a reveal toggle and a **Generate** button). Save is
disabled until there is a password; a "Saving…" state covers the bounded push.
Errors are shown inline and leave the form open with its content intact.

### Changed — `GrooAutoFill/AutoFillCredentialListView.swift`

A `+` toolbar item (`topBarTrailing`) shown when unlocked and
`allowsCreatingPassword`, and a "New Login" action inside the existing
`ContentUnavailableView` empty state (`:227`). Both present `NewLoginView`.

### Changed — `GrooAutoFill/AutoFillService.swift`

```swift
func createPassword(_ draft: SharedNewLoginDraft) async throws -> SharedPassPasswordItem
```

1. Build the item with a fresh lowercased UUID.
2. `SharedPendingPasswordsStore.append` — local durability first. A throw here
   aborts the save and is shown to the user; nothing is filled.
3. `PasswordPublisher.publish`, awaited under the deadline. Never throws.
4. `ASCredentialIdentityStore.saveCredentialIdentities` for the normalized
   host, so QuickType offers it on the next field without waiting for the app.
5. Append to `credentials` so the item is present if the sheet survives.

`withPendingPasskeys` gains a `withPendingPasswords` sibling, applied in
`loadCredentials()` (`:96`) and `performRefresh(using:)` (`:224`) so a second
sheet before the app runs still shows the item. Dedupe by `id` per D7, via a
`SharedCredentialMatcher.mergingPendingPasswords(vault:pending:)` mirroring
`:103`.

### Changed — `Groo/Features/Pass/PassService.swift`

`mergePendingItems()` per D6: the existing passkey merge unchanged, then
pending passwords appended as `PassPasswordItem`s (skipping ids already in the
vault), one `saveVault()` for both, then both queues cleared. A failure keeps
**both** queues for the next attempt. `PendingPasskeyStoring` gains a
`PendingPasswordStoring` sibling so tests can drive the queue without an App
Group.

### Changed — `Groo/Features/Pass/Views/PassItemListView.swift`

A `pendingSyncCount` published by `PassService`, surfaced as a banner with a
Retry action when a drain has left items queued. On the normal path this
clears within milliseconds of the app opening and is never seen; it exists so
that a *persistently* failing drain — the case where a password lives only on
this device — is visible rather than silent.

## Data flow

```
user taps + in sheet
  -> NewLoginView (draft)
  -> AutoFillService.createPassword
       -> pending_passwords.enc            (durable, local, synchronous)
       -> PasswordPublisher.publish        (best effort, <=5s, never throws)
       -> ASCredentialIdentityStore        (QuickType, best effort)
  -> completeRequest(withSelectedCredential:)   [field fills, process ends]

next app run
  -> PassService.mergePendingItems()
       -> vault.items += pending           (dedupe by id)
       -> saveVault()
       -> clear both queues                (only on success)
```

## Error handling

| Failure | Behaviour |
|---|---|
| Vault locked when Save is tapped | Save is unreachable — the form is only presented from the unlocked list |
| Queue write throws | Save aborts, error shown in the form, nothing filled. The one failure the user must see: without the queue there is no durability at all |
| Push fails / offline / token expired | Item stays queued, filled anyway, logged at `.error`. Never surfaced as a save failure |
| Vault at format 1 | Push skipped by the gate, item stays queued for the app |
| QuickType save fails | Logged only; the item is in the vault and the sheet, just not suggested until the app runs |
| Drain fails in the app | Both queues kept, banner shown with Retry |
| Records refresh fails before a drain | Logged; the merge proceeds against what is cached |
| Pending queue unreadable | Moved aside as `.corrupt`, never overwritten; already the passkey store's rule |

## Testing

Unit (`GrooTests`), all reachable because the logic lives in `Shared/`:

- **`SharedPasswordGenerator`** — requested length; at least one character from
  each enabled class; only enabled classes appear; empty charset yields empty;
  two calls differ.
- **`PasswordPublisher`** — exact payload keys and their absence when unset
  (`notes`/`totp`/`folderId`/`favorite` must not appear); `createdAt` and
  `updatedAt` present and equal; `type` is `"password"`; format 1 leaves it
  `.queued`; a throwing pusher leaves it `.queued` and never propagates.
- **`SharedPendingPasswordsStore`** — round-trip; unreadable file moves aside
  and is not overwritten; **operating on the passwords queue leaves
  `pending_passkeys.enc` byte-identical**.
- **`SharedNewLoginDraft`** — host to default name; bare domain to `https://`;
  an already-schemed site kept as-is; `isSaveable` boundaries.
- **`SharedCredentialMatcher.mergingPendingPasswords`** — dedupe by id; a
  pending item with a new id appears; ordering.
- **`PassService.mergePendingItems`** — passwords merged; ids already present
  skipped; passkey behaviour unchanged; both queues kept when `saveVault`
  throws; both cleared on success; `pendingSyncCount` reports the remainder.
- **Payload equality** — the payload the app rebuilds when draining must
  normalize byte-identically to `PasswordPublisher.payload`. Without it, D8's
  no-op does not hold and every drain rewrites a correct record.

Manual (the form is extension UI, which cannot be snapshot-tested here):
simulator run through `prepareCredentialList`, then a real-device pass — create
a login on a sign-up page, confirm the field fills, confirm the item reaches
the server, and confirm a second sheet shows it before the app is opened.
Offline repeat, confirming the queue drains on the next app launch.

## Security review points

- Password material now reaches a second App Group file. Same vault key, same
  AES-GCM sealing, same container — no new key, no new location class.
- No credential field (`password`, `username`, or the payload) may appear in a
  log line at any level. The publisher logs the item id only.
- `forceRefresh` stays disabled in the extension (family revocation).
- The record id is client-generated and brand new, so no read-modify-write of
  another item is possible from the extension.
- The clipboard behaviour in `selectCredential` is untouched; a newly created
  item has no TOTP and never populates it.

## Build notes

Every new `Shared/` file must be registered with
`ruby scripts/register_shared_file.rb <File.swift> Groo GrooAutoFill GrooTests`
(plus any other consuming target) — `Shared/` is not a filesystem-synchronized
group, and an unregistered file compiles into nothing. Files added under
`GrooAutoFill/` are picked up automatically.

No `Info.plist` or entitlements change: this uses capabilities the extension
already declares.
