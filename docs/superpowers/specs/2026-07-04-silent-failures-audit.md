# Silent-Failure Audit & Fix Plan — entire iOS app

Date: 2026-07-04
Method: four parallel audits covering every `.swift` file (136 files; all 164 `try?`,
85 `catch`, 72 `print(` sites classified as a finding or explicitly reviewed-OK).

Patterns hunted: swallowed `try?`, empty/comment-only catches, print-only logging
(invisible in production), generic user-facing errors that discard the cause,
nil/[]/default returns that make "failed" look like "empty", `?? fallback` masking
failed parses, and silent early returns that skip work that matters.

**Systemic finding**: the app has essentially no production logging — ~72 `print`
call sites and no `os.Logger` outside APICache. Nothing that fails in the field
is observable.

---

## Fix 0 — Logging foundation (everything below depends on it)

`Shared/SharedLog.swift`: `Logger` instances under subsystem `dev.groo.ios`
(categories: `pass`, `autofill`, `sync`, `store`, `crypto`, `wallet`, `stocks`,
`push`, `pad`, `scratchpad`, `azan`, `network`, `share`, `widget`). Compiled into
Groo + GrooAutoFill targets; Share/Widget/Keyboard extensions declare their own
`Logger` inline (separate targets). Viewable in Console.app by subsystem.

Rules applied everywhere:
- every formerly-silent catch logs the **actual error**
- user-initiated actions that fail must **surface** the error (alert/toast), using
  `error.localizedDescription`, not a hardcoded generic string
- "failed" must be distinguishable from "empty/not found"
- fallback values are never substituted for money-bearing or security-bearing parses

---

## A. Data-loss / correctness bugs (HIGH) — logic fixes, not just logging

| # | Site | Bug | Fix |
|---|------|-----|-----|
| A1 | `PassModels.swift:316-366` | Item that fails to decode becomes a corrupted stub whose `encode()` writes the placeholder back to the server on the next save — original secret permanently destroyed | Preserve the item's real raw JSON in the corrupted case and re-emit it verbatim on encode |
| A2 | `SharedPendingItemsStore.swift:23-40` | `load()` returns `[]` on decrypt/decode failure; `append()` then overwrites the file — destroys unsynced passkey private keys | `load()` throws, distinguishing not-found from unreadable; `append()` moves an unreadable file aside (`.corrupt`) instead of clobbering; log everything |
| A3 | `LocalStore.swift:37-50` | ANY ModelContainer init error deletes the whole local DB (stocks, prayer logs, offline sync queue) | Back the store file up (rename `.corrupt-<ts>`) instead of deleting; `Logger.fault`; record a "local data was reset" flag surfaced once in UI |
| A4 | `SyncService.swift:92-108` | Queued offline create whose payload fails to decode is deleted as "stale" — user's item never reaches the server | Keep the operation (dead-letter: skip, don't delete), log with op id, surface sync error state |
| A5 | `CryptoService.swift:47` | `SecRandomCopyBytes` status ignored — on failure the KDF salt is all zeros | Check status; `fatalError` on RNG failure (must never continue silently) |
| A6 | `SendView.swift:285,305` | `hexToUInt64 ?? 0` and `gasPrice ?? "0x0"` — malformed RPC values sign a tx with nonce/gas 0 | Strict parsing; abort send with visible error when nonce/gas price/limit unavailable |
| A7 | `EthereumService.swift:182` | Bad hex digit in balance → balance renders as 0 ("funds gone") | Make `hexToEth` throwing; log raw hex |
| A8 | `PortfolioView.swift:407-411` | Token decimals/balance parse failure → wrong magnitude or token silently dropped from portfolio | Skip + set `staleReason` + log instead of silent drop/`?? 18`/`?? 0` |
| A9 | `StockPortfolioManager.swift:29` + `YahooFinanceService.swift:232` | Missing exchange rate silently converts at 1:1 (¥1M shown as $1M) | Exclude unconverted holdings + `staleReason` naming the currency; log rate-fetch failures |
| A10 | `ShareViewController.swift:45-122` | App Group unavailable / encode / write failures discard shared content while reporting success; corrupt queue file gets clobbered | do/catch + log + `cancelRequest(withError:)`; back up undecodable queue file instead of overwriting |
| A11 | `ScratchpadView.swift:530` | Debounced auto-save failure only prints — edits lost, pill shows "Synced" | Error state in the status pill, keep dirty flag so retry happens, log |
| A12 | `ScratchpadTabView.swift:108` | `unlock()` returns false on wrong password but the Bool is discarded — view "unlocks" without a key | `guard try await unlock(...) else { error = "Incorrect password" }` (match PadUnlockView) |
| A13 | `Pass views` (`PassItemListView:204,231,264`, `PassTrashView:63,119,129,138,148`, `PassFolderListView:150,162,169`, `PassItemDetailView:457`) | `try?` on delete / restore / empty-trash / favorite / folder CRUD — destructive user actions silently fail; corrupted-item delete dismisses regardless | do/catch → error alert; only dismiss/clear editing state on success |
| A14 | `CredentialIdentityService.swift:107` | Failure to clear QuickType identities on sign-out only `print`s — credentials remain suggested after sign-out | `Logger.error` + return success Bool so sign-out can retry |
| A15 | `AppDelegate.swift:32` | `try? registerDeviceToken` — push registration failures invisible; push-triggered sync never works | do/catch + `Logger.fault` + `registrationError` state on PushService |
| A16 | `AzanNotificationService.swift:60` | Permission denied → silently removes existing notifications and schedules nothing | Expose `authorizationDenied` state; AzanView shows "Notifications disabled — open Settings" banner |
| A17 | `AzanView.swift:413-430` | Location failure never rendered (`locationService.error` is write-only) | Render the error with manual-location call-to-action |
| A18 | `PadService.swift:141` / `ScratchpadView.swift:415` | Per-item decrypt failures silently drop items from lists | Count failures, log ids, surface "N items couldn't be decrypted" |
| A19 | `PadListView.swift:112` / `HomeView.swift:313,365,380` | `(try? getDecryptedItems()) ?? []` — store/key failure renders as empty vault | do/catch → error state/toast, keep previous items |
| A20 | `FileAttachmentView.swift:117` | `errorMessage` set in catch but never rendered — dead-end download/decrypt failures | Render as alert |
| A21 | `ScratchpadView.swift:397,459,488` | Upload/create/delete failures print-only — user taps, nothing happens | Toast/error state + log |
| A22 | `LocalStore.swift` (23× `try? context.save()`, fetches `?? []`) | All SwiftData saves/fetches infallible-by-assumption; pending-op writes silently lost → offline data loss, replayed ops | Central `save(_:operation:)` helper that logs failures; sync-queue + primary-data writes become throwing and surface at call sites |
| A23 | `SyncService.swift:207-225`, `LocalPadItem:57`, `LocalScratchpad:66` | `(try? encode) ?? "{}"` — item cached with `{}` ciphertext, permanently undecryptable locally | Make inits failable/throwing; never substitute `"{}"` |
| A24 | `WalletManager.swift:254` | `EthereumAddress(to)!` force-unwrap — 42-char non-hex address crashes mid-send | guard → thrown `WalletError.invalidRecipient` |

## B. Observability / misleading-error fixes (MEDIUM)

Grouped by theme; every site gets `Logger` + where user-facing, the real error.

- **print-only catches → Logger(+ UI where user-initiated)**: `CredentialIdentityService:40`, `SyncService:109`, `PushService:152,176` (+ remove PAT-prefix log at :82), `WebSocketService:66,131,207` (+ expose failed state), `GrooApp:45`, `ExtensionHelper (Widget+Keyboard):125,157`, `ScratchpadView:358`, `ScratchpadWebView:52`, `ScratchpadEditorView:24,27`, `AzanNotificationService:30,84` , `AzanAudioService:32,39,52`, `RecitationAudioService:36,54`, `LocationSearchView:72,129`, `StockSearchView:119` (show error, not "No results"), `AzanWidget:109`.
- **Generic message discards cause**: `LoginView:136` (keychain save failure ≠ "Invalid token"), `ScratchpadTabView:110` ("Invalid password" for network errors), `AutoFillCredentialListView:151` (show the AutoFillError text), `AzanLocationService:59` (map CLError), `HomeView:381`, `StockPortfolioManager:124`, `WalletManager:96-196` (log underlying web3swift error).
- **"failed" indistinguishable from "empty/absent"**: `KeychainService.exists:98` (+ `AuthService:79`, `APIClient:49`, `PassService:867`, `WebSocketService:66`) — treat only `errSecItemNotFound` as absent, log other OSStatus; `LocalStore` fetches; `StockPortfolioManager.importJSON:263` (throwing); `ExtensionHelper` decrypt-skips (count + log).
- **Pass unlock/vault**: `PassService:106` (offline ≠ no vault), `:142,205,238,791` (log DecodingError; distinguish schema vs crypto), `:156,816` (log keychain write failures — silent loss of biometric unlock), `:165,254` (vault cache write must log + set lastError — stale AutoFill), `:191` (keychain error ≠ vaultNotSetup), `:216` (background sync failure → lastError), `:765` (merge failure → log + observable pending count), `AutoFillService:64,88` (map itemNotFound → vaultNotSetup; log OSStatus/crypto errors), `CredentialProviderViewController:195` (set error + show list), `PassUnlockView:239` / `PadUnlockView:241` / `GlobalLockView:165,177` (only `LAError.userCancel` stays silent; others set errorMessage).
- **Silent no-op user actions**: `WalletListView:130` (rename via `try?`), `try? unlockWithBiometric` (SendView:68, WalletListView:36, WalletOnboardingView:86), `StockPortfolioManager:200,209` (add/update transaction guard-returns), `AddItemSheet:167,197` (photo/file load → errorMessage), `PadService:289,122,116`, `StockPortfolioManager:81` (unknown tx type coerced to `.buy` — skip + log).
- **Passkey/AutoFill polish**: `CredentialProviderViewController:300` (cancel with `.failed` not `userCanceled`), `:411` (selectPasskey no-op → cancel), `SharedPassModels:197` (`try?` totp → plain try), auto-unlock catches log non-cancel errors.

## C. LOW severity (log-only or accepted)

Log-on-fallback for: `PrayerLog` raw-value coercions, `LocalAzanPreferences:174,184`,
`PrayerTimeService:43,88`, `Config` override parse, `Theme` hex parse
(assertionFailure), `CoinGecko/YahooFinance` retry `try? Task.sleep`
(propagate cancellation), `ReceiveView` QR nil placeholder, `TotpService` "------"
sentinel (align with SharedTotp Optional), `PassItemDetailView:146`
(no example.com link), `PushService:82` token-prefix removal,
`CredentialIdentityService:85` dropped-passkey log, `PassService:275`
sign-out cleanup logs, `AuthService:66` logout deletes log.
Accepted as-is (documented in audit output): formatter fallbacks, delete-if-exists
guards, preview-only prints, deliberate type-inference fallbacks in vault decode.

---

## Implementation loop (build + commit after each)

1. Fix 0: SharedLog + pbxproj registration
2. Shared + GrooAutoFill (A2, A14 ext-side, B autofill items)
3. Pass service/models/views (A1, A13, A14, B pass items)
4. Core: LocalStore/Sync/Crypto/Keychain/Auth/APIClient/WebSocket/Push (A3-A5, A15, A22, A23, B core items)
5. App views: Home/GlobalLock/Login (A19, B items)
6. Pad + Scratchpad (A11, A12, A18, A20, A21, B items)
7. Azan (A16, A17, B items)
8. Crypto + Stocks (A6-A9, A24, B items)
9. ShareExtension + Widget/Keyboard helpers (A10, B items)

Verification: full `xcodebuild` after each step; final pass re-greps for
empty catches and print-only error paths.
