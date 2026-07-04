# Groo Pass AutoFill — UX Spec, Gap Analysis & Fix Plan

Date: 2026-07-04
Scope: `GrooAutoFill/` extension, `Shared/`, `Groo/Features/Pass/` (identity sync + vault merge)

## 1. Reference UX (how it should work)

Based on how Bitwarden, 1Password and LastPass behave on iOS, plus Apple's
AuthenticationServices guidelines.

### 1.1 Password autofill

1. **QuickType (inline) suggestion** — When a login field is focused and the vault
   contains a credential matching the site's domain, the credential appears
   directly above the keyboard ("user@example.com — Groo"). Tapping it triggers
   Face ID and fills instantly. This requires the app to keep
   `ASCredentialIdentityStore` populated with one identity per saved URL,
   registered every time the vault is unlocked or changed.
2. **Provider list UI** — When the user taps "Passwords…" (or no suggestion
   matches), the extension UI opens and:
   - unlocks automatically via Face ID (no extra tap),
   - shows a **Suggested** section: credentials whose domain matches the current
     site (exact host or subdomain match — `accounts.google.com` matches a saved
     `google.com`, but `app.com` must NOT match `myapp.com`),
   - shows the **rest of the vault** below, so the user can always pick anything,
   - has an **always-visible search bar** (empty by default) that searches name,
     username and URL across the entire vault,
   - a clear empty state only when the vault has no items at all.
3. **After selection** — the credential fills immediately. If the item has a
   TOTP configured, the current code is copied to the clipboard (Bitwarden
   behavior) so the user can paste it on the next screen.

### 1.2 Passkeys

1. **Registration** — On "Create a passkey", the user picks Groo in the system
   picker. The extension shows a small confirmation card ("Create passkey for
   example.com as user@…"), authenticates with Face ID, generates a P-256
   keypair, returns a `none` attestation to the system, and persists the new
   passkey to the vault. This must work even though the extension cannot talk
   to the Pass server: the item is stored in an encrypted pending queue in the
   App Group and merged + synced by the main app on next unlock/sync.
2. **Assertion (login)** — The passkey appears in QuickType/system sheet
   (requires passkey identities registered). Selecting it opens the extension,
   Face ID runs, the assertion is signed and returned. In the list UI, passkeys
   are shown **only** for passkey-capable requests, filtered by relying party
   and the request's `allowedCredentials`.
3. **Sign counter** — Synced/multi-device credentials must report a constant
   counter of **0** (WebAuthn L3 guidance; what Bitwarden/1Password do).
   Reporting a non-zero, never-persisted counter makes relying parties'
   clone-detection reject the second login.

## 2. Gaps / bugs found

### A. Password autofill broken

| # | Issue | Root cause |
|---|-------|-----------|
| A1 | No QuickType suggestions for most items | `CredentialIdentityService.buildPasswordIdentities` uses `URL(string:)?.host`, which is `nil` for scheme-less URLs like `example.com` — those identities are silently dropped. `SharedPassPasswordItem.domains` already has the correct normalization but the identity builder doesn't use it. |
| A2 | Suggestions missing until first edit/sync | `updateCredentialIdentities` is only called from `saveVault()` and `sync()` — never after `unlock(password:)` or a cache-hit `unlockWithBiometric()` (only via best-effort background sync). |
| A3 | Wrong credentials suggested | `AutoFillService.filteredCredentials` uses bidirectional substring matching (`credDomain.contains(searchDomain) || searchDomain.contains(credDomain)`) — `app.com` matches `myapp.com`. |

### B. Search / list UX broken

| # | Issue | Root cause |
|---|-------|-----------|
| B1 | Opening the extension shows "No Credentials Found" even when matches exist | The search text is pre-filled with the full host (e.g. `accounts.google.com`) and a non-empty search bypasses domain matching entirely, doing a substring search over stored URLs — which usually misses (`accounts.google.com` is not a substring of `google.com`). |
| B2 | Search bar invisible | `.searchable` with default placement is hidden until the user pulls down on the list. |
| B3 | Stale search state | The controller replaces `rootView` with a new view whose `@State searchText` initial value is ignored by SwiftUI (same view identity), so the pre-fill/service identifiers can go stale. |
| B4 | Dead-end empty state | No way to search the whole vault from the empty state. |

### C. Passkeys don't work

| # | Issue | Root cause |
|---|-------|-----------|
| C1 | Creating a passkey does nothing | `prepareInterface(forPasskeyRegistration:)` is not implemented at all. The system opens the extension for registration and nothing handles it. |
| C2 | Passkey login fails on 2nd+ use on strict RPs | Sign count is reported as `signCount + 1` but never persisted — the RP sees the same counter every time and flags a cloned authenticator. Must report 0. |
| C3 | Tapping a passkey sometimes does nothing | `selectPasskey` silently returns when the request isn't a passkey request; passkeys are listed even for password-only requests. |
| C4 | `allowedCredentials` ignored | `filteredPasskeys(for:)` filters by rpId only. |
| C6 | Crash risk | `request.credentialIdentity as! ASPasskeyCredentialIdentity` force cast. |

### D. Polish

| # | Issue |
|---|-------|
| D1 | Misleading unlock error ("Please unlock in the main app" — unlocking in the extension works fine); raw error strings surfaced. |
| D2 | TOTP not copied after autofill (shared model doesn't even decode `totp`). |
| D3 | Odd empty `Section("")` header; plain `key.fill` icons. |

## 3. Fix plan (independent fixes)

1. **Fix QuickType identities (A1 + A2)** — main app.
   Normalize scheme-less URLs in `buildPasswordIdentities` (reuse the
   `https://` prefix trick); call `updateCredentialIdentities` after every
   successful unlock (password, biometric cache hit, biometric server fetch).
2. **Fix domain matching (A3)** — extension.
   Replace substring matching with exact-host-or-subdomain matching:
   `cred == search || search.hasSuffix("." + cred) || cred.hasSuffix("." + search)`.
3. **Redesign list view (B1–B4, C3, D3)** — extension.
   Remove search pre-fill. Suggested section (domain/rpId matches) + "All Items"
   section. Search bar always visible, searches whole vault. Passkeys shown only
   when the request supports passkeys. Monogram icons. Proper empty states.
4. **Passkey assertion correctness (C2, C4, C6)** — extension.
   Report signCount 0; filter by `allowedCredentials` when non-empty; remove
   force cast.
5. **Passkey registration (C1)** — extension + shared + main app.
   - `SharedPasskeyCrypto`: key generation, COSE public key, registration
     authenticator data, minimal CBOR encoder, `none` attestation object.
   - `SharedPendingItemsStore`: AES-GCM-encrypted pending-passkey queue in the
     App Group (encrypted with the vault key the extension already holds).
   - Extension: implement `prepareInterface(forPasskeyRegistration:)` with a
     confirmation screen; on confirm → unlock → generate → complete request →
     enqueue item → register identity in `ASCredentialIdentityStore`.
   - Extension load: merge pending passkeys into the in-memory list so they
     work for assertions immediately.
   - Main app: on unlock/sync, merge pending items into the vault, push to
     server, clear the queue.
6. **TOTP copy on fill (D2)** — extension + shared.
   Decode `totp` in `SharedPassPasswordItem`; add a small shared TOTP generator
   (HMAC SHA1/256/512); on credential selection copy the current code to the
   clipboard with a 1-minute clipboard expiry.
7. **Unlock UX text (D1)** — extension. Accurate copy, clear error on retry.

Non-goals: password saving/creation from the extension UI, favicon fetching,
iOS 18 credential-exchange APIs, conditional passkey registration.

## 4. Verification

- `xcodebuild -project ios/Groo.xcodeproj -scheme Groo -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build` after each fix.
- Manual on-device/simulator pass: QuickType suggestion, provider list on a
  subdomain site, vault-wide search, passkey create + login on webauthn.io.
