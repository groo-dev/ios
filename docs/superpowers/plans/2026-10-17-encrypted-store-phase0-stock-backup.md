# Encrypted store Phase 0 — automatic stock backup

**Spec:** `docs/superpowers/specs/2026-10-17-encrypted-local-store-design.md`, R8.

**Goal:** Stock holdings and transactions stop depending on someone remembering
to tap a button. They back up on their own, and when they cannot, the app says
so instead of going quiet.

**Why first:** this is the only phase whose absence can lose data that exists
nowhere else. Today holdings survive a new phone because the plaintext store
sits in the iCloud backup — precisely what the encrypted store removes. Encrypt
first and a restored backup is an unreadable file.

## Current state

Verified 2026-10-17.

- `StockPortfolioManager.exportJSON()` / the import counterpart already exist.
- `SettingsView.backupStocks()` upserts **one** Pass note named
  `"Stock Portfolio Backup"`, keyed on its name. Idempotent, single item.
- It is gated on `passService.isUnlocked` and is entirely manual.
- `lastBackupDate` is already persisted and shown.
- Holdings and transactions are **not** synced to any server, by design.

## Constraints

- **The vault must be unlocked to write.** Pass holds the backup, so a locked
  vault means no backup. That is not a bug to engineer around — it is a state to
  report.
- **Never block a user action on a backup.** Backing up is background work; a
  failure must never make adding a transaction fail.
- **One Pass note, upserted.** Keep the existing name key. A second item, or a
  per-run item, turns the vault into a log.
- **Must not write when nothing changed.** An unconditional write on every
  background would churn the vault's sync.
- Tests: `scripts/test.sh --unit`, pinned destination
  (`GROO_TEST_DESTINATION`, see `CLAUDE.md`).

## Review focus

1. **Pass locked for a long time.** Backup cannot run. Settings must show the
   real age of the last backup and say changes are unsaved — never show a
   reassuring default.
2. **A backup failing mid-write.** `lastBackupDate` must not advance. A failed
   backup that reports success is worse than no backup.
3. **Rapid edits.** Ten transactions in a row produce one backup, not ten.
4. **First run, no holdings.** No backup note is created, and nothing warns.
5. **Restore over existing data.** Already possible manually; confirm the
   automatic path has not changed its semantics.

## Rulings

- **R0-1 — Dirty flag, not a timer.** A monotonic `stocksChangedAt` is compared
  against `lastBackupDate`. A timer would write unchanged data and would still
  miss a change made seconds before a crash.
- **R0-2 — Triggers: on background, and on vault unlock.** Not on every
  mutation: edits come in bursts, and the background transition is the natural
  commit point. Unlock is the second trigger because that is the moment a
  previously impossible backup becomes possible.
- **R0-3 — Staleness is surfaced, not just recorded.** When there are unbacked
  changes, Settings says so plainly. The failure this guards against is a person
  believing they are covered because nothing told them otherwise.
- **R0-4 — Automatic backup never surfaces an alert.** The manual button keeps
  its alert; the automatic path reports through the Settings row only. An alert
  appearing because the app went to the background would be indefensible.

## File structure

| File | Responsibility |
|---|---|
| `Groo/Features/Stocks/Services/StockBackupCoordinator.swift` (create) | dirty tracking, trigger points, the upsert, last-result state |
| `Groo/Features/Stocks/Services/StockPortfolioManager.swift` (modify) | mark dirty on every mutation |
| `Groo/Views/SettingsView.swift` (modify) | show backup age and unbacked-changes state; manual button delegates to the coordinator |
| `Groo/ContentView.swift` (modify) | drive the background trigger; drive the unlock trigger |
| `GrooTests/Features/Stocks/StockBackupCoordinatorTests.swift` (create) | the behaviour below |

## Tasks

### Task 1 — Dirty tracking

- [ ] `stocksChangedAt` persisted alongside `lastBackupDate`.
- [ ] Every mutation in `StockPortfolioManager` that changes holdings or
      transactions stamps it.
- [ ] `hasUnbackedChanges` is `stocksChangedAt > lastBackupDate`.
- [ ] **Test, armed:** a mutation sets the flag; a successful backup clears it;
      a *failed* backup leaves it set. Mutate the failure path to advance
      `lastBackupDate` anyway and confirm the test reddens.

### Task 2 — The coordinator

- [ ] `backupIfNeeded()`: no-op when nothing changed, when there are no
      holdings, or when the vault is locked — each returning a distinguishable
      reason rather than a bare `false`.
- [ ] Reuses the existing upsert (one note, keyed by name).
- [ ] `lastBackupDate` advances only after the write succeeds.
- [ ] Concurrent calls collapse to one in-flight backup.
- [ ] **Test, armed:** locked vault does not write and does not advance the
      date; ten changes then one call writes once; a throwing vault leaves the
      date untouched.

### Task 3 — Triggers

- [ ] On `scenePhase == .background`, call `backupIfNeeded()`.
- [ ] On Pass vault unlock, call `backupIfNeeded()`.
- [ ] Neither blocks or alerts.
- [ ] **Test:** backgrounding with unbacked changes and an unlocked vault backs
      up; with a locked vault it does not, and the pending state survives.

### Task 4 — Make the gap visible

- [ ] Settings shows the last backup's age.
- [ ] When `hasUnbackedChanges`, it says so, and says the vault must be
      unlocked if that is why.
- [ ] No state renders as reassuring when a backup has never run.
- [ ] **Test:** snapshot the three states — backed up, unbacked changes with
      vault unlocked, unbacked changes with vault locked.

### Task 5 — Verify end to end

- [ ] Add holdings, background, reopen, confirm the Pass note contains them.
- [ ] Delete and reinstall the app, restore from Pass, confirm the portfolio
      returns intact. **This is the property Phase 1 depends on** — do not mark
      the phase done on unit tests alone.
- [ ] Full suite; diff the failing *set* against the baseline in `CLAUDE.md`,
      never the count.

## Done when

Holdings and transactions survive deleting the app, with no manual step, and
the app tells the truth about when it last managed it.
