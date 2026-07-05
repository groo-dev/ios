# iOS Test Suite — Phase 7: View Rendering Coverage (80% Overall)

**Date:** 2026-07-06
**Status:** Approved
**Parent spec:** `2026-07-05-ios-test-suite-design.md` (Phases 1–6, complete)
**Goal:** Raise Groo.app line coverage from 36.7% to ≥80% by making the SwiftUI view layer testable via render/snapshot tests, and seaming the remaining system-coupled services. Gain visual-regression protection as a first-class side benefit.

## Context

After Phases 1–6, the logic layer (crypto, vault, sync, wallet, stores) sits at 80–100% coverage, but Groo.app overall is 36.7% because the denominator is dominated by SwiftUI view bodies:

- **66 view files, ~14,100 lines** across 8 feature areas (Azan 3,249, Pass 3,175, Crypto 2,091, Pad 1,574, root Views 1,517, Stocks 1,256, Scratchpad 1,177, Drive 43) — almost all at 0% except the screens the 7 UI tests traverse.
- **~800 lines of system-coupled services** (AzanNotificationService 225, PushService 208, AzanAudioService 140, AzanLocationService 139, RecitationAudioService 92) blocked on UNUserNotificationCenter / CLLocationManager / AVAudioPlayer.
- Unit tests cannot execute view bodies; XCUITest covers them at ~30–60s per journey. Neither reaches 80%.

Reaching 80% requires a third technique: **hosting views in-process during unit tests**. Rendering a SwiftUI view in a `UIHostingController` executes its `body` (and closures reached by the given state), producing coverage at unit-test speed. Adding snapshot assertions on top turns "it rendered" into "it rendered *the same as last time*" — real regression value (this technique would have caught the Phase 5 recovery-phrase-sheet bug class).

## Decisions

| Decision | Choice |
|---|---|
| Rendering technique | `UIHostingController` harness in GrooTests (host app process, simulator) |
| Snapshot assertions | **pointfree `swift-snapshot-testing`** (SPM, test target only) — image snapshots with `perceptualPrecision` tolerance; reference images committed under `GrooTests/__Snapshots__/` |
| Fallback if the library fights us | Render-only harness (host + layout pass + non-nil image via `drawHierarchy`), no new dependency; snapshots added later. Coverage value is identical; only regression value differs |
| Determinism | Pinned simulator (iPhone 17 Pro), pinned appearance (light; one representative dark-mode set), `en_US` locale fixtures, injected clocks/fakes via the existing seams — a snapshot test that isn't byte-stable across two consecutive runs is a defect |
| Fixture wiring | Reuse the Phase 1–6 fakes: `PassServiceIntegrationTests.makeEnv`-style unlocked services, `InMemoryKeychain`, in-memory `LocalStore`, `StubURLProtocol`-backed clients, `UITestMode` stub vault where convenient |
| State coverage | Each view gets 2–4 fixture states chosen to hit real branches: empty / populated / error / locked-unlocked as applicable. YAGNI: no state explosion — one snapshot per meaningful branch |
| View-model extraction | Only where a view body holds real logic a render can't exercise (candidates: ScratchpadView's 137 functions, PassItemFormView validation). Decided per-file during planning recon; behavior-preserving; not a rewrite program |
| System-service seams | Protocol seams (KeychainServicing pattern) over UNUserNotificationCenter, CLLocationManager, AVAudioPlayer for the five services above; `PadService` gains a KDF-iterations parameter (default 600k) so the password-unlock path is testable at 1k iterations |
| Coverage gate | Groo.app overall ≥80%; no per-view minimum (some views are 90% reachable, some 60% — the aggregate is the goal) |
| Runtime budget | The added render/snapshot suite must keep `scripts/test.sh --unit` under ~3 minutes total (renders are fast; budget guards against over-snapshotting) |

## Architecture

### Render harness (`GrooTests/Support/ViewRenderHarness.swift`)

One small helper: hosts any `View` in a `UIHostingController` inside a fixed-size window, forces a layout pass on the main actor, and returns the controller (for render-only tests) or an image (for snapshot tests). All render tests are `@MainActor`. Suites that share `StubURLProtocol` state keep the `NetworkStubbedSuites` umbrella convention; pure-fixture render suites run parallel as usual.

### Snapshot conventions

- `assertSnapshot(of:as:.image(perceptualPrecision: 0.98), named: "<state>")` — tolerance absorbs GPU antialiasing noise while catching layout/content drift.
- Reference images are committed (they are the assertion). A failed snapshot writes a diff artifact; re-recording requires a deliberate `record: .failed` run documented in the README.
- One dark-mode + one large-Dynamic-Type representative set on the highest-traffic screens (Pass list, Home, Azan) rather than a full matrix.

### Fixture states per feature (sizing, refined during planning)

| Feature | Views | Indicative states |
|---|---|---|
| Pass | 11 | locked, unlocked-empty, unlocked-populated (all 7 item types), detail per type, form add/edit, generator, health report |
| Azan | 17 | prayer list (normal/Ramadan), settings, tracker grid (streak/empty), logs, recitations |
| Crypto | 8 | no-wallet onboarding, portfolio (with/without tokens), send/receive, asset detail with chart fixture |
| Stocks | 8 | onboarding, portfolio populated, add-transaction sheet, currency picker, chart fixture |
| Pad / Scratchpad | 13 | locked, list populated, editor with content, toast states |
| Root Views | 8 | login, unlock, global lock, main tabs, customize tabs, sparkline fixture |
| Drive | 1 | placeholder |

### System-service seams (coverage + testability, no behavior change)

- `NotificationScheduling` protocol over `UNUserNotificationCenter` → AzanNotificationService + PushService tests (schedule/clear/authorization-state logic).
- `LocationProviding` over `CLLocationManager` → AzanLocationService (authorization flow, coordinate handoff).
- `AudioPlaying` over `AVAudioPlayer` → AzanAudioService + RecitationAudioService (selection/looping logic; not actual audio).
- `PadService` KDF-iterations parameter → password unlock path tested at 1k iterations, mirroring the vault-test rule.

## Error handling / quality standards

- A render that crashes is a test failure surfacing a real defect (views must tolerate their fixture states).
- Every fixture state must exercise a branch that exists — no duplicate snapshots of identical output.
- Flake policy unchanged: no sleeps; layout waits are synchronous main-actor layout passes; a snapshot differing between two consecutive local runs is a bug to fix, not tolerate.

## Definition of done

1. Groo.app line coverage ≥80% in `scripts/test.sh --unit --coverage`.
2. Full suite green twice consecutively; `--unit` wall-clock under ~3 minutes; UI suite untouched and green.
3. All 6 targets build (Debug and Release).
4. README testing section documents the render/snapshot conventions and re-record procedure.

## Out of scope

- Extension-target UI (widget timelines, keyboard views, share sheet) — not compiled into GrooTests; their logic already lives in Shared/.
- Full appearance matrices (every view × dark × 5 Dynamic Type sizes) — representative set only.
- Interactive gesture flows (remain XCUITest territory).
- CI/device-farm snapshot infrastructure — snapshots are pinned to the local iPhone 17 Pro simulator; revisit if CI arrives.
- Rewriting views to MVVM wholesale — extraction only where render tests can't reach real logic.
