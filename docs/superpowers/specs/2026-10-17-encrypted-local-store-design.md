# Encrypted local store — design

**Status:** design agreed 2026-10-17, unimplemented.
**Reference implementation:** `bt/space` `apps/ios/space/Packages/SpaceStore`, and
its spec `docs/superpowers/specs/2026-10-12-ios-offline-first-email-design.md`.
Read §4 of that document before changing anything here; this design follows it
deliberately and departs from it in three places, each recorded below.

## 1. Goal

Everything Groo keeps on the device lives in one encrypted database, openable
only after Face ID or the device passcode. One unlock replaces three. The app
stays usable when the account session lapses — that half shipped separately
(`dadc3b0`) and is not re-specified here.

## 2. Current state

Verified 2026-10-17 by reading the tree, not from memory.

| Data | Where | Encrypted? |
|---|---|---|
| Pad notes | SwiftData `default.store`, App Group | field-level (`encryptedTextJSON`) |
| Scratchpad | same | field-level (`encryptedContentJSON`) |
| Stock holdings | same | **no** |
| Stock transactions | same | **no** — every buy and sell, in the clear |
| Cached token prices | same | no (not sensitive) |
| Pending operations | same | `payloadJSON`, varies |
| Pass vault | App Group files via `SharedVaultStore` | field-level |

The database file itself is plaintext SQLite, and nothing excludes it from
backup, so the holdings and transactions are also sitting in iCloud backups in
the clear.

**Keys today.** `pad_encryption_key` and `pass_encryption_key` are
password-derived; the Keychain copy is a biometric *cache*, not the source
(`PadService.swift:140` — "Biometric unlock will be unavailable until the next
password unlock"). Both are stored `.biometryCurrentSet`, so re-enrolling a face
destroys them; the app survives that only because of the password fallback.

**Readers.** The app, plus `WidgetExtension` and `KeyboardExtension`, which open
`default.store` directly with mirror models. **Both have always failed**: they
query the Keychain with an app group as `kSecAttrAccessGroup` while holding no
`keychain-access-groups` entitlement, so the read returns `errSecItemNotFound`
and they render their locked state without ever opening the database. See
`CLAUDE.md`. `GrooAutoFill` works because it declares the entitlement.

## 3. Rulings

**R1 — One store, GRDB + SQLCipher, fork pinned exact.**
`groo-dev/GRDB-SQLCipher`, tag `v7.11.1-sqlcipher.1`, pinned `exact:`. The same
fork `bt/space` uses; this is a second consumer, not a second fork.

**R2 — A local package, `Packages/GrooStore`, built as a dynamic framework, is
the only module that imports GRDB.** No GRDB type crosses its boundary. This is
not tidiness: it is what makes R9's build-time check possible, because there is
exactly one binary to inspect. `Packages/WalletCoreBinary` already establishes
the local-package convention in this repo.

**R3 — Key hierarchy, copied from Space.**

```
Secure Enclave P-256      .privateKeyUsage + .userPresence
   private key never leaves hardware
        │ HPKE P256_SHA256_AES_GCM_256, info "groo.store.master.v1"
        ▼
master key                32 random bytes, stored only sealed
        │ HKDF-SHA256, salt "groo.store.v1"
        └── info "sqlcipher" → database key
```

`.userPresence`, **not** `.biometryCurrentSet`. Groo uses the latter today and
gets away with it only because of the password fallback; the store has no such
fallback for stock data, so a re-enrolled face must not cost anything. Sealing
needs only the public key, so creating a master key needs no prompt; only
opening does.

**R4 — The Pad content key moves into the store. The Pass key does not, yet.**
This is a deliberate departure from "all keys in one place", and the reason is
`GrooAutoFill`. It needs `pass_encryption_key` and it works today. Reaching it
from inside the store means linking SQLCipher into an extension with a tight
memory budget *and* putting a second process on the database file, which would
forfeit R5. Breaking password AutoFill is not an acceptable cost for tidiness.
Phase 3 decides it on evidence from a size-and-memory spike. Until then the Pass
vault and its key stay exactly where they are.

**R5 — One process opens the database.** The app. The Widget and Keyboard are
cut off and given an honest "Open Groo to view" state. This costs nothing: §2
establishes they have never read anything. Space has to assert this property;
Groo gets it for free.

**R6 — One unlock.** Face ID (passcode fallback) opens the store, and the Pad
key comes out of it. The separate Pad unlock disappears. Pass keeps its own
unlock until R4 is resolved.

**R7 — Only provable key loss wipes.** `.keyUnusable`, or a missing root/master
key while a database file exists. Cancel, authentication failure, missing
passcode, I/O error, missing cipher all propagate untouched. A changed or nil
user **locks and never wipes** — a failed Keychain read is indistinguishable
from a sign-out, and destroying data on an inference is not acceptable. Wiping
happens only through an explicit sign-out path.

**R8 — Stocks are local-only by design (owner, 2026-10-17), so the backup path
is a precondition, not a nicety.** Today that data survives a new phone because
the plaintext store is in the iCloud backup — exactly what this work removes.
Once the store is encrypted with a device-bound key, a restored backup is
unreadable. Settings already has "Backup to Pass", and Pass syncs. Making that
automatic is the whole fix, and it ships **before** the store goes dark.

**R9 — The encryption is proven mechanically, not assumed.**
- `PRAGMA cipher_version` non-empty, checked on every connection; refuse to open
  otherwise. A mis-linked build otherwise opens the file unencrypted and reports
  success.
- `PRAGMA cipher_compatibility = 4`, pinned, so a future SQLCipher default
  change cannot make a valid store read as `NOTADB` — which R7 would classify as
  key loss.
- `scripts/check-sqlcipher-binding.sh` on a **Release** build: no `libsqlite3`
  load command, no `_sqlite3_*` import that is not from SQLCipher, and **at
  least one that is**. The third assertion is the one that matters — without it
  a build with GRDB not linked at all passes vacuously.

**R10 — Migration is one-way, verified before anything is deleted.** Read the
SwiftData store, write the encrypted one, verify row counts and a sample of
content, and only then delete. A failed migration leaves the old store intact
and reports; it never half-moves.

**R11 — Error text never carries key material.** A GRDB `DatabaseError` can
carry the `PRAGMA key` statement in its `description` and `sql`. One function
converts GRDB errors to store errors and emits codes only.

## 4. Layout

```
Application Support/groo-store/<userId>/
    groo.sqlite        protection: completeUntilFirstUserAuthentication
```

`completeUntilFirstUserAuthentication`, not `complete`: the stricter class
breaks a WAL write in the seconds after the device locks. The file is encrypted
by SQLCipher regardless.

Excluded from backup — but only once R8 has landed, because until then the
backup is the only copy of the holdings.

## 5. Lock and unlock

Locks on cold launch, after a configurable interval in the background
(`storeAutoLockSeconds`, default 300, `0` meaning immediately), and on sign-out.

Measured on `ContinuousClock`, so moving the wall clock cannot defeat it.
`.unlocking` counts as lockable — an unlock can land after the app is already
away.

`lock()` closes the database and drops key references. CryptoKit cannot zero a
`SymmetricKey`; dropping references is the best available and the code says so.
Anything decrypted to disk for preview is purged on lock.

**A lapsed account session locks but never wipes, and does not re-arm
auto-unlock** — a Face ID prompt appearing because a token expired is baffling.
This is where `requiresReauth` (`dadc3b0`) and the store meet.

## 6. Phases

| Phase | Content | Gate |
|---|---|---|
| 0 | Automatic Backup to Pass for stock data (R8) | holdings survive a device loss |
| 1 | `GrooStore` package, keys, schema, open/lock/wipe, binding check | store opens and locks; nothing reads it yet |
| 2 | Migrate Pad, Scratchpad, Stocks, prices, outbox; cut the extensions off; retire the Pad unlock | app reads from the store only |
| 3 | Decide the Pass vault on spike evidence (R4) | AutoFill still works, or stays as-is |

Phase 0 first, deliberately. It is the only phase whose absence can lose data
that exists nowhere else.

## 7. Tests

- Key loss, every flavour: Keychain wiped, master key undecodable, database
  present with no keys. Each must land on the right side of R7.
- A cancelled Face ID must leave everything intact and wipe nothing.
- `PRAGMA cipher_version` empty must refuse to open.
- Backgrounded for interval−1s and interval+1s, and `0` meaning immediately.
- Migration: row counts and sampled content match; a failed migration leaves the
  old store intact.
- The binding check, on Release, mutated three ways: no SQLCipher import, a
  `libsqlite3` load command, and GRDB absent entirely.

Every test armed by mutation before it is trusted. A key-loss test that has
never reddened proves nothing, and the thing it guards is the user's data.

## 8. Open questions

- **R4 / Phase 3.** Does SQLCipher fit in the AutoFill extension's memory
  budget? Needs a spike, not an opinion.
- **The Pad widget.** It has never worked. Under R5 it stays dark on purpose.
  Whether Groo wants a working Pad widget at all is a product decision, and if
  the answer is yes, R5 has to be reopened rather than worked around.
