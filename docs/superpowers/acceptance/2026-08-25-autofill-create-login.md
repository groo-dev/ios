# Acceptance — creating a login from the AutoFill sheet

**Date:** 2026-08-25
**Branch:** `feat/autofill-create-login`
**Plan:** `docs/superpowers/plans/2026-08-25-autofill-create-login.md`
**Spec:** `docs/superpowers/specs/2026-08-24-autofill-create-login-design.md`

**A check that was not run is recorded as "not run", never as a pass.**

## Automated — run, results below

| # | Check | Result |
|---|---|---|
| A1 | `xcodebuild clean` then `scripts/test.sh --all` | **PASS (against baseline).** 629 unit tests, up from 584 before this work. Failing set: `afterIshaNextIsTomorrowsFajrAndIshaRunsUntilIt`, `itemDetailCorrupted`, `itemDetailEveryType`, `itemDetailExtraStates`, `padItemRowVariants`, `padListPopulated`, `prayerTimeRowVariants`, `scratchpadListStates`, `settingsViewWithBackupDate`, `stockPriceChartVariants` — 10 unique names, every one in the `CLAUDE.md` baseline. No new name appeared. |
| A2 | Baseline confirmed by measurement, not assumption | **PASS.** All work stashed, suite re-run: same failing set at 584 tests. The only delta was `padListEmpty`/`padListPopulated` swapping, which `CLAUDE.md` documents as flaky. |
| A3 | UI suite (`scripts/test.sh --ui`) | **PASS (against baseline).** 10 tests, one failing: `PassCrudUITests.testLoginItemLifecycleCreateEditDetailTrashRestore` at `:41-42`. Confirmed pre-existing by checking out `main` (`6b467dd`) and running it there — identical failure, identical lines. `CLAUDE.md` was corrected: it had named a different test as the single UI failure. |
| A4 | 45 new tests all pass | **PASS.** Generator 6, draft 12, pending queue 9, publisher 8, matcher 4, drain 3, integration 3. |
| A5 | Existing passkey behaviour unchanged by the queue refactor and the drain rename | **PASS.** `SharedPendingItemsStoreTests` (7) and `syncDrainsPasskeysQueuedByAutoFill` pass untouched — neither was edited. |
| A6 | Drained payload is byte-identical to the pushed record | **PASS.** `theDrainedPayloadMatchesWhatTheExtensionPushed` normalizes both and compares. This is what makes the refreshed drain a no-op instead of a rewrite. |
| A7 | Queue file holds no plaintext password | **PASS.** `theFileOnDiskDoesNotContainThePasswordInClear` scans the raw bytes. |
| A8 | Password queue never touches the passkey queue | **PASS.** `passwordQueueOperationsLeaveThePasskeyQueueByteIdentical` compares the passkey file's bytes before and after. |
| A9 | Embedded extension is fresh after a build | **PASS.** Release `Groo.app/PlugIns/GrooAutoFill.appex/GrooAutoFill` built 03:21, 229 `NewLoginView` and 18 `createPassword` symbols; `ASCredentialProviderExtensionCapabilities` still carries `ProvidesPasswords` and `ProvidesPasskeys`. **Note the trap:** six DerivedData directories exist for this project, and the abandoned ones hold appex binaries from August 8. `find … | head -1` picks one of those. Resolve the *active* directory before drawing any conclusion about staleness — an earlier pass in this session read a stale folder and wrongly concluded the embed step had not re-run. Also remember the build is **Release**, not Debug. |
| A10 | Release build installed to simulator | **PASS.** iPhone 17 Pro, iOS 26.5 (`6BC5BD6C-DE1E-4827-9FDB-9FD07AB742C0`), bundle `dev.groo.ios`, `GrooAutoFill.appex` present in `PlugIns/`. |

## Manual — NOT RUN

Every check below needs a signed-in Groo account and an unlocked vault, which
this session had no credentials for. The device pass additionally needs
physical hardware. **None of these have been executed.**

The simulator at A10 is installed and ready; it needs sign-in, then
Settings → General → AutoFill & Passwords → Groo enabled, and Face ID enrolled
(Features → Face ID → Enrolled).

### Simulator pass — not run

| # | Check | Result |
|---|---|---|
| M1 | `+` appears in the sheet after unlock | not run |
| M2 | New Login prefills site and name; username focused | not run |
| M3 | Generate produces a 20-character password and reveals it | not run |
| M4 | Save fills **both** username and password on the page | not run |
| M5 | Re-opening the sheet lists the new login under "Suggested for &lt;host&gt;" (the pending-merge read path) | not run |
| M6 | Opening the Groo app shows the login in the vault, and no banner appears | not run |

### Offline pass — not run

| # | Check | Result |
|---|---|---|
| M7 | Airplane Mode: save still fills the field, within the 5s deadline | not run |
| M8 | Groo app while still offline shows the banner with a count of 1 | not run |
| M9 | Networking back on, Retry clears the banner and the item appears | not run |

### Device pass — not run

| # | Check | Result |
|---|---|---|
| M10 | Record reached the server (visible in the `pass` web app) | not run |
| M11 | No credential material logged: `log show --predicate 'subsystem == "dev.groo.ios"' --last 30m \| grep -ci <the password used>` returns `0` | not run |

Face ID, the shared keychain and the App Group all behave differently on
hardware, and extension logs are only readable from a device log archive
(`sudo log collect --device-udid <udid>`), so M1-M9 must be repeated there
rather than assumed from the simulator.

## What the automated coverage does and does not establish

Every unit of logic the feature composes is covered: generation, the draft,
the queue, the publisher's payload, the read-time merge, and the app-side
drain including the failure path that must keep both queues.

What no automated test here covers is the **composition inside a live AutoFill
presentation** — that iOS calls the entry point we expect, that
`allowsCreatingPassword` is true there, that `completeRequest` fills both
fields, and that the sheet's own biometric unlock still works with a second
queue in the read path. Extension UI cannot be snapshot-tested from
`GrooTests` (the test bundle hosts the app) and AutoFill cannot be driven from
`GrooUITests`. M1-M11 are the only coverage of that, and they are outstanding.

## Data-security review of the diff

Run 2026-08-25 over `main..feat/autofill-create-login`. Each line below is a
command that was run, not a reading.

| Property | Evidence | Result |
|---|---|---|
| No credential field reaches a log | Every `Log.*` line added by the diff enumerated. They interpolate: the item `id`, a `reason` string, and `String(describing: error)`. No `password`, `username`, `payload` or `privateKey`. | **PASS** |
| Extension never force-refreshes tokens | All three `PassAPIClient(` constructions in `GrooAutoFill/AutoFillService.swift` (`:244`, `:359`, `:425`) carry `forceRefresh: { throw APIError.unauthorized }`. A late refresh would revoke the token family and sign the user out everywhere. | **PASS** |
| The extension cannot modify or destroy an existing record | Its entire server write surface is one call: `api.post(PassAPIClient.Endpoint.records, …)`, in `PasswordPublisher` and `PasskeyPublisher`. No `api.put`, no `api.delete` is reachable from extension code. Combined with a freshly generated `UUID().uuidString.lowercased()` per item, a read-modify-write of somebody else's item is structurally impossible, not merely avoided. | **PASS** |
| A passkey assertion cannot be answered with a password credential | `allowsCreatingPassword` defaults to `false` and is only ever set by `updateServiceIdentifiers`, which the assertion branch (`:236`) and the registration entry point (`:314`) never call — they show `RegisterPasskeyView` or nothing. So the `+` button cannot appear on those paths. | **PASS** |
| Queue file protection matches the existing convention | `SharedPendingQueue.swift:82` and `SharedRecordStore.swift:94` are the only `write(to:)` calls in `Shared/`; both use `options: .atomic` with no explicit `NSFileProtection`. The new queue therefore matches the store that already holds the whole vault. Contents are AES-GCM sealed under the vault key regardless. **Observation, not a finding:** neither sets protection explicitly, so both inherit the App Group default. Changing that is a separate decision affecting existing files. | **PASS (consistent)** |
| Plaintext never lands on disk | `theFileOnDiskDoesNotContainThePasswordInClear` scans the written bytes for the password. | **PASS** |

**One residual risk, stated rather than hidden.** Between the queue write and
the app's next successful drain, a created login exists only in
`pending_passwords.enc` on that device. Uninstalling the app, or losing the
device, loses it. This is the accepted trade of the "save locally, fill, sync
later" decision, and it is the same exposure the passkey queue already carries
for private keys. The banner (Task 9) is what keeps a *persistently* failing
drain visible rather than silent; it does not remove the window.
