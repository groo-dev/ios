# iOS Test Suite — Phase 7: View Rendering/Snapshot Coverage to 80% Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Raise Groo.app line coverage from 36.69% (15,115/41,194) to ≥80% (32,955/41,194) by executing SwiftUI view bodies in-process — a `UIHostingController` render harness plus pointfree `swift-snapshot-testing` image assertions — across all 8 feature areas, and by seaming the five remaining system-coupled services (`UNUserNotificationCenter`, `CLLocationManager`, `AVAudioPlayer`) plus `PadService`'s KDF path. Side benefit: first-class visual-regression protection (committed reference images).

**Architecture:** Three new pieces, everything else is fan-out:

1. **`GrooTests/Support/ViewRenderHarness.swift`** — hosts any `View` in a `UIHostingController` inside a fixed-size `UIWindow` (402×874, the iPhone 17 Pro logical size), forces a synchronous layout pass, and draws the hierarchy to a `UIImage` at scale 1. Wrappers: `assertViewSnapshot(of:named:)` (image assertion via SnapshotTesting), `ViewRender.assertRenders(_:)` (render-only: coverage without a reference image, for time-varying views), and `ViewRender.settledImage(of:yields:)` (lets a synchronous main-actor `.task` finish before drawing — used where a view populates its own `@State` on appear from in-memory data).
2. **`swift-snapshot-testing` (SPM, GrooTests target ONLY)** — wired by a new ruby script following the `scripts/add_test_targets.rb` precedent. References are committed under `GrooTests/**/__Snapshots__/`; the default record mode (`.missing`) gives the two-run workflow: run 1 records + fails, run 2 asserts green.
3. **System-service protocol seams** (Task 7, all default-parameter, zero production behavior change): `NotificationScheduling` over `UNUserNotificationCenter` (AzanNotificationService, PushService), `LocationProviding` over `CLLocationManager` + an injectable geocode closure (AzanLocationService), `AudioPlaying` + `AudioSessionControlling` factories over `AVAudioPlayer`/`AVAudioSession` (AzanAudioService, RecitationAudioService — whose `private init` becomes an internal parameterized init while `static let shared` keeps the defaults), a `kdfIterations` parameter on `PadService` (600_000 default, tests at 1_000), and a `PushTokenProviding` protocol + injected `URLSession` so PushService's registration paths are testable.
4. **Task 8** extracts `ScratchpadView`'s 20+ logic functions (load/save-debounce/CRUD/WebSocket handlers — unreachable by rendering) into a new `ScratchpadStore` (`@Observable`, injectable seams), behavior-preserving, then unit-tests the store directly and snapshots the view states the store makes reachable. Recon showed this extraction is REQUIRED for the 80% gate (see arithmetic below).

**Tech Stack:** Swift Testing (`@Test`/`#expect`/`#require`); `SnapshotTesting` ≥1.17 (`assertSnapshot` works inside `@Test` without XCTest wrappers since 1.16/1.17 — verify against the resolved checkout in Task 1, which is the source of truth); `UIHostingController`/`UIWindow`/`UIGraphicsImageRenderer`; existing Phase 1–6 fakes (`PassServiceIntegrationTests.makeEnv`, `PadServiceTests.makeUnlockedEnv`, `InMemoryKeychain`, `InMemoryLocalStore`, `StubURLProtocol`, `WebSocketFakes`); `scripts/test.sh`; ruby `xcodeproj` gem for the pbxproj edit.

**Spec:** `docs/superpowers/specs/2026-07-06-ios-test-suite-phase7-view-coverage-design.md` (approved). Ledger: `.superpowers/sdd/progress.md`.

## Coverage arithmetic (from `build/coverage/20260706-001247.xcresult` — re-derive against a fresh baseline in Task 1 if numbers drifted)

Groo.app: **15,115/41,194 = 36.69%**. The 80% gate needs **+17,840 newly covered lines**. Where they come from (executable-line pools are exact xccov numbers; "reach" is the honest estimate for multi-state renders — button-action closures, unpresented sheets, and `@State`-gated branches stay uncovered):

| Task | Files (uncovered-line pool) | Pool | Est. reach | Est. delta |
|---|---|---|---|---|
| T1 | SparklineView 70, CustomizeTabsView 65 (DrivePlaceholderView already 100%) | 135 | ~95% | **+130** |
| T2 Pass | PasswordHealthView 840, PassItemDetailView 934, PassFolderListView 457, PassItemFormView 363, PassItemListView 244, PassUnlockView 208, TotpDisplayView 166, PassView 55, PassTrashView 43, PasswordGeneratorView 37, PassItemRow 22 (+ incidental PassService 338→~120, PassModels ~80) | 3,787 | ~69% | **+2,600** |
| T3 Azan | AzanSettingsView 1,277, PrayerGuideDataProvider 1,152, PrayerDetailView 689, AzanView 645, PrayerLogView 552, RakatGroupSectionView 527, ShortSurahsView 430, EssentialRecitationsView 385, PrayerAnalyticsView 317, RakatBreakdownView 311, LocationSearchView 234, PrayerPostureIcon 222, PrayerTimeRow 189, PrayerBreakdownChart 188, WeeklyGridView 131, PrayerGuideModels 101, DailyDuasView 82, ProgressRing 41, TrackerSummaryCard 38, AzanModels 129 | 7,640 | ~77% | **+5,900** |
| T4 Crypto+Stocks | SendView 687, PortfolioView 677, WalletListView 629, AssetDetailView 619, PriceChartView 316, ReceiveView 282, WalletOnboardingView 261, CryptoModels 45; StockPortfolioView 1,080, StockDetailView 917, StockSearchView 525, StockPriceChartView 425, AddTransactionSheet 377, CurrencyPickerView 130, StockPortfolioManager 142, StockModels 30 | 7,142 | ~70% | **+5,000** |
| T5 Pad+Scratchpad | AddItemSheet 798, FileAttachmentView 416, PadUnlockView 305, PadListView 251, ItemRow 107, QuickInputBar 102, PadView 97, ToastView 79; ScratchpadListView 137, ScratchpadWebView 130, ScratchpadTabView 64, ScratchpadEditorView 50, WebViewBridge 34, ScratchpadView (body plumbing only this task) ~190 of 1,277 | 2,760 | ~69% | **+1,900** |
| T6 Root | GlobalLockView 527, HomeView 444 (render-only, ~50%), UnlockView 303, SettingsView 209, LoginView 105, MainTabView 8 | 1,596 | ~63% | **+1,000** |
| T7 Seams | AzanNotificationService 180, PadService 135, PushService 111, AzanAudioService 110, AzanLocationService 87, RecitationAudioService 65 (+ KeychainService plain-item paths ~70 of 103) | 758 | ~82% | **+620** |
| T8 Scratchpad extraction | ScratchpadView remaining logic → ScratchpadStore tested at ~90% + newly snapshot-able view states | ~800 | ~75% | **+600** |
| **Total** | | | | **≈ +17,750 → ≈ 79.8–80.4%** |

This lands **on** the gate with no slack, so: (a) Task 4 and Task 6 end with a **coverage checkpoint** (`--coverage` run, compare cumulative actual vs. the running "expected ≥" line in each task); (b) Task 9 contains a pre-authorized **gap-closing menu** (ordered, concrete) to execute until ≥80% if the estimates ran short. Do NOT silently skip the checkpoints.

## Spec-coverage notes (read before implementing)

- **Snapshot vs. render-only is decided per view by determinism, not effort.** A snapshot is byte-unstable (and therefore FORBIDDEN — the spec calls an unstable snapshot a defect) wherever the pixels depend on wall-clock now: live countdowns (`AzanView` next-prayer card, `HomeView` prayer strip, `TotpDisplayView` code/ring), month grids built from `Date()` (`PrayerLogView`), indeterminate `ProgressView` spinners (any loading state), or live WKWebView paints. Those views get **render-only** tests (`ViewRender.assertRenders`) — identical coverage value, no regression image. Each task lists the classification per view.
- **Exclusions (not rendered at all), with reasons:**
  - `CameraPicker` (in `AddItemSheet.swift`) — `UIImagePickerController` with `.camera` source throws on simulator; only reachable via user action. Excluded.
  - `ScratchpadWebView`'s loaded-editor behavior (`.ready` → `setContent` round-trip) — needs the JS editor running; `makeUIView` + `Coordinator` message handling ARE covered (render-only + a `WKScriptMessage` subclass driving the Coordinator directly), but the live JS bridge remains XCUITest/manual territory.
  - `LocationSearchView` live-search results — `MKLocalSearchCompleter` results require network + Apple services; the empty state renders/snapshots fine and `selectResult` stays uncovered.
  - `ContentView` service-initialization branches — needs the full auth environment; only the logged-out branch is a T9 gap-closing lever.
  - Biometric keychain paths (`saveBiometricProtected` on device without enrolled biometry), OAuth browser flow, extension-target UI — unchanged from the Phase 1–6 deliberate list.
- **Dark-mode + Dynamic Type representative set (approved deviation):** the spec names "Pass list, Home, Azan" as the highest-traffic dark/a11y set, but Home and the Azan prayer list are countdown-bearing (render-only). The deterministic substitutes are **PassItemListView (T2), PrayerDetailView (T3), StockPortfolioView (T4)** — each gets one `.dark` and one `.accessibility2` Dynamic Type snapshot. Flag in the final report.
- **`RecitationAudioService` seam shape:** the spec's KeychainServicing pattern maps to: keep `static let shared = RecitationAudioService()`, change `private init()` to an internal `init(makePlayer:audioSession:)` with production defaults. The singleton stays; tests build private instances. Views already take it as a `let` parameter, so fixtures pass `.shared` (render never plays audio — playback is tap-gated).
- **`AzanNotificationService.scheduleNotifications` tests assert invariants, not counts** — the service compares against the real `Date()` internally, so tests assert "every added request has an `azan_` id and a future trigger; pendingCount == adds; denied auth schedules nothing and wipes nothing" rather than exact schedules. Suhoor branch is only assertable during Ramadan — left uncovered (documented), Jumu'ah branch is deterministic (there is always a future Friday).
- **`AzanLocationService.requestLocation`'s notDetermined path sleeps 1s** (production `Task.sleep`) — tests avoid that branch (fake starts `.authorizedWhenInUse`/`.denied`); the 3-line branch stays uncovered rather than violating the no-sleeps rule.
- **`PortfolioView`/`StockSearchView`/`AddItemSheet` reach ~45–55% only** — their interesting states live behind `@State` mutated by user input or async network results landing post-snapshot. Documented; the aggregate gate absorbs it.
- **Snapshot PNGs land inside the synchronized `GrooTests/` folder** and therefore become test-bundle resources — harmless, and it keeps references next to their suites (`__Snapshots__/<TestFile>/<test>.<name>.png`). Scale-1 images keep the repo delta ~5–10MB total.
- **`LocalStore.shared` and `UserDefaults.standard` are process-global** — every suite that renders a view reading them (`@AppStorage`, Azan preferences, Config base URLs) pins the keys via `withPinnedDefaults`/`withFixedAzanLocation` helpers and restores them, and sits under the `NetworkStubbedSuites` serialized umbrella. Pure-fixture suites stay parallel.

## Global Constraints

- Working directory: `/Users/groo/work/gr/ios`, branch `ios-test-suite-phase7` off `main`. Runner: `bash scripts/test.sh --unit` / `--ui` → `** TEST SUCCEEDED **`.
- **Baseline: 316 unit tests in 39 suites + 7 UI tests, all green; Groo.app coverage 36.69%.** Running totals (xcodebuild counts `@Test` declarations; if a count differs, find out why before committing):
  - After Task 1: **320 unit** (+4 pilot)
  - After Task 2: **335 unit** (+15 Pass)
  - After Task 3: **354 unit** (+19 Azan)
  - After Task 4: **370 unit** (+16 Crypto+Stocks) — coverage checkpoint ≥ ~68%
  - After Task 5: **391 unit** (+21 Pad+Scratchpad)
  - After Task 6: **397 unit** (+6 root) — coverage checkpoint ≥ ~74%
  - After Task 7: **441 unit** (+44 seams incl. keychain roundtrips)
  - After Task 8: **454 unit** (+13 extraction)
  - Task 9: gate ≥80%, suite ×2, runtime, builds, README, summary
- **THE SNAPSHOT TWO-RUN REALITY (every task):** with record mode `.missing` (the library default), the FIRST `--unit` run after adding snapshot tests FAILS those tests with "No reference was found on disk. Automatically recorded snapshot: …" while writing the PNGs; the SECOND run must be fully green; run a THIRD time to prove byte-stability (the spec's determinism rule). Only then `git add` the new `__Snapshots__/` directories WITH the test files — reference images are the assertion and are committed in the same commit.
- **Determinism rules (restated from spec):** pinned simulator (iPhone 17 Pro), light appearance default (dark only in the representative set), `en_US` locale forced by the harness, animations disabled by the harness, scale-1 rendering, fixed epoch fixtures (`1_700_000_000`-style, never `Date()`), no snapshots of countdown/spinner/relative-"now" content, injected clocks/fakes via existing seams. A snapshot differing between two consecutive local runs is a bug to fix (usually: un-pinned defaults, live time, or a spinner) — never re-record around it.
- Re-record procedure (documented in README, Task 1): `TEST_RUNNER_SNAPSHOT_TESTING_RECORD=all bash scripts/test.sh --unit` (xcodebuild forwards `TEST_RUNNER_`-prefixed vars to the test process; SnapshotTesting reads `SNAPSHOT_TESTING_RECORD` — VERIFY both names against the resolved package source in Task 1; fallback is temporarily flipping the suite trait to `.snapshots(record: .all)`).
- **No sleeps, no timing assertions.** `ViewRender.settledImage`'s `Task.yield()` loop is cooperative scheduling, not time; `ScratchpadStore` tests run the debounce at `Duration.zero` and `await saveTask?.value`.
- Suites that touch `StubURLProtocol`, `UserDefaults.standard`, or `LocalStore.shared` go under `extension NetworkStubbedSuites { @Suite(.serialized) … }`. Pure-fixture render suites are top-level and parallel (all render tests are `@MainActor`, so they serialize on the main actor anyway).
- Production edits are confined to Tasks 7–8 (+ two pre-authorized T9 visibility levers) and are behavior-preserving: protocol seams with production defaults, `PadService.kdfIterations` default 600_000, the `ScratchpadStore` extraction (same logic, same call ordering), `private` → internal on two sheet subviews if the gate needs them. **The pbxproj is touched exactly once (Task 1, by script).**
- Tests are coverage over recon'd contracts: if a render crashes or an assertion fails against production, **STOP and report** — a crashing render is a real defect per spec, not a fixture to shim. (Exception: Task 7/8 TDD steps are expected red before their production edit.)
- Before each commit: `bash scripts/test.sh --unit` green (snapshot suites green on the SECOND-and-third runs per the two-run reality); Tasks 1, 7, 8 additionally build the app (`xcodebuild build -project Groo.xcodeproj -scheme Groo -destination 'platform=iOS Simulator,name=iPhone 17 Pro'` — compiles all 6 targets); Task 9 runs `--ui`, Release build, and the full gate.

---

### Task 1: swift-snapshot-testing dependency + ViewRenderHarness + pilot suite (record→assert workflow proven end-to-end)

**Files:**
- Create: `scripts/add_snapshot_package.rb`
- Modify: `Groo.xcodeproj/project.pbxproj` (BY SCRIPT ONLY)
- Create: `GrooTests/Support/ViewRenderHarness.swift`
- Create: `GrooTests/Views/RootPilotSnapshotTests.swift`
- Create (by test run): `GrooTests/Views/__Snapshots__/RootPilotSnapshotTests/*.png`
- Modify: `README.md` (snapshot conventions + re-record procedure)

**Interfaces:**
- Consumes: `scripts/add_test_targets.rb` + `scripts/register_shared_file.rb` ruby/xcodeproj precedent; pbxproj structure — `packageReferences` on the PBXProject (`1B28509F…`), `XCRemoteSwiftPackageReference`/`XCSwiftPackageProductDependency` sections, GrooTests native target `20144DA48A1997E29F2CE31F` (no `packageProductDependencies` today), Frameworks-phase `PBXBuildFile` entries with `productRef` (the existing web3swift/Adhan/GrooAuth pattern).
- Produces: `SnapshotTesting` importable from GrooTests ONLY; `ViewRender.image/settledImage/assertRenders`, `assertViewSnapshot(of:named:)`, `withPinnedDefaults`; four pilot tests with committed references.

- [ ] **Step 1: The wiring script**

Create `scripts/add_snapshot_package.rb`:

```ruby
#!/usr/bin/env ruby
# Adds pointfree swift-snapshot-testing as a remote SPM package and wires the
# SnapshotTesting product into the GrooTests target ONLY (packageReferences on
# the project + XCSwiftPackageProductDependency + Frameworks-phase build file,
# mirroring how web3swift/Adhan/GrooAuth are wired). Idempotent.
require 'xcodeproj'

project_path = File.expand_path('../Groo.xcodeproj', __dir__)
project = Xcodeproj::Project.open(project_path)

test_target = project.targets.find { |t| t.name == 'GrooTests' }
abort 'ERROR: GrooTests target not found' unless test_target

if test_target.package_product_dependencies.any? { |d| d.product_name == 'SnapshotTesting' }
  abort 'SnapshotTesting already wired into GrooTests — nothing to do'
end

pkg = project.root_object.package_references.find do |ref|
  ref.respond_to?(:repositoryURL) && ref.repositoryURL.to_s.include?('swift-snapshot-testing')
end
unless pkg
  pkg = project.new(Xcodeproj::Project::Object::XCRemoteSwiftPackageReference)
  pkg.repositoryURL = 'https://github.com/pointfreeco/swift-snapshot-testing'
  pkg.requirement = { 'kind' => 'upToNextMajorVersion', 'minimumVersion' => '1.17.0' }
  project.root_object.package_references << pkg
end

dep = project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
dep.package = pkg
dep.product_name = 'SnapshotTesting'
test_target.package_product_dependencies << dep

build_file = project.new(Xcodeproj::Project::Object::PBXBuildFile)
build_file.product_ref = dep
test_target.frameworks_build_phase.files << build_file

project.save
puts 'OK: SnapshotTesting (swift-snapshot-testing >= 1.17.0) wired into GrooTests'
```

Run: `ruby scripts/add_snapshot_package.rb`
Expected: `OK: SnapshotTesting … wired into GrooTests`. (If the xcodeproj gem is missing: `gem install xcodeproj --user-install` — same setup the Phase 5 scripts needed.)

- [ ] **Step 2: pbxproj verification greps (all four must hold)**

```bash
grep -c 'swift-snapshot-testing' Groo.xcodeproj/project.pbxproj
# expected: 2+ (XCRemoteSwiftPackageReference decl + section comment)
grep -n 'SnapshotTesting' Groo.xcodeproj/project.pbxproj
# expected: a "SnapshotTesting in Frameworks" PBXBuildFile, an XCSwiftPackageProductDependency
# with productName = SnapshotTesting, and ONE packageProductDependencies entry
sed -n '/20144DA48A1997E29F2CE31F \/\* GrooTests \*\//,/productType/p' Groo.xcodeproj/project.pbxproj | grep -c 'SnapshotTesting'
# expected: 1 (the GrooTests target owns the product dependency)
sed -n '/1B2850A62F13FF540046247D \/\* Groo \*\/ = {/,/productType = "com.apple.product-type.application"/p' Groo.xcodeproj/project.pbxproj | grep -c 'SnapshotTesting' || true
# expected: 0 (the app target must NOT link it)
```

- [ ] **Step 3: Resolve + verify the library's Swift Testing integration against the checkout (source of truth)**

```bash
xcodebuild -resolvePackageDependencies -project Groo.xcodeproj -scheme Groo 2>&1 | tail -3
CHECKOUT=$(ls -d ~/Library/Developer/Xcode/DerivedData/Groo-*/SourcePackages/checkouts/swift-snapshot-testing | head -1)
grep -rn "import Testing" "$CHECKOUT/Sources/SnapshotTesting" | head -5
grep -rn "SNAPSHOT_TESTING_RECORD" "$CHECKOUT/Sources" | head -5
grep -rln "func snapshots(" "$CHECKOUT/Sources/SnapshotTesting"
```

Confirm three things and adapt the harness if names differ (this is the ONLY file that would change):
1. `assertSnapshot` reports through Swift Testing when running inside `@Test` (look for `Issue.record`/`Test.current` in `AssertSnapshot.swift` or `RecordIssue.swift`) — i.e. **no XCTest wrapper is needed**.
2. The suite trait `.snapshots(record:diffTool:)` exists (`SnapshotsTestTrait.swift` or similar) — used on every snapshot suite below for an explicit record mode.
3. The record-override env var name (expected `SNAPSHOT_TESTING_RECORD`, values `all`/`failed`/`missing`/`never`) for the README re-record procedure.

If (1) is absent in the resolved version (it should not be at ≥1.17), STOP and report — the spec's fallback (render-only harness, no dependency) needs an adjudicated decision, not an improvised wrapper.

- [ ] **Step 4: Create `GrooTests/Support/ViewRenderHarness.swift`**

```swift
//
//  ViewRenderHarness.swift
//  GrooTests
//
//  Phase 7 render/snapshot harness. Hosts any SwiftUI view in a
//  UIHostingController inside a fixed-size key window (iPhone 17 Pro logical
//  size), forces a synchronous main-actor layout pass, and draws the
//  hierarchy to a UIImage at scale 1. Determinism: en_US locale forced,
//  animations disabled, light appearance unless a test opts into dark.
//  Snapshot wrapper uses perceptualPrecision 0.98 (absorbs GPU antialiasing
//  noise, catches layout/content drift). Views whose pixels depend on
//  wall-clock now (countdowns, TOTP codes, spinners) use assertRenders —
//  same coverage, no reference image.
//

import SnapshotTesting
import SwiftUI
import Testing
import UIKit

@MainActor
enum ViewRender {
    /// iPhone 17 Pro logical size — the pinned simulator.
    static let deviceSize = CGSize(width: 402, height: 874)

    static func makeWindow(
        hosting view: some View,
        size: CGSize = deviceSize,
        appearance: UIUserInterfaceStyle = .light
    ) -> UIWindow {
        UIView.setAnimationsEnabled(false)
        let host = UIHostingController(rootView: AnyView(
            view
                .environment(\.locale, Locale(identifier: "en_US"))
                .transaction { $0.disablesAnimations = true }
        ))
        let window = UIWindow(frame: CGRect(origin: .zero, size: size))
        window.overrideUserInterfaceStyle = appearance
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.frame = window.bounds
        window.layoutIfNeeded()
        return window
    }

    static func draw(_ window: UIWindow) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1   // committed references stay small; layout drift is still pixel-visible
        let image = UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        window.isHidden = true
        window.rootViewController = nil
        return image
    }

    /// Host + layout + draw in one main-actor turn (async .task bodies have
    /// NOT run yet — the image shows the view's initial state).
    static func image(
        of view: some View,
        size: CGSize = deviceSize,
        appearance: UIUserInterfaceStyle = .light
    ) -> UIImage {
        draw(makeWindow(hosting: view, size: size, appearance: appearance))
    }

    /// Like image(of:), but yields the main actor a few times first so a
    /// synchronous-on-main .task / onAppear state population (in-memory work
    /// only — NEVER network) completes before drawing. Cooperative
    /// scheduling, not time: no sleeps.
    static func settledImage(
        of view: some View,
        yields: Int = 8,
        size: CGSize = deviceSize,
        appearance: UIUserInterfaceStyle = .light
    ) async -> UIImage {
        let window = makeWindow(hosting: view, size: size, appearance: appearance)
        for _ in 0..<yields { await Task.yield() }
        window.layoutIfNeeded()
        return draw(window)
    }

    /// Render-only assertion: hosting + layout + draw must not crash and must
    /// produce a non-empty bitmap. Used for views whose pixels are
    /// time-varying (a snapshot would be byte-unstable — a spec defect).
    static func assertRenders(
        _ view: some View,
        size: CGSize = deviceSize,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        let image = image(of: view, size: size)
        #expect(image.size.width > 0 && image.size.height > 0,
                "view produced an empty render", sourceLocation: sourceLocation)
    }

    /// Async twin of assertRenders for settled renders.
    static func assertSettledRenders(
        _ view: some View,
        yields: Int = 8,
        size: CGSize = deviceSize,
        sourceLocation: SourceLocation = #_sourceLocation
    ) async {
        let image = await settledImage(of: view, yields: yields, size: size)
        #expect(image.size.width > 0 && image.size.height > 0,
                "view produced an empty render", sourceLocation: sourceLocation)
    }
}

/// Snapshot a view at device size. named: distinguishes fixture states
/// within one test ("locked", "populated", "dark", …).
@MainActor
func assertViewSnapshot(
    of view: some View,
    named name: String,
    size: CGSize = ViewRender.deviceSize,
    appearance: UIUserInterfaceStyle = .light,
    fileID: StaticString = #fileID,
    filePath: StaticString = #filePath,
    testName: String = #function,
    line: UInt = #line,
    column: UInt = #column
) {
    assertSnapshot(
        of: ViewRender.image(of: view, size: size, appearance: appearance),
        as: .image(perceptualPrecision: 0.98),
        named: name,
        fileID: fileID,
        file: filePath,
        testName: testName,
        line: line,
        column: column
    )
}

/// Settled variant (see ViewRender.settledImage).
@MainActor
func assertSettledViewSnapshot(
    of view: some View,
    named name: String,
    yields: Int = 8,
    size: CGSize = ViewRender.deviceSize,
    appearance: UIUserInterfaceStyle = .light,
    fileID: StaticString = #fileID,
    filePath: StaticString = #filePath,
    testName: String = #function,
    line: UInt = #line,
    column: UInt = #column
) async {
    assertSnapshot(
        of: await ViewRender.settledImage(of: view, yields: yields, size: size, appearance: appearance),
        as: .image(perceptualPrecision: 0.98),
        named: name,
        fileID: fileID,
        file: filePath,
        testName: testName,
        line: line,
        column: column
    )
}

/// Pin UserDefaults.standard keys for the duration of body, restoring the
/// previous values (or absence) afterwards. Callers MUST sit under the
/// NetworkStubbedSuites serialized umbrella (standard defaults are
/// process-global shared state).
@MainActor
func withPinnedDefaults<T>(_ values: [String: Any], _ body: () throws -> T) rethrows -> T {
    let defaults = UserDefaults.standard
    var previous: [String: Any?] = [:]
    for (key, value) in values {
        previous[key] = defaults.object(forKey: key)
        defaults.set(value, forKey: key)
    }
    defer {
        for (key, old) in previous {
            if let old { defaults.set(old, forKey: key) } else { defaults.removeObject(forKey: key) }
        }
    }
    return try body()
}

/// Async twin for bodies that await (settled snapshots).
@MainActor
func withPinnedDefaults<T>(_ values: [String: Any], _ body: () async throws -> T) async rethrows -> T {
    let defaults = UserDefaults.standard
    var previous: [String: Any?] = [:]
    for (key, value) in values {
        previous[key] = defaults.object(forKey: key)
        defaults.set(value, forKey: key)
    }
    defer {
        for (key, old) in previous {
            if let old { defaults.set(old, forKey: key) } else { defaults.removeObject(forKey: key) }
        }
    }
    return try await body()
}
```

If the resolved `assertSnapshot` signature differs (`file:` label vs `filePath:` — it changed across 1.x), fix the pass-through labels HERE and nowhere else; every suite goes through these wrappers.

- [ ] **Step 5: Pilot suite `GrooTests/Views/RootPilotSnapshotTests.swift`** (create the `GrooTests/Views/` directory — synchronized folder, compiles automatically)

```swift
//
//  RootPilotSnapshotTests.swift
//  GrooTests
//
//  Phase 7 pilot: proves the record→assert snapshot workflow end-to-end on
//  the three dependency-free views (Drive placeholder + two root views)
//  before the per-feature fan-out. Pure fixtures — no umbrella needed.
//

import SnapshotTesting
import SwiftUI
import Testing
@testable import Groo

@MainActor
@Suite(.snapshots(record: .missing))
struct RootPilotSnapshotTests {
    @Test func drivePlaceholder() {
        assertViewSnapshot(of: DrivePlaceholderView(), named: "default")
    }

    @Test func drivePlaceholderDark() {
        assertViewSnapshot(of: DrivePlaceholderView(), named: "dark", appearance: .dark)
    }

    @Test func sparklineVariants() {
        let up: [Double] = [1, 2, 1.5, 3, 2.5, 4]
        let down: [Double] = [4, 3.5, 3, 2, 2.5, 1]
        assertViewSnapshot(
            of: SparklineView(data: up, color: .green).frame(width: 120, height: 40).padding(),
            named: "up", size: CGSize(width: 160, height: 80))
        assertViewSnapshot(
            of: SparklineView(data: down, color: .red).frame(width: 120, height: 40).padding(),
            named: "down", size: CGSize(width: 160, height: 80))
        assertViewSnapshot(
            of: SparklineView(data: [], color: .green).frame(width: 120, height: 40).padding(),
            named: "empty", size: CGSize(width: 160, height: 80))
    }

    @Test func customizeTabs() {
        assertViewSnapshot(of: NavigationStack { CustomizeTabsView() }, named: "default")
    }
}
```

- [ ] **Step 6: The two-run record→assert cycle (this IS the pilot's point)**

Run: `bash scripts/test.sh --unit 2>&1 | tail -20`
Expected: **FAIL** — exactly the 4 new pilot tests fail with "No reference was found on disk. Automatically recorded snapshot: …"; all 316 pre-existing tests stay green. Confirm the PNGs exist:
`ls GrooTests/Views/__Snapshots__/RootPilotSnapshotTests/` → 6 PNGs (`drivePlaceholder.default.png`, `drivePlaceholderDark.dark.png`, `sparklineVariants.up/down/empty.png`, `customizeTabs.default.png`). Open one (`open GrooTests/Views/__Snapshots__/RootPilotSnapshotTests/drivePlaceholder.default.png`) and eyeball it — a blank/black image means the harness draw is broken: STOP and fix (likely `afterScreenUpdates`/window-keying) before any fan-out.

Run: `bash scripts/test.sh --unit 2>&1 | tail -5`
Expected: PASS — **320 tests**.

Run: `bash scripts/test.sh --unit 2>&1 | tail -5` (third run — byte-stability)
Expected: PASS again. Any flake here is a harness determinism bug; fix now, not in Task 2.

Also verify the re-record path once (it is the README promise):
`TEST_RUNNER_SNAPSHOT_TESTING_RECORD=all bash scripts/test.sh --unit 2>/dev/null; git status --short GrooTests/Views` — if the env var round-trips, the PNGs are rewritten byte-identical (`git status` clean or whitespace-identical). If the env var does NOT reach the tests, document the trait-flip fallback in the README instead and note it in the task report.

- [ ] **Step 7: README**

In `README.md`'s Testing section, append:

```markdown
- View render/snapshot tests (Phase 7): views are hosted in-process via `GrooTests/Support/ViewRenderHarness.swift` and snapshot-asserted with pointfree swift-snapshot-testing (`assertViewSnapshot(of:named:)`, perceptualPrecision 0.98, scale 1, en_US, light appearance, iPhone 17 Pro). Reference images are committed under `GrooTests/**/__Snapshots__/` — they are the assertion. First run after adding a snapshot test records the reference and fails ("No reference was found on disk"); the second run asserts. Views with time-varying pixels (countdowns, TOTP, spinners) use render-only assertions (`ViewRender.assertRenders`) — never snapshot wall-clock content.
- Re-recording after an intentional UI change: `TEST_RUNNER_SNAPSHOT_TESTING_RECORD=all bash scripts/test.sh --unit`, then review the PNG diffs in git and commit them with the change. `=failed` re-records only failing ones. Snapshots are pinned to the local iPhone 17 Pro simulator.
```

- [ ] **Step 8: Build + commit**

Run: `xcodebuild build -project Groo.xcodeproj -scheme Groo -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -3` → `** BUILD SUCCEEDED **` (all 6 targets; the app target must not have grown a SnapshotTesting link).

```bash
git add scripts/add_snapshot_package.rb Groo.xcodeproj/project.pbxproj GrooTests/Support/ViewRenderHarness.swift GrooTests/Views README.md
git commit -m "test: swift-snapshot-testing (GrooTests-only) + ViewRenderHarness + pilot snapshot suite"
```

---

### Task 2: Pass feature fan-out (11 views; expected delta ≈ +2,600 covered lines)

**Files:**
- Create: `GrooTests/Features/Pass/PassViewSnapshotTests.swift`
- Create (by test run): `GrooTests/Features/Pass/__Snapshots__/PassViewSnapshotTests/*.png`

**Interfaces:**
- Consumes (all recon-verified): `PassServiceIntegrationTests.makeEnv(items:folders:vaultVersion:)` + `.password` (static `"test-master-password"`); `VaultItemFixtures.allItemJSONs`; view inits — `PassView(passService:onSignOut:)`, `PassUnlockView(passService:onUnlock:onSignOut:)`, `PassItemListView(passService:onSelectItem:onAddItem:onEditItem:)`, `PassItemDetailView(item:passService:onDismiss:)`, `PassItemFormView(passService:editingItem:defaultType:onSave:onCancel:)`, `PassItemRow(item:onTap:onCopyPassword:)`, `PassFolderListView(passService:onDismiss:onSelectFolder:)`, `PassTrashView(passService:onDismiss:)`, `PasswordGeneratorView(onPasswordGenerated:)`, `PasswordHealthView(passService:onDismiss:onSelectItem:)`, `TotpDisplayView(config:onCopy:)`; model memberwise inits per `PassModels.swift` (`PassPasswordItem(id:type:name:username:password:urls:notes:totp:folderId:favorite:createdAt:updatedAt:deletedAt:)`, `PassFolder(id:name:parentId:)`, `PassCorruptedItem(id:rawJson:error:raw:)`, `PassTotpConfig(secret:algorithm:digits:period:)`).
- Classification: snapshots everywhere EXCEPT `PasswordGeneratorView` (random password on appear) and `TotpDisplayView` / totp-bearing detail (live code + countdown ring) — those are render-only.
- Simulator precondition (whole phase): Face ID must NOT be enrolled in the pinned simulator (`xcrun simctl spawn booted notifyutil` not needed — just check Features ▸ Face ID; `LAContext` then reports `.none` deterministically, which the unlock-view snapshots encode).

- [ ] **Step 1: Create `GrooTests/Features/Pass/PassViewSnapshotTests.swift`**

```swift
//
//  PassViewSnapshotTests.swift
//  GrooTests
//
//  Phase 7: render/snapshot coverage for all 11 Pass views over the
//  Phase 1 fake vault (makeEnv). Fixed-epoch fixtures; the canonical
//  decoded items carry fixed timestamps. Generator and TOTP surfaces are
//  render-only (random/live content).
//

import SnapshotTesting
import SwiftUI
import Testing
@testable import Groo

extension NetworkStubbedSuites {

@MainActor
@Suite(.serialized, .snapshots(record: .missing))
struct PassViewSnapshotTests {
    static let fixedMs = 1_700_000_000_000

    static func allItems() throws -> [PassVaultItem] {
        try VaultItemFixtures.allItemJSONs.map {
            try JSONDecoder().decode(PassVaultItem.self, from: Data($0.utf8))
        }
    }

    static func snapPassword(
        id: String = "pw-snap", name: String = "Example Login",
        password: String = "hunter2-secret", totp: PassTotpConfig? = nil,
        folderId: String? = nil, updatedAt: Int = fixedMs, deletedAt: Int? = nil
    ) -> PassVaultItem {
        .password(PassPasswordItem(
            id: id, type: .password, name: name, username: "user@example.com",
            password: password, urls: ["https://example.com/login"], notes: "Work account",
            totp: totp, folderId: folderId, favorite: true,
            createdAt: fixedMs, updatedAt: updatedAt, deletedAt: deletedAt))
    }

    static func makeUnlockedEnv(
        items: [PassVaultItem], folders: [PassFolder] = []
    ) async throws -> PassServiceIntegrationTests.Env {
        let env = try PassServiceIntegrationTests.makeEnv(items: items, folders: folders)
        _ = try await env.service.unlock(password: PassServiceIntegrationTests.password)
        return env
    }

    static func cleanUp(_ env: PassServiceIntegrationTests.Env) {
        try? FileManager.default.removeItem(at: env.tempDir)
    }

    // MARK: - Unlock / shell

    @Test func unlockViewLocked() throws {
        let env = try PassServiceIntegrationTests.makeEnv(items: [])
        defer { Self.cleanUp(env) }
        assertViewSnapshot(
            of: PassUnlockView(passService: env.service, onUnlock: {}, onSignOut: {}),
            named: "locked")
    }

    @Test func passViewLockedShell() throws {
        let env = try PassServiceIntegrationTests.makeEnv(items: [])
        defer { Self.cleanUp(env) }
        // .task fires checkVaultSetup against the stubbed key-info GET
        // (last-response-repeats); the async result lands post-draw.
        assertViewSnapshot(
            of: PassView(passService: env.service, onSignOut: {}),
            named: "locked")
    }

    // MARK: - Item list (dark + Dynamic Type representative set lives here)

    @Test func itemListPopulated() async throws {
        let env = try await Self.makeUnlockedEnv(items: Self.allItems())
        defer { Self.cleanUp(env) }
        let view = NavigationStack {
            PassItemListView(passService: env.service, onSelectItem: { _ in },
                             onAddItem: {}, onEditItem: { _ in })
        }
        assertViewSnapshot(of: view, named: "populated")
    }

    @Test func itemListRepresentativeSet() async throws {
        let env = try await Self.makeUnlockedEnv(items: Self.allItems())
        defer { Self.cleanUp(env) }
        let view = NavigationStack {
            PassItemListView(passService: env.service, onSelectItem: { _ in },
                             onAddItem: {}, onEditItem: { _ in })
        }
        assertViewSnapshot(of: view, named: "dark", appearance: .dark)
        assertViewSnapshot(
            of: view.environment(\.dynamicTypeSize, .accessibility2), named: "a11y-xl")
    }

    @Test func itemListEmpty() async throws {
        let env = try await Self.makeUnlockedEnv(items: [])
        defer { Self.cleanUp(env) }
        assertViewSnapshot(
            of: NavigationStack {
                PassItemListView(passService: env.service, onSelectItem: { _ in },
                                 onAddItem: {}, onEditItem: { _ in })
            },
            named: "empty")
    }

    // MARK: - Detail (every type; totp-bearing password is render-only)

    @Test func itemDetailEveryType() async throws {
        let items = try Self.allItems()
        let env = try await Self.makeUnlockedEnv(items: items)
        defer { Self.cleanUp(env) }

        // The canonical password fixture carries a TOTP config → live code →
        // render-only. Snapshot the password type via a no-totp twin instead.
        for item in items {
            let view = NavigationStack {
                PassItemDetailView(item: item, passService: env.service, onDismiss: {})
            }
            if case .password(let pwd) = item, pwd.totp != nil {
                ViewRender.assertRenders(view)
            } else {
                assertViewSnapshot(of: view, named: item.type.rawValue)
            }
        }
        assertViewSnapshot(
            of: NavigationStack {
                PassItemDetailView(item: Self.snapPassword(), passService: env.service, onDismiss: {})
            },
            named: "password")
    }

    @Test func itemDetailCorrupted() async throws {
        let corrupted = PassVaultItem.corrupted(PassCorruptedItem(
            id: "bad-1", rawJson: #"{"type":"alien"}"#,
            error: "unknown item type: alien", raw: nil))
        let env = try await Self.makeUnlockedEnv(items: [corrupted])
        defer { Self.cleanUp(env) }
        assertViewSnapshot(
            of: NavigationStack {
                PassItemDetailView(item: corrupted, passService: env.service, onDismiss: {})
            },
            named: "corrupted")
    }

    // MARK: - Form (add per editable type + edit mode)

    @Test func formAddModes() async throws {
        let env = try await Self.makeUnlockedEnv(items: [], folders: [PassFolder(id: "f-1", name: "Work", parentId: nil)])
        defer { Self.cleanUp(env) }
        for type in [PassVaultItemType.password, .card, .bankAccount, .note] {
            assertViewSnapshot(
                of: NavigationStack {
                    PassItemFormView(passService: env.service, defaultType: type,
                                     onSave: {}, onCancel: {})
                },
                named: "add-\(type.rawValue)")
        }
    }

    @Test func formEditModes() async throws {
        let items = try Self.allItems()
        let env = try await Self.makeUnlockedEnv(items: items)
        defer { Self.cleanUp(env) }
        let note = try #require(items.first(where: { $0.type == .note }))
        assertViewSnapshot(
            of: NavigationStack {
                PassItemFormView(passService: env.service, editingItem: Self.snapPassword(),
                                 onSave: {}, onCancel: {})
            },
            named: "edit-password")
        assertViewSnapshot(
            of: NavigationStack {
                PassItemFormView(passService: env.service, editingItem: note,
                                 onSave: {}, onCancel: {})
            },
            named: "edit-note")
    }

    // MARK: - Folders / trash

    @Test func folderListStates() async throws {
        let folders = [PassFolder(id: "f-1", name: "Work", parentId: nil),
                       PassFolder(id: "f-2", name: "Personal", parentId: nil)]
        let populated = try await Self.makeUnlockedEnv(
            items: [Self.snapPassword(folderId: "f-1")], folders: folders)
        defer { Self.cleanUp(populated) }
        assertViewSnapshot(
            of: NavigationStack {
                PassFolderListView(passService: populated.service, onDismiss: {}, onSelectFolder: { _ in })
            },
            named: "populated")

        let empty = try await Self.makeUnlockedEnv(items: [])
        defer { Self.cleanUp(empty) }
        assertViewSnapshot(
            of: NavigationStack {
                PassFolderListView(passService: empty.service, onDismiss: {}, onSelectFolder: { _ in })
            },
            named: "empty")
    }

    @Test func trashStates() async throws {
        let deleted = Self.snapPassword(id: "pw-del", name: "Old Login", deletedAt: Self.fixedMs)
        let populated = try await Self.makeUnlockedEnv(items: [deleted])
        defer { Self.cleanUp(populated) }
        assertViewSnapshot(
            of: NavigationStack { PassTrashView(passService: populated.service, onDismiss: {}) },
            named: "populated")

        let empty = try await Self.makeUnlockedEnv(items: [])
        defer { Self.cleanUp(empty) }
        assertViewSnapshot(
            of: NavigationStack { PassTrashView(passService: empty.service, onDismiss: {}) },
            named: "empty")
    }

    // MARK: - Health report (settled: its .task is pure main-actor in-memory work)

    @Test func healthReportStates() async throws {
        let mixed = try await Self.makeUnlockedEnv(items: [
            Self.snapPassword(id: "pw-weak", name: "Weak", password: "123"),
            Self.snapPassword(id: "pw-reuse-1", name: "Reused A", password: "shared-password-1"),
            Self.snapPassword(id: "pw-reuse-2", name: "Reused B", password: "shared-password-1"),
            Self.snapPassword(id: "pw-old", name: "Old", password: "Str0ng!passphrase-old",
                              updatedAt: 1_500_000_000_000),
        ])
        defer { Self.cleanUp(mixed) }
        await assertSettledViewSnapshot(
            of: NavigationStack {
                PasswordHealthView(passService: mixed.service, onDismiss: {}, onSelectItem: { _ in })
            },
            named: "mixed-report")

        let empty = try await Self.makeUnlockedEnv(items: [])
        defer { Self.cleanUp(empty) }
        await assertSettledViewSnapshot(
            of: NavigationStack {
                PasswordHealthView(passService: empty.service, onDismiss: {}, onSelectItem: { _ in })
            },
            named: "empty-vault")
    }

    // MARK: - Rows / generator / TOTP

    @Test func itemRowVariants() throws {
        let items = try Self.allItems()
        let note = try #require(items.first(where: { $0.type == .note }))
        let stack = VStack(spacing: 0) {
            PassItemRow(item: Self.snapPassword(), onTap: {}, onCopyPassword: {})
            PassItemRow(item: note, onTap: {})
        }
        assertViewSnapshot(of: stack, named: "variants", size: CGSize(width: 402, height: 220))
    }

    @Test func passwordGeneratorRendersOnly() {
        // onAppear generates a random password — snapshot would differ every run.
        ViewRender.assertRenders(
            NavigationStack { PasswordGeneratorView(onPasswordGenerated: { _ in }) })
    }

    @Test func totpDisplayRendersOnly() {
        // Live code + countdown ring — render-only by the determinism rule.
        ViewRender.assertRenders(
            TotpDisplayView(
                config: PassTotpConfig(secret: "JBSWY3DPEHPK3PXP", algorithm: .sha1, digits: 6, period: 30),
                onCopy: { _ in })
            .padding(),
            size: CGSize(width: 402, height: 200))
    }
}
}
```

- [ ] **Step 2: The two-run cycle**

Run: `bash scripts/test.sh --unit 2>&1 | tail -20` → the 13 snapshot-bearing tests fail recording (~26 PNGs); 320 prior tests green.
Run twice more: `bash scripts/test.sh --unit 2>&1 | tail -5` → PASS both, **335 tests**. If `healthReportStates` shows a spinner instead of the report in its PNG (open it and check), the `.task` didn't settle within the yields: raise `yields:` to 16 once; if still a spinner, convert BOTH health snapshots to `assertSettledRenders` and note the coverage hit (-~600 lines) in the task report — the Task 9 gap menu compensates. Never commit a spinner snapshot.

If a PassItemDetailView PNG shows a relative date ("2 years ago"), it re-verifies stable day-to-day; leave it — the fixtures are pinned to Nov 2023 epochs and only roll over at year boundaries (re-record procedure covers that).

- [ ] **Step 3: Commit**

```bash
git add GrooTests/Features/Pass
git commit -m "test: Pass view render/snapshot suite (11 views, fixed-epoch vault fixtures)"
```

---

### Task 3: Azan feature fan-out (17 views + PrayerGuideDataProvider; expected delta ≈ +5,900 covered lines)

**Files:**
- Create: `GrooTests/Features/Azan/AzanViewSnapshotTests.swift`
- Create (by test run): `GrooTests/Features/Azan/__Snapshots__/AzanViewSnapshotTests/*.png`

**Interfaces:**
- Consumes (recon-verified): pure-fixture views `PrayerPostureIcon(posture:size:)`, `ProgressRing(completed:total:size:lineWidth:)`, `WeeklyGridView(grid:)`, `PrayerBreakdownChart(stats:)`, `PrayerTimeRow(entry:onToggleNotification:onTapPrayer:)`, `RakatBreakdownView(rakats:onTapGroup:)`, `RakatGroupSectionView(group:)`, `ShortSurahsView(surahs:expandedId:audioService:)`, `EssentialRecitationsView(recitations:expandedId:audioService:)`, sheets `ShortSurahsSheet()`/`EssentialRecitationsSheet()`/`DailyDuasSheet()` (note: `DailyDuasView.swift` defines only `DailyDuasSheet`); service-backed `TrackerSummaryCard(trackingService:)`, `PrayerAnalyticsView(trackingService:)`, `PrayerLogView(trackingService:)`, `AzanSettingsView(preferences:locationService:onSave:)`, `LocationSearchView(onSelect:)`, `AzanView()`; models `PrayerTimeEntry` (10-field memberwise), `DaySummary(dateString:completedCount:onTimeCount:lateCount:)`, `PrayerStat(prayer:onTimeCount:lateCount:totalDays:)`, `PrayerDeadline.Urgency`, `PrayerGuideDataProvider.guide(for:madhab:role:isTraveling:isQaza:)/shortSurahs()/essentialRecitations()/dailyDuas()`; `PrayerTrackingService(store:now:)` + `logPrayer(dateString:prayer:status:)` + `recalculate()`; `InMemoryLocalStore.make()`; `LocalStore.shared.getAzanPreferences()/saveAzanPreferences(_:)`.
- Classification: snapshots for everything static (guide content, charts, rows, settings list, sheets, tracker/analytics over a fixed-clock service); **render-only** for `AzanView` (live next-prayer countdown) and `PrayerLogView` (month list built from `Date()`).
- `@AppStorage` keys pinned via `withPinnedDefaults`: `prayerGuideMadhab`, `prayerGuideRole`, `prayerGuideTraveling`, `prayerGuideQaza`. `LocalStore.shared` Azan preferences pinned+restored via the suite's `withFixedAzanLocation`. Both are why this suite sits under the serialized umbrella.

- [ ] **Step 1: Create `GrooTests/Features/Azan/AzanViewSnapshotTests.swift`**

```swift
//
//  AzanViewSnapshotTests.swift
//  GrooTests
//
//  Phase 7: render/snapshot coverage for the Azan views. Guide content is
//  static data (PrayerGuideDataProvider); tracker views run over a
//  fixed-clock PrayerTrackingService on an in-memory store. AzanView and
//  PrayerLogView are render-only (wall-clock countdowns / month walks).
//

import SnapshotTesting
import SwiftUI
import Testing
@testable import Groo

extension NetworkStubbedSuites {

@MainActor
@Suite(.serialized, .snapshots(record: .missing))
struct AzanViewSnapshotTests {
    static let baseTime = Date(timeIntervalSince1970: 1_700_000_000)
    static let hanafiDefaults: [String: Any] = [
        "prayerGuideMadhab": FiqhMadhab.hanafi.rawValue,
        "prayerGuideRole": PrayerRole.munfarid.rawValue,
        "prayerGuideTraveling": false,
        "prayerGuideQaza": false,
    ]

    static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static func entry(
        _ prayer: Prayer, isNext: Bool = false, isPassed: Bool = false, isCurrent: Bool = false,
        urgency: PrayerDeadline.Urgency? = nil, notif: Bool = true, adjustment: Int = 0,
        friday: String? = nil, ramadan: String? = nil
    ) -> PrayerTimeEntry {
        PrayerTimeEntry(prayer: prayer, time: baseTime, isNext: isNext, isPassed: isPassed,
                        isCurrent: isCurrent, currentUrgency: urgency, notificationEnabled: notif,
                        adjustment: adjustment, fridayLabel: friday, ramadanLabel: ramadan)
    }

    /// Fixed-clock tracking service with 4 seeded days (alternating
    /// on-time/late) — every derived stat is deterministic.
    static func seededTracking() throws -> PrayerTrackingService {
        let store = try InMemoryLocalStore.make()
        let now = Date(timeIntervalSince1970: 1_751_700_000)   // 2025-07-05T07:20Z (P6 fixture)
        let service = PrayerTrackingService(store: store, now: { now })
        for daysAgo in 0...3 {
            let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: now)!
            for prayer in Prayer.notifiable {
                service.logPrayer(dateString: Self.dayFormatter.string(from: date), prayer: prayer,
                                  status: daysAgo.isMultiple(of: 2) ? .onTime : .late)
            }
        }
        service.recalculate()
        return service
    }

    /// Pin LocalStore.shared's Azan preferences to a fixed manual location
    /// (Dubai) so AzanView neither prompts CoreLocation nor varies by
    /// machine; restores previous values after.
    static func withFixedAzanLocation(_ body: () throws -> Void) rethrows {
        let store = LocalStore.shared
        let prefs = store.getAzanPreferences() ?? LocalAzanPreferences()
        let saved = (prefs.useDeviceLocation, prefs.latitude, prefs.longitude, prefs.locationName)
        prefs.useDeviceLocation = false
        prefs.latitude = 25.2048
        prefs.longitude = 55.2708
        prefs.locationName = "Dubai"
        store.saveAzanPreferences(prefs)
        defer {
            (prefs.useDeviceLocation, prefs.latitude, prefs.longitude, prefs.locationName) = saved
            store.saveAzanPreferences(prefs)
        }
        try body()
    }

    // MARK: - Pure drawing views

    @Test func prayerPostureIconAllPostures() {
        let grid = VStack(spacing: 12) {
            ForEach([PrayerPosture.standing, .handsRaised, .bowing, .standingBrief,
                     .prostrating, .sitting, .salam], id: \.self) { posture in
                HStack { PrayerPostureIcon(posture: posture, size: 32); Text(String(describing: posture)) }
            }
        }.padding()
        assertViewSnapshot(of: grid, named: "all", size: CGSize(width: 300, height: 420))
    }

    @Test func progressRingVariants() {
        let rings = HStack(spacing: 16) {
            ProgressRing(completed: 0, total: 5)
            ProgressRing(completed: 3, total: 5)
            ProgressRing(completed: 5, total: 5)
            ProgressRing(completed: 0, total: 0)
        }.padding()
        assertViewSnapshot(of: rings, named: "variants", size: CGSize(width: 320, height: 100))
    }

    @Test func weeklyGridFixedWeek() {
        let grid = (0..<7).map { day in
            DaySummary(dateString: "2023-11-0\(day + 1)", completedCount: day < 5 ? day + 1 : 0,
                       onTimeCount: day < 5 ? day : 0, lateCount: day < 5 ? 1 : 0)
        }
        assertViewSnapshot(of: WeeklyGridView(grid: grid).padding(), named: "week",
                           size: CGSize(width: 402, height: 160))
    }

    @Test func prayerBreakdownChartFixedStats() {
        let stats = Prayer.notifiable.enumerated().map { index, prayer in
            PrayerStat(prayer: prayer, onTimeCount: 10 - index, lateCount: index, totalDays: 14)
        }
        assertViewSnapshot(of: PrayerBreakdownChart(stats: stats).padding(), named: "stats",
                           size: CGSize(width: 402, height: 300))
    }

    @Test func prayerTimeRowVariants() {
        let rows = VStack(spacing: 0) {
            PrayerTimeRow(entry: Self.entry(.fajr, isPassed: true, ramadan: "Suhoor ends"),
                          onToggleNotification: { _ in }, onTapPrayer: { _ in })
            PrayerTimeRow(entry: Self.entry(.dhuhr, isNext: true, friday: "Jumu'ah"),
                          onToggleNotification: { _ in }, onTapPrayer: { _ in })
            PrayerTimeRow(entry: Self.entry(.asr, isCurrent: true, urgency: .urgent),
                          onToggleNotification: { _ in }, onTapPrayer: { _ in })
            PrayerTimeRow(entry: Self.entry(.maghrib, notif: false, adjustment: 15),
                          onToggleNotification: { _ in }, onTapPrayer: nil)
        }
        assertViewSnapshot(of: rows, named: "variants", size: CGSize(width: 402, height: 320))
    }

    // MARK: - Guide content (drives PrayerGuideDataProvider's 1,150 lines)

    @Test func rakatBreakdownFajr() throws {
        let guide = try #require(PrayerGuideDataProvider.guide(
            for: .fajr, madhab: .hanafi, role: .munfarid, isTraveling: false, isQaza: false))
        assertViewSnapshot(of: RakatBreakdownView(rakats: guide.rakatBreakdown, onTapGroup: { _ in }).padding(),
                           named: "fajr", size: CGSize(width: 402, height: 260))
    }

    @Test func rakatGroupSectionFajrFard() throws {
        let guide = try #require(PrayerGuideDataProvider.guide(
            for: .fajr, madhab: .hanafi, role: .munfarid, isTraveling: false, isQaza: false))
        let group = try #require(guide.groups.first)
        assertViewSnapshot(of: ScrollView { RakatGroupSectionView(group: group) }, named: "fajr-first")
    }

    @Test func prayerDetailHanafiAllPrayers() {
        withPinnedDefaults(Self.hanafiDefaults) {
            for prayer in Prayer.notifiable {
                assertViewSnapshot(of: NavigationStack { PrayerDetailView(prayer: prayer) },
                                   named: prayer.rawValue)
            }
        }
    }

    @Test func prayerDetailVariants() {
        withPinnedDefaults(Self.hanafiDefaults.merging(["prayerGuideQaza": true]) { _, new in new }) {
            assertViewSnapshot(of: NavigationStack { PrayerDetailView(prayer: .dhuhr) }, named: "qaza")
        }
        withPinnedDefaults(Self.hanafiDefaults.merging(["prayerGuideTraveling": true]) { _, new in new }) {
            assertViewSnapshot(of: NavigationStack { PrayerDetailView(prayer: .dhuhr) }, named: "traveling")
        }
        withPinnedDefaults(Self.hanafiDefaults.merging(["prayerGuideMadhab": FiqhMadhab.shafii.rawValue]) { _, new in new }) {
            assertViewSnapshot(of: NavigationStack { PrayerDetailView(prayer: .fajr) }, named: "madhab-unavailable")
        }
    }

    @Test func prayerDetailRepresentativeSet() {
        withPinnedDefaults(Self.hanafiDefaults) {
            let view = NavigationStack { PrayerDetailView(prayer: .fajr) }
            assertViewSnapshot(of: view, named: "dark", appearance: .dark)
            assertViewSnapshot(of: view.environment(\.dynamicTypeSize, .accessibility2), named: "a11y-xl")
        }
    }

    // MARK: - Recitations / surahs / duas

    @Test func shortSurahsCollapsedAndExpanded() throws {
        let surahs = PrayerGuideDataProvider.shortSurahs()
        let first = try #require(surahs.first)
        assertViewSnapshot(
            of: ScrollView { ShortSurahsView(surahs: surahs, expandedId: .constant(nil), audioService: .shared) },
            named: "collapsed")
        assertViewSnapshot(
            of: ScrollView { ShortSurahsView(surahs: surahs, expandedId: .constant(first.id), audioService: .shared) },
            named: "expanded")
    }

    @Test func essentialRecitationsCollapsedAndExpanded() throws {
        let recitations = PrayerGuideDataProvider.essentialRecitations()
        let first = try #require(recitations.first)
        assertViewSnapshot(
            of: ScrollView { EssentialRecitationsView(recitations: recitations, expandedId: .constant(nil), audioService: .shared) },
            named: "collapsed")
        assertViewSnapshot(
            of: ScrollView { EssentialRecitationsView(recitations: recitations, expandedId: .constant(first.id), audioService: .shared) },
            named: "expanded")
    }

    @Test func recitationSheets() {
        assertViewSnapshot(of: ShortSurahsSheet(), named: "surahs-sheet")
        assertViewSnapshot(of: EssentialRecitationsSheet(), named: "recitations-sheet")
        assertViewSnapshot(of: DailyDuasSheet(), named: "duas-sheet")
    }

    // MARK: - Tracking views (fixed-clock service)

    @Test func trackerSummaryCard() throws {
        let service = try Self.seededTracking()
        assertViewSnapshot(of: NavigationStack { TrackerSummaryCard(trackingService: service).padding() },
                           named: "seeded", size: CGSize(width: 402, height: 240))
    }

    @Test func prayerAnalyticsSeeded() async throws {
        let service = try Self.seededTracking()
        await assertSettledViewSnapshot(
            of: NavigationStack { PrayerAnalyticsView(trackingService: service) }, named: "seeded")
    }

    @Test func prayerLogRendersOnly() throws {
        // Month sections are built from Date() — render-only by rule.
        let service = try Self.seededTracking()
        ViewRender.assertRenders(NavigationStack { PrayerLogView(trackingService: service) })
    }

    // MARK: - Settings / search / main screen

    @Test func azanSettingsList() {
        assertViewSnapshot(
            of: NavigationStack {
                AzanSettingsView(preferences: LocalAzanPreferences(),
                                 locationService: AzanLocationService(), onSave: { _ in })
            },
            named: "defaults")
    }

    @Test func locationSearchEmpty() {
        assertViewSnapshot(of: NavigationStack { LocationSearchView(onSelect: { _, _, _ in }) },
                           named: "empty")
    }

    @Test func azanViewRendersOnly() {
        // Live countdown card + real-clock prayer list — render-only. The
        // pinned manual location keeps CoreLocation untouched.
        Self.withFixedAzanLocation {
            ViewRender.assertRenders(AzanView())
        }
    }
}
}
```

- [ ] **Step 2: The two-run cycle**

Run: `bash scripts/test.sh --unit 2>&1 | tail -20` → 17 snapshot-bearing tests record (~33 PNGs).
Run twice more → PASS ×2, **354 tests** (335 + 19). Eyeball `prayerDetailHanafiAllPrayers.fajr.png` (must show the full guide, not a blank list) and `azanSettingsList.defaults.png`.

Failure modes to expect and how to react (never shim the view):
- `guide(for:)` returning nil for hanafi → the provider contract changed; STOP and report.
- `AzanSettingsView` snapshot differing between runs → a `Date()`/location string leaked into the list; find the row and pin its input, or split that row's state out as render-only WITH a note.
- `azanViewRendersOnly` crashing → real defect per spec (views must tolerate their fixture states); STOP and report.

- [ ] **Step 3: Commit**

```bash
git add GrooTests/Features/Azan
git commit -m "test: Azan view render/snapshot suite (guide content, tracker, settings; AzanView render-only)"
```

---

### Task 4: Crypto + Stocks fan-out (16 views; expected delta ≈ +5,000 covered lines) + mid-phase coverage checkpoint

**Files:**
- Create: `GrooTests/Features/Crypto/CryptoViewSnapshotTests.swift`
- Create: `GrooTests/Features/Stocks/StocksViewSnapshotTests.swift`
- Create (by test run): matching `__Snapshots__/` directories

**Interfaces:**
- Consumes (recon-verified): `CryptoView(passService:)`, `PortfolioView(walletManager:ethereumService:coinGeckoService:passService:)`, `SendView(asset:walletManager:ethereumService:passService:)`, `ReceiveView(address:)`, `AssetDetailView(asset:walletManager:ethereumService:coinGeckoService:passService:)`, `WalletListView(walletManager:passService:)`, `WalletOnboardingView(walletManager:passService:)`, `PriceChartView(data:isLoading:isPositive:errorMessage:selectedPoint:)`; `StocksView()`, `StockPortfolioView(portfolioManager:yahooService:)`, `StockDetailView(holding:portfolioManager:yahooService:)`, `StockPriceChartView(data:isLoading:isPositive:errorMessage:currencyCode:timeframe:tradingPeriod:selectedPoint:)`, `StockSearchView(portfolioManager:yahooService:)`, `AddTransactionSheet(symbol:companyName:currency:editingTransaction:onSave:)`, `CurrencyPickerView(selectedCurrency:)`, `StockOnboardingView(portfolioManager:yahooService:)`; models `CryptoAsset` (9-field memberwise), `PricePoint(timestamp:price:)`, `StockHolding` (8-field memberwise), `StockTransaction(id:type:shares:totalCost:date:)`, `StockPricePoint(timestamp:price:)`, `TradingPeriod(open:close:)`; `WalletManager(passService:defaults:)` (reads `walletAddresses`/`activeWalletAddress` from its defaults — seed those instead of running scrypt `createWallet`); `StockPortfolioManager(store:)` + the P6 seeding pattern (`addHolding` → `store.getStockHolding(symbol:)` → `cachedPrice` → `saveStockChanges()` → `loadCachedHoldings()`); `YahooFinanceServiceTests.chartJSON(price:previousClose:currency:)`; stub-backed services `EthereumService(sessionConfiguration:)`, `CoinGeckoService(cache:)`, `YahooFinanceService(cache:)`.
- Classification: **render-only** — `PortfolioView` (initial `isLoading` spinner; async load lands post-draw), `StocksView` (reads the process-global `LocalStore.shared` stock cache — machine-dependent), `AddTransactionSheet` add-mode (DatePicker defaults to today), `PriceChartView`/`StockPriceChartView` `isLoading` states (indeterminate spinner). Everything else snapshots.

- [ ] **Step 1: Create `GrooTests/Features/Crypto/CryptoViewSnapshotTests.swift`**

```swift
//
//  CryptoViewSnapshotTests.swift
//  GrooTests
//
//  Phase 7: render/snapshot coverage for the Crypto views. Wallet state is
//  seeded through WalletManager's injected defaults (never scrypt);
//  services ride StubURLProtocol so nothing leaves the process.
//

import SnapshotTesting
import SwiftUI
import Testing
@testable import Groo

extension NetworkStubbedSuites {

@MainActor
@Suite(.serialized, .snapshots(record: .missing))
struct CryptoViewSnapshotTests {
    static let fixedMs = 1_700_000_000_000
    static let address = "0xAb5801a7D398351b8bE11C439e05C5B3259aeC9B"

    static let ethAsset = CryptoAsset(
        id: "eth", symbol: "ETH", name: "Ethereum", balance: 1.5, price: 2000,
        priceChange24h: 2.5, iconURL: nil, decimals: 18, contractAddress: nil)
    static let tokenAsset = CryptoAsset(
        id: "0xa0b8", symbol: "USDC", name: "USD Coin", balance: 250, price: 1.0,
        priceChange24h: -0.1, iconURL: nil, decimals: 6,
        contractAddress: "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48")

    static func pricePoints() -> [PricePoint] {
        (0..<24).map {
            PricePoint(timestamp: Date(timeIntervalSince1970: 1_700_000_000 + Double($0) * 3600),
                       price: 1900 + Double($0) * 10)
        }
    }

    static func walletItem(id: String, name: String, address: String) -> PassVaultItem {
        .cryptoWallet(PassCryptoWalletItem(
            id: id, type: .cryptoWallet, name: name, address: address,
            seedPhrase: "legal winner thank year wave sausage worth useful legal winner thank yellow",
            privateKey: nil, publicKey: nil, derivationPath: "m/44'/60'/0'/0/0",
            notes: nil, folderId: nil, favorite: nil,
            createdAt: fixedMs, updatedAt: fixedMs, deletedAt: nil))
    }

    struct WalletSetup {
        let manager: WalletManager
        let env: PassServiceIntegrationTests.Env
        let defaults: UserDefaults
        let suiteName: String
    }

    /// Unlocked fake vault + WalletManager over an isolated defaults suite
    /// with pre-seeded addresses — no scrypt, no network beyond the stubs.
    static func makeWalletSetup(items: [PassVaultItem], addresses: [String]) async throws -> WalletSetup {
        let env = try PassServiceIntegrationTests.makeEnv(items: items)
        _ = try await env.service.unlock(password: PassServiceIntegrationTests.password)
        let suiteName = "CryptoSnapshotTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(addresses, forKey: "walletAddresses")
        if let first = addresses.first { defaults.set(first, forKey: "activeWalletAddress") }
        return WalletSetup(manager: WalletManager(passService: env.service, defaults: defaults),
                           env: env, defaults: defaults, suiteName: suiteName)
    }

    static func tearDown(_ setup: WalletSetup) {
        setup.defaults.removePersistentDomain(forName: setup.suiteName)
        try? FileManager.default.removeItem(at: setup.env.tempDir)
    }

    static func stubbedEthereum() -> EthereumService {
        EthereumService(sessionConfiguration: StubURLProtocol.stubbedConfiguration())
    }

    static func stubbedCoinGecko() -> CoinGeckoService {
        CoinGeckoService(cache: APICache(sessionConfiguration: StubURLProtocol.stubbedConfiguration()))
    }

    // MARK: - Pure fixtures

    @Test func receiveViewQR() {
        assertViewSnapshot(of: NavigationStack { ReceiveView(address: Self.address) }, named: "address")
    }

    @Test func priceChartVariants() {
        let points = Self.pricePoints()
        assertViewSnapshot(
            of: PriceChartView(data: points, isLoading: false, isPositive: true,
                               errorMessage: nil, selectedPoint: .constant(nil)).padding(),
            named: "positive", size: CGSize(width: 402, height: 300))
        assertViewSnapshot(
            of: PriceChartView(data: points.reversed(), isLoading: false, isPositive: false,
                               errorMessage: nil, selectedPoint: .constant(nil)).padding(),
            named: "negative", size: CGSize(width: 402, height: 300))
        assertViewSnapshot(
            of: PriceChartView(data: [], isLoading: false, isPositive: true,
                               errorMessage: "Rate limited — try again later", selectedPoint: .constant(nil)).padding(),
            named: "error", size: CGSize(width: 402, height: 300))
        assertViewSnapshot(
            of: PriceChartView(data: [], isLoading: false, isPositive: true,
                               errorMessage: nil, selectedPoint: .constant(nil)).padding(),
            named: "empty", size: CGSize(width: 402, height: 300))
        // isLoading spinner is indeterminate — render-only
        ViewRender.assertRenders(
            PriceChartView(data: [], isLoading: true, isPositive: true,
                           errorMessage: nil, selectedPoint: .constant(nil)).padding(),
            size: CGSize(width: 402, height: 300))
    }

    // MARK: - Wallet-backed screens

    @Test func sendViewForAssets() async throws {
        StubURLProtocol.reset()
        let setup = try await Self.makeWalletSetup(
            items: [Self.walletItem(id: "w-1", name: "Main", address: Self.address)],
            addresses: [Self.address])
        defer { Self.tearDown(setup) }
        assertViewSnapshot(
            of: NavigationStack {
                SendView(asset: Self.ethAsset, walletManager: setup.manager,
                         ethereumService: Self.stubbedEthereum(), passService: setup.env.service)
            },
            named: "eth")
        assertViewSnapshot(
            of: NavigationStack {
                SendView(asset: Self.tokenAsset, walletManager: setup.manager,
                         ethereumService: Self.stubbedEthereum(), passService: setup.env.service)
            },
            named: "token")
    }

    @Test func walletOnboardingMain() async throws {
        StubURLProtocol.reset()
        let setup = try await Self.makeWalletSetup(items: [], addresses: [])
        defer { Self.tearDown(setup) }
        assertViewSnapshot(
            of: WalletOnboardingView(walletManager: setup.manager, passService: setup.env.service),
            named: "main")
    }

    @Test func walletListStates() async throws {
        StubURLProtocol.reset()
        let second = "0x00000000219ab540356cBB839Cbe05303d7705Fa"
        let populated = try await Self.makeWalletSetup(
            items: [Self.walletItem(id: "w-1", name: "Main", address: Self.address),
                    Self.walletItem(id: "w-2", name: "Savings", address: second)],
            addresses: [Self.address, second])
        defer { Self.tearDown(populated) }
        await assertSettledViewSnapshot(
            of: NavigationStack {
                WalletListView(walletManager: populated.manager, passService: populated.env.service)
            },
            named: "populated")

        // Locked PassService → unlock-prompt branch
        let lockedEnv = try PassServiceIntegrationTests.makeEnv(items: [])
        defer { try? FileManager.default.removeItem(at: lockedEnv.tempDir) }
        let lockedManager = WalletManager(passService: lockedEnv.service, defaults: populated.defaults)
        await assertSettledViewSnapshot(
            of: NavigationStack {
                WalletListView(walletManager: lockedManager, passService: lockedEnv.service)
            },
            named: "locked")
    }

    @Test func cryptoViewOnboardingState() async throws {
        StubURLProtocol.reset()
        let env = try PassServiceIntegrationTests.makeEnv(items: [])
        defer { try? FileManager.default.removeItem(at: env.tempDir) }
        _ = try await env.service.unlock(password: PassServiceIntegrationTests.password)
        // CryptoView builds its own WalletManager over UserDefaults.standard —
        // pin the wallet keys empty so the onboarding branch is deterministic.
        let previousActive = UserDefaults.standard.object(forKey: "activeWalletAddress")
        UserDefaults.standard.removeObject(forKey: "activeWalletAddress")
        defer { if let previousActive { UserDefaults.standard.set(previousActive, forKey: "activeWalletAddress") } }
        await withPinnedDefaults(["walletAddresses": [String]()]) {
            await assertSettledViewSnapshot(
                of: CryptoView(passService: env.service), named: "onboarding")
        }
    }

    @Test func portfolioViewRendersOnly() async throws {
        StubURLProtocol.reset()
        let setup = try await Self.makeWalletSetup(
            items: [Self.walletItem(id: "w-1", name: "Main", address: Self.address)],
            addresses: [Self.address])
        defer { Self.tearDown(setup) }
        // Initial isLoading spinner + async portfolio load → render-only.
        await ViewRender.assertSettledRenders(
            NavigationStack {
                PortfolioView(walletManager: setup.manager, ethereumService: Self.stubbedEthereum(),
                              coinGeckoService: Self.stubbedCoinGecko(), passService: setup.env.service)
            })
    }

    @Test func assetDetailInitial() async throws {
        StubURLProtocol.reset()
        let setup = try await Self.makeWalletSetup(
            items: [Self.walletItem(id: "w-1", name: "Main", address: Self.address)],
            addresses: [Self.address])
        defer { Self.tearDown(setup) }
        // Header/stats/timeframe picker are deterministic; the chart's async
        // load lands post-draw (chartData starts empty).
        assertViewSnapshot(
            of: NavigationStack {
                AssetDetailView(asset: Self.ethAsset, walletManager: setup.manager,
                                ethereumService: Self.stubbedEthereum(),
                                coinGeckoService: Self.stubbedCoinGecko(),
                                passService: setup.env.service)
            },
            named: "initial")
    }
}
}
```

- [ ] **Step 2: Create `GrooTests/Features/Stocks/StocksViewSnapshotTests.swift`**

```swift
//
//  StocksViewSnapshotTests.swift
//  GrooTests
//
//  Phase 7: render/snapshot coverage for the Stocks views over a seeded
//  in-memory StockPortfolioManager (P6 seeding pattern) with pinned
//  displayCurrency and a stubbed Yahoo service for exchange rates.
//

import SnapshotTesting
import SwiftUI
import Testing
@testable import Groo

extension NetworkStubbedSuites {

@MainActor
@Suite(.serialized, .snapshots(record: .missing))
struct StocksViewSnapshotTests {
    static let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)

    static func stubbedYahoo() -> YahooFinanceService {
        YahooFinanceService(cache: APICache(sessionConfiguration: StubURLProtocol.stubbedConfiguration()))
    }

    /// AAPL (USD, priced 150 on 10 shares @100) + Toyota (JPY) — the P6
    /// currency-suite shape, dyadic numbers so totals are exact.
    static func seededManager() async throws -> StockPortfolioManager {
        StubURLProtocol.reset()
        let store = try InMemoryLocalStore.make()
        let manager = StockPortfolioManager(store: store)
        manager.addHolding(symbol: "AAPL", companyName: "Apple", exchange: "NMS")
        manager.addTransaction(to: "AAPL", type: .buy, shares: 10, totalCost: 1000, date: Self.fixedDate)
        manager.addHolding(symbol: "7203.T", companyName: "Toyota", exchange: "JPX")
        manager.addTransaction(to: "7203.T", type: .buy, shares: 50, totalCost: 50_000, date: Self.fixedDate)
        let aapl = try #require(store.getStockHolding(symbol: "AAPL"))
        aapl.cachedPrice = 150
        let toyota = try #require(store.getStockHolding(symbol: "7203.T"))
        toyota.cachedPrice = 2000
        store.saveStockChanges()
        manager.loadCachedHoldings()
        // JPY→USD at a dyadic 2^-7 so converted totals are exact doubles
        StubURLProtocol.enqueue(method: "GET", pathSuffix: "/chart/JPYUSD=X",
                                json: YahooFinanceServiceTests.chartJSON(price: "0.0078125", previousClose: "0.0078125"))
        await manager.refreshExchangeRates(using: Self.stubbedYahoo())
        return manager
    }

    static func holding(transactions: [StockTransaction]) -> StockHolding {
        StockHolding(symbol: "AAPL", companyName: "Apple", exchange: "NMS", currency: "USD",
                     currentPrice: 150, changePercent: 1.25, previousClose: 148.15,
                     transactions: transactions)
    }

    static func stockPoints() -> [StockPricePoint] {
        (0..<26).map {
            StockPricePoint(timestamp: Date(timeIntervalSince1970: 1_700_000_000 + Double($0) * 900),
                            price: 148 + Double($0) * 0.25)
        }
    }

    // MARK: - Pure fixtures

    @Test func stockPriceChartVariants() {
        let points = Self.stockPoints()
        let period = TradingPeriod(open: Date(timeIntervalSince1970: 1_700_000_000),
                                   close: Date(timeIntervalSince1970: 1_700_023_400))
        assertViewSnapshot(
            of: StockPriceChartView(data: points, isLoading: false, isPositive: true,
                                    errorMessage: nil, currencyCode: "USD", timeframe: .day,
                                    tradingPeriod: period, selectedPoint: .constant(nil)).padding(),
            named: "day-positive", size: CGSize(width: 402, height: 320))
        assertViewSnapshot(
            of: StockPriceChartView(data: points.reversed(), isLoading: false, isPositive: false,
                                    errorMessage: nil, currencyCode: "JPY", timeframe: .week,
                                    tradingPeriod: nil, selectedPoint: .constant(nil)).padding(),
            named: "week-negative-jpy", size: CGSize(width: 402, height: 320))
        assertViewSnapshot(
            of: StockPriceChartView(data: [], isLoading: false, isPositive: true,
                                    errorMessage: "No chart data", currencyCode: "USD", timeframe: .day,
                                    tradingPeriod: nil, selectedPoint: .constant(nil)).padding(),
            named: "error", size: CGSize(width: 402, height: 320))
        ViewRender.assertRenders(
            StockPriceChartView(data: [], isLoading: true, isPositive: true,
                                errorMessage: nil, currencyCode: "USD", timeframe: .day,
                                tradingPeriod: nil, selectedPoint: .constant(nil)).padding(),
            size: CGSize(width: 402, height: 320))
    }

    @Test func currencyPicker() {
        assertViewSnapshot(of: NavigationStack { CurrencyPickerView(selectedCurrency: .constant("USD")) },
                           named: "usd-selected")
    }

    @Test func addTransactionModes() {
        // Add mode's DatePicker defaults to Date() — render-only.
        ViewRender.assertRenders(
            NavigationStack {
                AddTransactionSheet(symbol: "AAPL", companyName: "Apple", onSave: { _, _, _, _ in })
            })
        let editing = StockTransaction(id: "t-1", type: .buy, shares: 10, totalCost: 1000,
                                       date: Self.fixedDate)
        assertViewSnapshot(
            of: NavigationStack {
                AddTransactionSheet(symbol: "AAPL", companyName: "Apple", currency: "USD",
                                    editingTransaction: editing, onSave: { _, _, _, _ in })
            },
            named: "edit")
    }

    // MARK: - Manager-backed screens

    @Test func stockPortfolioPopulatedAndRepresentativeSet() async throws {
        let manager = try await Self.seededManager()
        withPinnedDefaults(["displayCurrency": "USD"]) {
            let view = NavigationStack {
                StockPortfolioView(portfolioManager: manager, yahooService: Self.stubbedYahoo())
            }
            assertViewSnapshot(of: view, named: "populated")
            assertViewSnapshot(of: view, named: "dark", appearance: .dark)
            assertViewSnapshot(of: view.environment(\.dynamicTypeSize, .accessibility2), named: "a11y-xl")
        }
    }

    @Test func stockDetailWithTransactions() async throws {
        let manager = try await Self.seededManager()
        let holding = Self.holding(transactions: [
            StockTransaction(id: "t-1", type: .buy, shares: 10, totalCost: 1000, date: Self.fixedDate),
            StockTransaction(id: "t-2", type: .sell, shares: 2, totalCost: 300,
                             date: Date(timeIntervalSince1970: 1_705_000_000)),
        ])
        withPinnedDefaults(["displayCurrency": "USD"]) {
            assertViewSnapshot(
                of: NavigationStack {
                    StockDetailView(holding: holding, portfolioManager: manager,
                                    yahooService: Self.stubbedYahoo())
                },
                named: "with-transactions")
        }
    }

    @Test func stockSearchEmpty() async throws {
        let manager = try await Self.seededManager()
        assertViewSnapshot(
            of: NavigationStack {
                StockSearchView(portfolioManager: manager, yahooService: Self.stubbedYahoo())
            },
            named: "empty")
    }

    @Test func stockOnboarding() throws {
        StubURLProtocol.reset()
        let store = try InMemoryLocalStore.make()
        assertViewSnapshot(
            of: StockOnboardingView(portfolioManager: StockPortfolioManager(store: store),
                                    yahooService: Self.stubbedYahoo()),
            named: "empty")
    }

    @Test func stocksViewShellRendersOnly() {
        // StocksView owns a manager over LocalStore.shared (process-global,
        // machine-dependent cache) — render-only.
        ViewRender.assertRenders(StocksView())
    }
}
}
```

- [ ] **Step 3: The two-run cycle**

Run once (records, ~24 PNGs), then twice green: **370 tests** (354 + 16). Eyeball `stockPortfolioPopulatedAndRepresentativeSet.populated.png` — it must show BOTH holdings with converted totals (¥100,000 at 0.0078125 → $781.25 slice), or the seeding path silently regressed.

`StockDetailView` note: its `.task` fires `getChartData` against the stub queue — enqueue nothing; the chart error state lands post-draw and does not affect the committed image. If the detail PNG differs between runs 2 and 3, the async chart result IS landing pre-draw: convert that snapshot to `assertRenders` and note it (do not enqueue a chart response to "fix" timing — that's a race, not determinism).

- [ ] **Step 4: COVERAGE CHECKPOINT**

Run: `bash scripts/test.sh --unit --coverage 2>&1 | tail -60`
Record Groo.app overall. **Expected ≥ ~68%** (36.69 + [130+2,600+5,900+5,000]/41,194 ≈ 69.8%, minus slack). If below 66%: STOP, compare per-file actuals against the Task 2–4 pool tables, and add fixture states to the biggest shortfall files BEFORE proceeding (candidates: more `PassItemDetailView` field variants, `SendView` unlock-prompt state, `AzanSettingsView` — check which sections never executed via `xcrun xccov view --file`). Report the checkpoint number in the task report either way.

- [ ] **Step 5: Commit**

```bash
git add GrooTests/Features/Crypto GrooTests/Features/Stocks
git commit -m "test: Crypto + Stocks view render/snapshot suites (seeded wallets/holdings, stubbed services)"
```

---

### Task 5: Pad + Scratchpad fan-out (13 views + WebViewBridge; expected delta ≈ +1,900 covered lines)

**Files:**
- Create: `GrooTests/Features/Pad/PadViewSnapshotTests.swift`
- Create: `GrooTests/Features/Pad/WebViewBridgeTests.swift`
- Create: `GrooTests/Features/Scratchpad/ScratchpadViewSnapshotTests.swift` (new directory — synchronized, compiles automatically)
- Create (by test runs): matching `__Snapshots__/` directories

**Interfaces:**
- Consumes (recon-verified): `PadServiceTests.makeUnlockedEnv()` (`Env(service:store:keychain:key:)` — biometric unlock over a pre-seeded `InMemoryKeychain`, zero network); `SyncService(api:store:monitorsNetwork:)` with `monitorsNetwork: false` (`.task` sync() early-returns offline); views `PadView(padService:syncService:onSignOut:)`, `PadListView(padService:syncService:refreshTrigger:)`, `PadUnlockView(padService:syncService:onUnlock:onSignOut:)`, `AddItemSheet(padService:syncService:)`, `ItemRow(item:padService:onCopy:onDelete:)`, `PasteFAB(padService:syncService:onItemAdded:)` (the type in `QuickInputBar.swift`), `ToastView(message:style:)`/`.toast(isPresented:message:style:duration:)`/`ToastState`, `FileAttachmentChip(file:padService:)`, `FileAttachmentsGrid(files:padService:)`, `PendingFileChip(file:onRemove:)`, `FilePreviewSheet(data:mimeType:fileName:)`, `FileIconHelper.icon(for:)/formatSize(_:)`; `ScratchpadListView(pads:selectedId:onSelect:onDelete:onCreate:)`, `ScratchpadTabView(padService:syncService:)` (+ `.environment(AuthService())` because its unlocked branch hosts `ScratchpadView`), `ScratchpadEditorView(scratchpad:onContentChange:)`, `ScratchpadWebView(initialContent:onContentChange:onReady:onError:webView:)` + its `Coordinator`; models `DecryptedListItem(id:text:files:createdAt: Int)`, `DecryptedFileAttachment(id:name:type:size:r2Key:)`, `DecryptedScratchpad(id:content:files:createdAt:updatedAt:)` (Int ms), `LocalPadItem(id:encryptedTextJSON:createdAt:syncedAt:filesJSON:)`, `PadEncryptedPayload(ciphertext:iv:version:)`; `EditorCommand`/`EditorEvent` from `WebViewBridge.swift`.
- Classification: **render-only** — `AddItemSheet` (focused TextEditor caret), `FilePreviewSheet`/`ScratchpadWebView`/`ScratchpadEditorView` (live WKWebView paint), `ScratchpadView` itself (deferred to Task 8, where the store extraction makes its states snapshot-able). Everything else snapshots.
- **Exclusion:** `CameraPicker` (UIImagePickerController `.camera` throws on simulator; user-action-only).

- [ ] **Step 1: Create `GrooTests/Features/Pad/PadViewSnapshotTests.swift`**

```swift
//
//  PadViewSnapshotTests.swift
//  GrooTests
//
//  Phase 7: render/snapshot coverage for the Pad views over an unlocked
//  PadService (biometric fake-keychain path — no network) and an offline
//  SyncService. Encrypted fixtures are produced with the env's real key so
//  decryption succeeds end-to-end.
//

import SnapshotTesting
import SwiftUI
import Testing
import CryptoKit
@testable import Groo

extension NetworkStubbedSuites {

@MainActor
@Suite(.serialized, .snapshots(record: .missing))
struct PadViewSnapshotTests {
    static let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)

    /// Encrypt text with the env's key and return the PadEncryptedPayload
    /// JSON string LocalPadItem/LocalScratchpad store.
    static func encryptedJSON(_ text: String, key: SymmetricKey) throws -> String {
        let combined = try CryptoService().encryptData(Data(text.utf8), using: key)
        let payload = PadEncryptedPayload(
            ciphertext: combined.dropFirst(12).base64EncodedString(),
            iv: combined.prefix(12).base64EncodedString(),
            version: 1)
        return String(decoding: try JSONEncoder().encode(payload), as: UTF8.self)
    }

    static func encryptedPayload(_ text: String, key: SymmetricKey) throws -> PadEncryptedPayload {
        let combined = try CryptoService().encryptData(Data(text.utf8), using: key)
        return PadEncryptedPayload(
            ciphertext: combined.dropFirst(12).base64EncodedString(),
            iv: combined.prefix(12).base64EncodedString(),
            version: 1)
    }

    static func offlineSync(store: LocalStore) -> SyncService {
        SyncService(
            api: APIClient(baseURL: URL(string: "https://pad.test")!,
                           sessionConfiguration: StubURLProtocol.stubbedConfiguration(),
                           tokenProvider: { "pad-token" }),
            store: store, monitorsNetwork: false)
    }

    static func lockedPadService() throws -> (service: PadService, store: LocalStore) {
        let store = try InMemoryLocalStore.make()
        let service = PadService(
            api: APIClient(baseURL: URL(string: "https://pad.test")!,
                           sessionConfiguration: StubURLProtocol.stubbedConfiguration(),
                           tokenProvider: { "pad-token" }),
            keychain: InMemoryKeychain(), store: store)
        return (service, store)
    }

    static func seedItem(_ env: PadServiceTests.Env, id: String, text: String,
                         files: [PadFileAttachment] = []) throws {
        let item = LocalPadItem(id: id, encryptedTextJSON: try Self.encryptedJSON(text, key: env.key),
                                createdAt: Self.fixedDate, syncedAt: Self.fixedDate)
        if !files.isEmpty { item.files = files }
        env.store.context.insert(item)
        try env.store.context.save()
    }

    static func fileAttachment(_ env: PadServiceTests.Env, id: String, name: String,
                               type: String, size: Int) throws -> PadFileAttachment {
        PadFileAttachment(id: id,
                          encryptedName: try Self.encryptedPayload(name, key: env.key),
                          size: size,
                          encryptedType: try Self.encryptedPayload(type, key: env.key),
                          r2Key: "files/\(id)")
    }

    // MARK: - Unlock / shell

    @Test func padUnlockLocked() throws {
        StubURLProtocol.reset()
        let (service, store) = try Self.lockedPadService()
        assertViewSnapshot(
            of: PadUnlockView(padService: service, syncService: Self.offlineSync(store: store),
                              onUnlock: {}, onSignOut: {}),
            named: "locked")
    }

    @Test func padViewLockedShell() throws {
        StubURLProtocol.reset()
        let (service, store) = try Self.lockedPadService()
        assertViewSnapshot(
            of: PadView(padService: service, syncService: Self.offlineSync(store: store), onSignOut: {}),
            named: "locked")
    }

    // MARK: - List

    @Test func padListPopulated() async throws {
        StubURLProtocol.reset()
        let env = try PadServiceTests.makeUnlockedEnv()
        try Self.seedItem(env, id: "item-1", text: "Meeting notes for Monday")
        try Self.seedItem(env, id: "item-2", text: "https://example.com/shared-link",
                          files: [try Self.fileAttachment(env, id: "f-1", name: "report.pdf",
                                                          type: "application/pdf", size: 82_944)])
        await assertSettledViewSnapshot(
            of: NavigationStack {
                PadListView(padService: env.service, syncService: Self.offlineSync(store: env.store))
            },
            named: "populated")
    }

    @Test func padListEmpty() async throws {
        StubURLProtocol.reset()
        let env = try PadServiceTests.makeUnlockedEnv()
        await assertSettledViewSnapshot(
            of: NavigationStack {
                PadListView(padService: env.service, syncService: Self.offlineSync(store: env.store))
            },
            named: "empty")
    }

    @Test func itemRowVariants() throws {
        StubURLProtocol.reset()
        let env = try PadServiceTests.makeUnlockedEnv()
        let plain = DecryptedListItem(id: "i-1", text: "Short note", files: [],
                                      createdAt: 1_700_000_000_000)
        let withFile = DecryptedListItem(
            id: "i-2", text: "Contract draft",
            files: [DecryptedFileAttachment(id: "f-1", name: "contract.docx",
                                            type: "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
                                            size: 120_832, r2Key: "files/f-1")],
            createdAt: 1_700_000_000_000)
        let long = DecryptedListItem(id: "i-3",
                                     text: String(repeating: "A very long pad entry line. ", count: 12),
                                     files: [], createdAt: 1_700_000_000_000)
        let rows = List {
            ItemRow(item: plain, padService: env.service, onCopy: {}, onDelete: {})
            ItemRow(item: withFile, padService: env.service, onCopy: {}, onDelete: {})
            ItemRow(item: long, padService: env.service, onCopy: {}, onDelete: {})
        }
        assertViewSnapshot(of: rows, named: "variants")
    }

    // MARK: - Add sheet / FAB / toast

    @Test func addItemSheetRendersOnly() throws {
        StubURLProtocol.reset()
        let env = try PadServiceTests.makeUnlockedEnv()
        // Focused TextEditor (caret) on appear — render-only by rule.
        ViewRender.assertRenders(
            NavigationStack {
                AddItemSheet(padService: env.service, syncService: Self.offlineSync(store: env.store))
            })
    }

    @Test func pasteFAB() throws {
        StubURLProtocol.reset()
        let env = try PadServiceTests.makeUnlockedEnv()
        assertViewSnapshot(
            of: PasteFAB(padService: env.service, syncService: Self.offlineSync(store: env.store),
                         onItemAdded: {})
                .padding(),
            named: "default", size: CGSize(width: 200, height: 160))
    }

    @Test func toastVariants() {
        let stack = VStack(spacing: 12) {
            ToastView(message: "Copied to clipboard", style: .success)
            ToastView(message: "Something went wrong", style: .error)
            ToastView(message: "Syncing…", style: .info)
        }.padding()
        assertViewSnapshot(of: stack, named: "styles", size: CGSize(width: 402, height: 260))
        assertViewSnapshot(
            of: Color.clear.toast(isPresented: .constant(true), message: "Copied!", style: .success),
            named: "modifier-presented")
    }

    @Test func toastStateTransitions() {
        let state = ToastState()
        #expect(!state.isPresented)
        state.showCopied()
        #expect(state.isPresented)
        #expect(state.style == .success)
        state.showError("nope")
        #expect(state.message == "nope")
        #expect(state.style == .error)
        state.show("info", style: .info)
        #expect(state.style == .info)
    }

    // MARK: - File attachments

    @Test func fileAttachmentComponents() throws {
        StubURLProtocol.reset()
        let env = try PadServiceTests.makeUnlockedEnv()
        let files = [
            DecryptedFileAttachment(id: "f-1", name: "report.pdf", type: "application/pdf",
                                    size: 82_944, r2Key: "files/f-1"),
            DecryptedFileAttachment(id: "f-2", name: "photo.jpg", type: "image/jpeg",
                                    size: 2_411_724, r2Key: "files/f-2"),
        ]
        let pending = PendingFile(name: "notes.txt", type: "text/plain", data: Data("hello".utf8))
        let stack = VStack(alignment: .leading, spacing: 16) {
            FileAttachmentChip(file: files[0], padService: env.service)
            FileAttachmentsGrid(files: files, padService: env.service)
            PendingFileChip(file: pending, onRemove: {})
        }.padding()
        assertViewSnapshot(of: stack, named: "components", size: CGSize(width: 402, height: 320))
    }

    @Test func filePreviewSheetRendersOnly() {
        // Hosts a WKWebView (async paint) — render-only.
        ViewRender.assertRenders(
            FilePreviewSheet(data: Data("hello preview".utf8), mimeType: "text/plain",
                             fileName: "notes.txt"))
    }

    @Test func fileIconHelperMappings() {
        #expect(FileIconHelper.icon(for: "application/pdf") != FileIconHelper.icon(for: "image/jpeg"))
        #expect(!FileIconHelper.icon(for: "application/x-unknown-blob").isEmpty)   // fallback icon
        #expect(FileIconHelper.formatSize(0) != "")
        #expect(FileIconHelper.formatSize(82_944).contains("K") || FileIconHelper.formatSize(82_944).lowercased().contains("kb"))
    }
}
}
```

(`PendingFile` lives in `FileAttachmentView.swift` with `let id = UUID()` — constructing it in a test is fine; the UUID never renders.) If `FileIconHelper.formatSize` uses `ByteCountFormatter` with locale-dependent output, weaken the last assertion to non-empty + digits — do NOT pin separator-exact strings (P6 locale rule).

- [ ] **Step 2: Create `GrooTests/Features/Pad/WebViewBridgeTests.swift`**

FIRST read `Groo/Features/Scratchpad/WebViewBridge.swift` and confirm the event dictionary keys `EditorEvent.parse(from:)` expects (recon indicates `{"type": "ready" | "contentChanged" | "error", …content/message payload…}`) — adjust the three payload literals below to the real keys before running.

```swift
//
//  WebViewBridgeTests.swift
//  GrooTests
//
//  Pure-logic tests for the JS bridge: EditorCommand JS generation
//  (escaping is the load-bearing part) and EditorEvent parsing.
//

import Testing
@testable import Groo

struct WebViewBridgeTests {
    @Test func setContentEscapesJSMetacharacters() {
        let js = EditorCommand.setContent(#"line "quoted" \ end"# + "\nnext\rline").jsCall
        #expect(js.contains(#"\\"#))          // backslash escaped
        #expect(js.contains(#"\""#))          // quote escaped
        #expect(js.contains(#"\n"#))          // newline escaped
        #expect(js.contains(#"\r"#))          // carriage return escaped
        #expect(!js.contains("\n"), "raw newline would break the JS string literal")
        #expect(js.contains("window.grooEditor"))
    }

    @Test func simpleCommandsProduceGuardedCalls() {
        #expect(EditorCommand.focus.jsCall.contains("window.grooEditor"))
        #expect(EditorCommand.blur.jsCall.contains("window.grooEditor"))
        #expect(EditorCommand.setReadOnly(true).jsCall.contains("true"))
        #expect(EditorCommand.setReadOnly(false).jsCall.contains("false"))
    }

    @Test func parseRecognizesAllEventTypes() throws {
        guard case .ready = try #require(EditorEvent.parse(from: ["type": "ready"])) else {
            Issue.record("expected .ready"); return
        }
        guard case .contentChanged(let content) =
                try #require(EditorEvent.parse(from: ["type": "contentChanged", "content": "# Hi"])) else {
            Issue.record("expected .contentChanged"); return
        }
        #expect(content == "# Hi")
        guard case .error(let message) =
                try #require(EditorEvent.parse(from: ["type": "error", "message": "boom"])) else {
            Issue.record("expected .error"); return
        }
        #expect(message == "boom")
    }

    @Test func parseRejectsUnknownAndMalformed() {
        #expect(EditorEvent.parse(from: ["type": "alien"]) == nil)
        #expect(EditorEvent.parse(from: [:]) == nil)
        #expect(EditorEvent.parse(from: ["type": "contentChanged"]) == nil)   // missing payload
    }
}
```

(If `EditorEvent` is not `Equatable`, the `== nil` comparisons still compile via `Optional`'s `_ == nil`; the `guard case` pattern avoids needing Equatable elsewhere.)

- [ ] **Step 3: Create `GrooTests/Features/Scratchpad/ScratchpadViewSnapshotTests.swift`**

```swift
//
//  ScratchpadViewSnapshotTests.swift
//  GrooTests
//
//  Phase 7: Scratchpad view coverage that does NOT need the Task 8 store
//  extraction — the pure list, the locked tab, the WKWebView-backed editor
//  surfaces (render-only), and the Coordinator's message handling driven
//  through a WKScriptMessage stub.
//

import SnapshotTesting
import SwiftUI
import Testing
import WebKit
@testable import Groo

extension NetworkStubbedSuites {

@MainActor
@Suite(.serialized, .snapshots(record: .missing))
struct ScratchpadViewSnapshotTests {
    static func pad(id: String, content: String, updatedAt: Int = 1_700_000_000_000) -> DecryptedScratchpad {
        DecryptedScratchpad(id: id, content: content, files: [],
                            createdAt: 1_699_000_000_000, updatedAt: updatedAt)
    }

    @Test func scratchpadListStates() {
        let pads = [
            Self.pad(id: "p-1", content: "# Shopping\nmilk, eggs"),
            Self.pad(id: "p-2", content: "# Ideas\n- render harness"),
            Self.pad(id: "p-3", content: ""),   // "Untitled" title branch
        ]
        assertViewSnapshot(
            of: NavigationStack {
                ScratchpadListView(pads: pads, selectedId: "p-2", onSelect: { _ in },
                                   onDelete: { _ in }, onCreate: {})
            },
            named: "populated")
        assertViewSnapshot(
            of: NavigationStack {
                ScratchpadListView(pads: [], selectedId: nil, onSelect: { _ in },
                                   onDelete: { _ in }, onCreate: {})
            },
            named: "empty")
    }

    @Test func scratchpadTabLocked() throws {
        StubURLProtocol.reset()
        let (service, store) = try PadViewSnapshotTests.lockedPadService()
        assertViewSnapshot(
            of: ScratchpadTabView(padService: service,
                                  syncService: PadViewSnapshotTests.offlineSync(store: store))
                .environment(AuthService()),
            named: "locked")
    }

    @Test func scratchpadEditorRendersOnly() {
        ViewRender.assertRenders(
            ScratchpadEditorView(scratchpad: Self.pad(id: "p-1", content: "# Hello"),
                                 onContentChange: { _ in }))
    }

    @Test func scratchpadWebViewRendersOnly() {
        ViewRender.assertRenders(
            ScratchpadWebView(initialContent: "# Hello", onContentChange: { _ in },
                              onReady: {}, onError: { _ in }, webView: .constant(nil)))
    }

    @Test func coordinatorRoutesScriptMessages() async {
        final class StubScriptMessage: WKScriptMessage {
            private let stubbedBody: Any
            init(body: Any) { self.stubbedBody = body; super.init() }
            override var body: Any { stubbedBody }
            override var name: String { "grooEditor" }
        }

        var readyCount = 0
        var contents: [String] = []
        var errors: [String] = []
        let view = ScratchpadWebView(
            initialContent: "seed",
            onContentChange: { contents.append($0) },
            onReady: { readyCount += 1 },
            onError: { errors.append($0) },
            webView: .constant(nil))
        let coordinator = view.makeCoordinator()
        let controller = WKUserContentController()

        coordinator.userContentController(controller, didReceive: StubScriptMessage(body: ["type": "ready"]))
        coordinator.userContentController(controller, didReceive: StubScriptMessage(body: ["type": "contentChanged", "content": "# Edited"]))
        coordinator.userContentController(controller, didReceive: StubScriptMessage(body: ["type": "error", "message": "editor exploded"]))
        coordinator.userContentController(controller, didReceive: StubScriptMessage(body: "not-a-dict"))
        await Task.yield()   // in case the coordinator hops to the main queue

        #expect(readyCount == 1)
        #expect(contents == ["# Edited"])
        #expect(errors == ["editor exploded"])
    }
}
}
```

(Adjust the message body literals to the keys confirmed in Step 2. If the Coordinator's `onReady` path ALSO fires a pending `setContent` into the nil webView, that's fine — `webView?` is nil-safe.)

- [ ] **Step 4: The two-run cycle**

Run once (records ~13 PNGs), then twice green: **391 tests** (370 + 21). Eyeball `padListPopulated.populated.png` — both items decrypted (plain text visible), the second showing its file chip; ciphertext-looking rows mean the fixture key path broke: STOP and fix the fixture (never loosen the view).

- [ ] **Step 5: Commit**

```bash
git add GrooTests/Features/Pad GrooTests/Features/Scratchpad
git commit -m "test: Pad + Scratchpad view render/snapshot suites + WebViewBridge unit tests"
```

---

### Task 6: Root Views fan-out (expected delta ≈ +1,000 covered lines) + second coverage checkpoint

**Files:**
- Create: `GrooTests/Views/RootViewSnapshotTests.swift`
- Create (by test run): `GrooTests/Views/__Snapshots__/RootViewSnapshotTests/*.png`

**Interfaces:**
- Consumes (recon-verified): `LoginView()` + REQUIRED `.environment(AuthService())`; `UnlockView(padService:syncService:onUnlock:onSignOut:)` + env `AuthService`; `GlobalLockView(padService:passService:onUnlock:onSignOut:)` (no env — but its `.onAppear` schedules a 0.3s-delayed biometric `unlockAll()`, which no-ops on the fakes and lands post-draw); `SettingsView(padService:passService:onSignOut:onLock:)` + env `AuthService` (its `.task` runs an `LAContext` availability check — `.none` on the un-enrolled pinned simulator — and a locked-vault backup-date read); `MainTabView(padService:syncService:passService:onSignOut:)` + env `AuthService`; `HomeView(padService:syncService:passService:)`. Config base-URL UserDefaults keys (the `UITestMode.activateIfNeeded` set): `padAPIBaseURL`, `passAPIBaseURL`, `accountsAPIBaseURL`, `ethereumRPCURL`, `blockscoutBaseURL`, `coinGeckoBaseURL` — pinned to `http://127.0.0.1:9` so HomeView/MainTabView refresh tasks fail fast in-process.
- Classification: **render-only** — `HomeView` and `MainTabView` (live prayer countdown + `LocalStore.shared` cached-portfolio reads). Snapshots for `LoginView`, `UnlockView`, `GlobalLockView`, `SettingsView`.

- [ ] **Step 1: Create `GrooTests/Views/RootViewSnapshotTests.swift`**

```swift
//
//  RootViewSnapshotTests.swift
//  GrooTests
//
//  Phase 7: root screens. AuthService is injected bare (constructible
//  without side effects — the preview pattern); Pad/Pass services are the
//  standard fakes; Config base URLs are pinned to a dead loopback port so
//  HomeView's refresh tasks fail fast without leaving the process.
//

import SnapshotTesting
import SwiftUI
import Testing
@testable import Groo

extension NetworkStubbedSuites {

@MainActor
@Suite(.serialized, .snapshots(record: .missing))
struct RootViewSnapshotTests {
    static let deadURLDefaults: [String: Any] = [
        "padAPIBaseURL": "http://127.0.0.1:9",
        "passAPIBaseURL": "http://127.0.0.1:9",
        "accountsAPIBaseURL": "http://127.0.0.1:9",
        "ethereumRPCURL": "http://127.0.0.1:9",
        "blockscoutBaseURL": "http://127.0.0.1:9",
        "coinGeckoBaseURL": "http://127.0.0.1:9",
        "displayCurrency": "USD",
        "selectedTab": "home",
    ]

    @Test func loginView() {
        assertViewSnapshot(of: LoginView().environment(AuthService()), named: "logged-out")
    }

    @Test func unlockView() throws {
        StubURLProtocol.reset()
        let (padService, store) = try PadViewSnapshotTests.lockedPadService()
        assertViewSnapshot(
            of: UnlockView(padService: padService,
                           syncService: PadViewSnapshotTests.offlineSync(store: store),
                           onUnlock: {}, onSignOut: {})
                .environment(AuthService()),
            named: "locked")
    }

    @Test func globalLockView() throws {
        StubURLProtocol.reset()
        let (padService, _) = try PadViewSnapshotTests.lockedPadService()
        let passEnv = try PassServiceIntegrationTests.makeEnv(items: [])
        defer { try? FileManager.default.removeItem(at: passEnv.tempDir) }
        // onAppear schedules unlockAll() at +0.3s — it runs against the
        // fakes AFTER the draw and cannot affect the committed image.
        assertViewSnapshot(
            of: GlobalLockView(padService: padService, passService: passEnv.service,
                               onUnlock: {}, onSignOut: {}),
            named: "locked")
    }

    @Test func settingsView() async throws {
        StubURLProtocol.reset()
        let (padService, _) = try PadViewSnapshotTests.lockedPadService()
        let passEnv = try PassServiceIntegrationTests.makeEnv(items: [])
        defer { try? FileManager.default.removeItem(at: passEnv.tempDir) }
        await withPinnedDefaults(Self.deadURLDefaults) {
            await assertSettledViewSnapshot(
                of: NavigationStack {
                    SettingsView(padService: padService, passService: passEnv.service,
                                 onSignOut: {}, onLock: {})
                }
                .environment(AuthService()),
                named: "default")
        }
    }

    @Test func homeViewRendersOnly() throws {
        StubURLProtocol.reset()
        let (padService, store) = try PadViewSnapshotTests.lockedPadService()
        let passEnv = try PassServiceIntegrationTests.makeEnv(items: [])
        defer { try? FileManager.default.removeItem(at: passEnv.tempDir) }
        withPinnedDefaults(Self.deadURLDefaults) {
            // Live prayer countdown + shared-store cache reads — render-only.
            ViewRender.assertRenders(
                HomeView(padService: padService,
                         syncService: PadViewSnapshotTests.offlineSync(store: store),
                         passService: passEnv.service))
        }
    }

    @Test func mainTabViewRendersOnly() throws {
        StubURLProtocol.reset()
        let (padService, store) = try PadViewSnapshotTests.lockedPadService()
        let passEnv = try PassServiceIntegrationTests.makeEnv(items: [])
        defer { try? FileManager.default.removeItem(at: passEnv.tempDir) }
        withPinnedDefaults(Self.deadURLDefaults) {
            ViewRender.assertRenders(
                MainTabView(padService: padService,
                            syncService: PadViewSnapshotTests.offlineSync(store: store),
                            passService: passEnv.service, onSignOut: {})
                    .environment(AuthService()))
        }
    }
}
}
```

(`settingsView`'s PNG includes the app version/build strings from `Bundle.main` — it re-records when the marketing version changes; acceptable, the README procedure covers it. If `SettingsView`'s snapshot shows a spinner from the backup-date task, treat like the Task 2 health case: raise yields once, else downgrade to `assertSettledRenders` + report.)

- [ ] **Step 2: The two-run cycle + COVERAGE CHECKPOINT**

Run once (records 4 PNGs), then twice green: **397 tests** (391 + 6).

Run: `bash scripts/test.sh --unit --coverage 2>&1 | tail -60`
**Expected Groo.app ≥ ~74%** (cumulative estimate ≈ 76%, minus slack). Record actual. If < 72%: per-file diff against the pool tables and expand states NOW (see the Task 9 gap menu for the ranked levers) before Task 7 — Task 7/8 only add ~1,200 more, so a big hole here cannot be closed later.

- [ ] **Step 3: Commit**

```bash
git add GrooTests/Views
git commit -m "test: root view render/snapshot suite (login, unlock, global lock, settings; home/tabs render-only)"
```

---

### Task 7: System-service protocol seams + service tests (TDD; expected delta ≈ +620 covered lines)

**Files:**
- Create: `Groo/Core/Notifications/NotificationScheduling.swift`
- Create: `Groo/Features/Azan/Services/AudioPlaying.swift`
- Create: `Groo/Features/Azan/Services/LocationProviding.swift`
- Modify: `Groo/Features/Azan/Services/AzanNotificationService.swift`, `Groo/Core/Notifications/PushService.swift`, `Groo/Features/Azan/Services/AzanAudioService.swift`, `Groo/Features/Azan/Services/RecitationAudioService.swift`, `Groo/Features/Azan/Services/AzanLocationService.swift`, `Groo/Features/Pad/PadService.swift`
- Create: `GrooTests/Support/SystemServiceFakes.swift`
- Create: `GrooTests/Features/Azan/AzanNotificationServiceTests.swift`, `GrooTests/Features/Azan/AzanAudioServiceTests.swift`, `GrooTests/Features/Azan/RecitationAudioServiceTests.swift`, `GrooTests/Features/Azan/AzanLocationServiceTests.swift`, `GrooTests/Core/PushServiceTests.swift`, `GrooTests/Core/KeychainServiceTests.swift`
- Modify: `GrooTests/Features/Pad/PadServiceTests.swift` (append the kdf-iterations unlock tests)

**Interfaces:**
- Consumes: the verbatim service sources below (all read during planning recon — the "Replace/With" pairs are against the current files); `KeychainServicing` precedent for the protocol shape; `PrayerTimeServiceTests.makeService(nowAt:)`; `LocalAzanPreferences(jumuahReminderEnabled:)` memberwise; `PadServiceTests` suite conventions; `PrayerGuideDataProvider.shortSurahs()` (a real bundled audio file name); `YahooFinanceServiceTests`-style stub JSON.
- Produces (all default-parameter, production behavior identical):
  - `NotificationScheduling` (+ `UNUserNotificationCenter` conformance), consumed by `AzanNotificationService(center:)` and `PushService(center:…)`
  - `AudioPlaying`/`AudioSessionControlling` (+ `AVAudioPlayer`/`SystemAudioSession`), consumed by `AzanAudioService(makePlayer:audioSession:)` and `RecitationAudioService(makePlayer:audioSession:)` (whose `private init` becomes internal; `static let shared` unchanged)
  - `LocationProviding` (+ `CLLocationManager` conformance) and an injectable `geocodeName` closure, consumed by `AzanLocationService(manager:geocodeName:)`
  - `PushTokenProviding` (`accessToken`/`forceRefresh`; `AuthService` conforms as-is) + injected `URLSession` + injected `registerForRemoteNotifications` closure on `PushService`
  - `PadService(api:crypto:keychain:store:kdfIterations:)` with default `600_000`
- Approved micro-deviations to flag in the report: (a) `PushService.requestAuthorization` drops its redundant `await MainActor.run` (class is `@MainActor`); (b) `AzanLocationService.reverseGeocode` no longer sets `locationName = ""` when a placemark has neither city nor country (previously possible; empty-string names were meaningless); (c) `AzanLocationService`'s `notDetermined` 1s-sleep branch stays untested (no-sleeps rule).

- [ ] **Step 1: Write the fakes + tests first (RED — they do not compile until Step 2's seams land)**

Create `GrooTests/Support/SystemServiceFakes.swift`:

```swift
//
//  SystemServiceFakes.swift
//  GrooTests
//
//  Phase 7 fakes for the system-service seams: notification center, audio
//  player/session, location manager. Lock-guarded like InMemoryKeychain so
//  the sync protocol requirements are satisfiable off the main actor.
//

import AVFoundation
import CoreLocation
import Foundation
import UserNotifications
@testable import Groo

final class FakeNotificationCenter: NotificationScheduling, @unchecked Sendable {
    private let lock = NSLock()
    var authorizationResult: Result<Bool, any Error> = .success(true)
    var status: UNAuthorizationStatus = .authorized

    private var _added: [UNNotificationRequest] = []
    private var _pending: [UNNotificationRequest] = []
    private var _removedIdentifiers: [[String]] = []
    private var _categories: [Set<UNNotificationCategory>] = []

    var added: [UNNotificationRequest] { lock.withLock { _added } }
    var pending: [UNNotificationRequest] { lock.withLock { _pending } }
    var removedIdentifiers: [[String]] { lock.withLock { _removedIdentifiers } }
    var categories: [Set<UNNotificationCategory>] { lock.withLock { _categories } }

    func seedPending(_ requests: [UNNotificationRequest]) {
        lock.withLock { _pending.append(contentsOf: requests) }
    }

    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        try authorizationResult.get()
    }

    func authorizationStatus() async -> UNAuthorizationStatus { status }

    func setNotificationCategories(_ categories: Set<UNNotificationCategory>) {
        lock.withLock { _categories.append(categories) }
    }

    func add(_ request: UNNotificationRequest) async throws {
        lock.withLock { _added.append(request); _pending.append(request) }
    }

    func pendingNotificationRequests() async -> [UNNotificationRequest] {
        lock.withLock { _pending }
    }

    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
        lock.withLock {
            _removedIdentifiers.append(identifiers)
            _pending.removeAll { identifiers.contains($0.identifier) }
        }
    }
}

final class FakeAudioPlayer: AudioPlaying {
    let url: URL
    var stubbedIsPlaying = true
    var duration: TimeInterval = 100
    var currentTime: TimeInterval = 25
    weak var delegate: AVAudioPlayerDelegate?
    private(set) var prepareCount = 0
    private(set) var playCount = 0
    private(set) var stopCount = 0

    init(url: URL) { self.url = url }

    var isPlaying: Bool { stubbedIsPlaying }

    @discardableResult func prepareToPlay() -> Bool { prepareCount += 1; return true }
    @discardableResult func play() -> Bool { playCount += 1; return true }
    func stop() { stopCount += 1; stubbedIsPlaying = false }
}

@MainActor
final class AudioPlayerRecorder {
    private(set) var players: [FakeAudioPlayer] = []
    var creationError: (any Error)?

    func make(_ url: URL) throws -> any AudioPlaying {
        if let creationError { throw creationError }
        let player = FakeAudioPlayer(url: url)
        players.append(player)
        return player
    }
}

final class RecordingAudioSession: AudioSessionControlling, @unchecked Sendable {
    private let lock = NSLock()
    private var _activations = 0
    private var _deactivations = 0
    var activationError: (any Error)?
    var activations: Int { lock.withLock { _activations } }
    var deactivations: Int { lock.withLock { _deactivations } }

    func activatePlayback() throws {
        lock.withLock { _activations += 1 }
        if let activationError { throw activationError }
    }

    func deactivate() { lock.withLock { _deactivations += 1 } }
}

final class FakeLocationManager: LocationProviding {
    weak var delegate: CLLocationManagerDelegate?
    var desiredAccuracy: CLLocationAccuracy = 0
    var authorizationStatus: CLAuthorizationStatus = .authorizedWhenInUse
    private(set) var didRequestAuthorization = false
    private(set) var didRequestLocation = false
    /// Test hook: invoked synchronously from requestLocation so the test can
    /// drive the delegate callbacks (success or failure).
    var onRequestLocation: () -> Void = {}

    func requestWhenInUseAuthorization() { didRequestAuthorization = true }
    func requestLocation() { didRequestLocation = true; onRequestLocation() }
}
```

Create `GrooTests/Features/Azan/AzanNotificationServiceTests.swift`:

```swift
//
//  AzanNotificationServiceTests.swift
//  GrooTests
//
//  Authorization-state and scheduling logic over the NotificationScheduling
//  seam. The service compares prayer times against the real clock, so
//  scheduling tests assert INVARIANTS (azan_ ids, future triggers, count
//  bookkeeping, denied-auth preservation) — never absolute schedules.
//

import Foundation
import Testing
import UserNotifications
@testable import Groo

@MainActor
struct AzanNotificationServiceTests {
    static func request(id: String) -> UNNotificationRequest {
        UNNotificationRequest(identifier: id, content: UNMutableNotificationContent(), trigger: nil)
    }

    /// Real-clock Dubai prayer service: some times today are already past,
    /// some are future — exactly what the invariants need.
    static func prayerService() -> PrayerTimeService {
        PrayerTimeServiceTests.makeService(nowAt: Date())
    }

    @Test func requestAuthorizationGrantedSetsFlags() async {
        let center = FakeNotificationCenter()
        let service = AzanNotificationService(center: center)
        #expect(await service.requestAuthorization())
        #expect(service.isAuthorized)
        #expect(!service.authorizationDenied)
    }

    @Test func requestAuthorizationDeniedSetsDeniedFlag() async {
        let center = FakeNotificationCenter()
        center.authorizationResult = .success(false)
        let service = AzanNotificationService(center: center)
        #expect(!(await service.requestAuthorization()))
        #expect(!service.isAuthorized)
        #expect(service.authorizationDenied)
    }

    @Test func requestAuthorizationErrorIsNotADenial() async {
        struct Boom: Error {}
        let center = FakeNotificationCenter()
        center.authorizationResult = .failure(Boom())
        let service = AzanNotificationService(center: center)
        #expect(!(await service.requestAuthorization()))
        #expect(!service.authorizationDenied)   // errored ≠ user denied
    }

    @Test(arguments: [
        (UNAuthorizationStatus.authorized, true, false),
        (UNAuthorizationStatus.denied, false, true),
        (UNAuthorizationStatus.notDetermined, false, false),
    ])
    func checkAuthorizationMapsStatus(_ fixture: (UNAuthorizationStatus, Bool, Bool)) async {
        let center = FakeNotificationCenter()
        center.status = fixture.0
        let service = AzanNotificationService(center: center)
        await service.checkAuthorization()
        #expect(service.isAuthorized == fixture.1)
        #expect(service.authorizationDenied == fixture.2)
    }

    @Test func registerCategoryRegistersAzanPrayer() {
        let center = FakeNotificationCenter()
        let service = AzanNotificationService(center: center)
        service.registerCategory()
        #expect(center.categories.count == 1)
        #expect(center.categories.first?.contains { $0.identifier == "AZAN_PRAYER" } == true)
    }

    @Test func deniedAuthorizationSchedulesNothingAndWipesNothing() async {
        let center = FakeNotificationCenter()
        center.status = .denied
        center.authorizationResult = .success(false)
        center.seedPending([Self.request(id: "azan_fajr_123")])
        let service = AzanNotificationService(center: center)

        await service.scheduleNotifications(prayerService: Self.prayerService(),
                                            preferences: LocalAzanPreferences())

        #expect(center.added.isEmpty)
        #expect(center.removedIdentifiers.isEmpty, "a denied request must never wipe existing notifications")
        #expect(center.pending.map(\.identifier) == ["azan_fajr_123"])
    }

    @Test func schedulingInvariantsHold() async throws {
        let center = FakeNotificationCenter()
        center.seedPending([Self.request(id: "azan_stale_1"), Self.request(id: "other_app_id")])
        let service = AzanNotificationService(center: center)

        await service.scheduleNotifications(prayerService: Self.prayerService(),
                                            preferences: LocalAzanPreferences())

        #expect(!center.added.isEmpty, "12 days ahead always yields future prayers")
        for request in center.added {
            #expect(request.identifier.hasPrefix("azan_"), "foreign id scheduled: \(request.identifier)")
            let trigger = try #require(request.trigger as? UNCalendarNotificationTrigger)
            let fireDate = try #require(trigger.nextTriggerDate())
            #expect(fireDate > Date(), "past trigger scheduled: \(request.identifier)")
        }
        #expect(center.added.count <= 60, "maxNotifications cap violated")
        #expect(service.pendingCount == center.added.count)
        // The stale azan_ id was wiped, the foreign id preserved
        let removed = center.removedIdentifiers.flatMap { $0 }
        #expect(removed.contains("azan_stale_1"))
        #expect(!removed.contains("other_app_id"))
    }

    @Test func jumuahReminderScheduledWhenEnabled() async {
        let center = FakeNotificationCenter()
        let service = AzanNotificationService(center: center)

        await service.scheduleNotifications(
            prayerService: Self.prayerService(),
            preferences: LocalAzanPreferences(jumuahReminderEnabled: true))

        #expect(center.added.contains { $0.identifier.hasPrefix("azan_jumuah_") },
                "there is always a future Friday inside the 12-day window")
    }

    @Test func updatePendingCountCountsOnlyAzanIds() async {
        let center = FakeNotificationCenter()
        center.seedPending([Self.request(id: "azan_a"), Self.request(id: "azan_b"),
                            Self.request(id: "other")])
        let service = AzanNotificationService(center: center)
        await service.updatePendingCount()
        #expect(service.pendingCount == 2)
        await service.removeAllAzanNotifications()
        #expect(service.pendingCount == 0)
        #expect(center.pending.map(\.identifier) == ["other"])
    }
}
```

Create `GrooTests/Features/Azan/AzanAudioServiceTests.swift`:

```swift
//
//  AzanAudioServiceTests.swift
//  GrooTests
//
//  Playback selection/looping state over the AudioPlaying seam — no real
//  audio, no real audio session. File lookup runs against the host app
//  bundle (azan sound files ship with the app).
//

import Foundation
import Testing
@testable import Groo

@MainActor
struct AzanAudioServiceTests {
    static func makeService() -> (service: AzanAudioService, players: AudioPlayerRecorder, session: RecordingAudioSession) {
        let players = AudioPlayerRecorder()
        let session = RecordingAudioSession()
        let service = AzanAudioService(makePlayer: { try players.make($0) }, audioSession: session)
        return (service, players, session)
    }

    @Test func playFullAzanStartsPlayerAndSetsState() throws {
        let (service, players, session) = Self.makeService()
        service.playFullAzan(for: .dhuhr)
        #expect(service.isPlaying)
        #expect(service.currentPrayer == .dhuhr)
        #expect(session.activations == 1)
        let player = try #require(players.players.first)
        #expect(player.playCount == 1 && player.prepareCount == 1)
        #expect(player.url.lastPathComponent.hasPrefix("azan_full"),
                "default non-fajr sound is azan_full.*: \(player.url.lastPathComponent)")
    }

    @Test func fajrUsesFajrSound() throws {
        let (service, players, _) = Self.makeService()
        service.playFullAzan(for: .fajr)
        let player = try #require(players.players.first)
        #expect(player.url.lastPathComponent.hasPrefix("azan_fajr"))
    }

    @Test func missingSoundFallsBackToAzanFull() throws {
        let (service, players, _) = Self.makeService()
        service.playFullAzan(for: .dhuhr, soundName: "definitely-not-bundled-xyz")
        let player = try #require(players.players.first)
        #expect(player.url.lastPathComponent.hasPrefix("azan_full"))
    }

    @Test func stopResetsStateAndDeactivatesSession() throws {
        let (service, players, session) = Self.makeService()
        service.playFullAzan(for: .isha)
        service.stopAzan()
        #expect(!service.isPlaying)
        #expect(service.currentPrayer == nil)
        #expect(service.playbackProgress == 0)
        #expect(try #require(players.players.first).stopCount >= 1)
        #expect(session.deactivations == 1)
    }

    @Test func togglePlaybackFlips() {
        let (service, _, _) = Self.makeService()
        service.togglePlayback(for: .asr)
        #expect(service.isPlaying)
        service.togglePlayback(for: .asr)
        #expect(!service.isPlaying)
    }

    @Test func playerCreationFailureLeavesStopped() {
        struct Boom: Error {}
        let (service, players, _) = Self.makeService()
        players.creationError = Boom()
        service.playFullAzan(for: .dhuhr)
        #expect(!service.isPlaying)
        #expect(service.currentPrayer == nil)
    }

    @Test func sessionActivationFailureStillPlays() {
        struct Boom: Error {}
        let (service, players, session) = Self.makeService()
        session.activationError = Boom()
        service.playFullAzan(for: .dhuhr)
        // Log-and-continue contract: playback proceeds on the default session
        #expect(service.isPlaying)
        #expect(players.players.count == 1)
    }

    @Test func displayNames() {
        #expect(AzanAudioService.displayName(for: "default") == "Default")
        #expect(AzanAudioService.displayName(for: "mishary-rashid-alafasy") == "Mishary Rashid Alafasy")
        #expect(AzanAudioService.displayName(for: "unknown-sound") == "unknown-sound")
    }
}
```

If `playFullAzanStartsPlayerAndSetsState` fails because no `azan_full.*` file resolves from the host bundle, list the bundled azan files (`ls azan-audio-files/`, and check the app target's resources) and pin the expected basename accordingly — do NOT delete the assertion.

Create `GrooTests/Features/Azan/RecitationAudioServiceTests.swift`:

```swift
//
//  RecitationAudioServiceTests.swift
//  GrooTests
//
//  Toggle/stop/error state over the AudioPlaying seam, on isolated
//  instances (the production singleton keeps its real defaults).
//

import AVFoundation
import Foundation
import Testing
@testable import Groo

@MainActor
struct RecitationAudioServiceTests {
    /// A file name guaranteed bundled: the first short surah's audio.
    static func bundledFileName() throws -> String {
        try #require(PrayerGuideDataProvider.shortSurahs().first).audioFileName
    }

    static func makeService() -> (service: RecitationAudioService, players: AudioPlayerRecorder, session: RecordingAudioSession) {
        let players = AudioPlayerRecorder()
        let session = RecordingAudioSession()
        let service = RecitationAudioService(makePlayer: { try players.make($0) }, audioSession: session)
        return (service, players, session)
    }

    @Test func playSetsStateAndCreatesPlayer() throws {
        let (service, players, session) = Self.makeService()
        let file = try Self.bundledFileName()
        service.play(file)
        #expect(service.isPlaying)
        #expect(service.currentFile == file)
        #expect(service.isCurrentlyPlaying(file))
        #expect(service.lastError == nil)
        #expect(session.activations == 1)
        #expect(players.players.count == 1)
    }

    @Test func playSameFileTogglesOff() throws {
        let (service, _, _) = Self.makeService()
        let file = try Self.bundledFileName()
        service.play(file)
        service.play(file)
        #expect(!service.isPlaying)
        #expect(service.currentFile == nil)
    }

    @Test func missingFileSetsLastError() {
        let (service, players, _) = Self.makeService()
        service.play("definitely-not-bundled-xyz")
        #expect(!service.isPlaying)
        #expect(service.lastError == "Audio unavailable for this recitation")
        #expect(players.players.isEmpty)
    }

    @Test func delegateFinishAutoStops() async throws {
        let (service, players, _) = Self.makeService()
        let file = try Self.bundledFileName()
        service.play(file)
        let player = try #require(players.players.first)
        let delegate = try #require(player.delegate)
        // The delegate's onFinish hops to the main actor via Task — yield for it.
        let url = try #require(Bundle.main.url(forResource: file, withExtension: "mp3"))
        let dummyPlayer = try AVAudioPlayer(contentsOf: url)
        delegate.audioPlayerDidFinishPlaying?(dummyPlayer, successfully: true)
        for _ in 0..<4 { await Task.yield() }
        #expect(!service.isPlaying)
        #expect(service.currentFile == nil)
    }

    @Test func creationFailureSetsError() throws {
        struct Boom: Error {}
        let (service, players, _) = Self.makeService()
        players.creationError = Boom()
        service.play(try Self.bundledFileName())
        #expect(!service.isPlaying)
        #expect(service.lastError == "Couldn't play audio")
    }
}
```

Create `GrooTests/Features/Azan/AzanLocationServiceTests.swift`:

```swift
//
//  AzanLocationServiceTests.swift
//  GrooTests
//
//  Authorization flow + coordinate handoff over the LocationProviding seam.
//  Delegate callbacks are driven with a throwaway CLLocationManager (its
//  construction is side-effect free). The notDetermined branch (production
//  1s sleep) is deliberately untested — no-sleeps rule.
//

import CoreLocation
import Foundation
import Testing
@testable import Groo

@MainActor
struct AzanLocationServiceTests {
    @Test func initConfiguresManagerAndReadsStatus() {
        let manager = FakeLocationManager()
        manager.authorizationStatus = .denied
        let service = AzanLocationService(manager: manager, geocodeName: { _ in nil })
        #expect(service.authorizationStatus == .denied)
        #expect(manager.delegate === service)
        #expect(manager.desiredAccuracy == kCLLocationAccuracyKilometer)
        #expect(!service.hasLocation)
    }

    @Test func requestLocationSuccessSetsCoordinatesAndGeocodedName() async {
        let manager = FakeLocationManager()
        let service = AzanLocationService(manager: manager, geocodeName: { _ in "Dubai, United Arab Emirates" })
        manager.onRequestLocation = { [weak manager] in
            manager?.delegate?.locationManager?(
                CLLocationManager(), didUpdateLocations: [CLLocation(latitude: 25.2048, longitude: 55.2708)])
        }

        await service.requestLocation()

        #expect(service.latitude == 25.2048)
        #expect(service.longitude == 55.2708)
        #expect(service.locationName == "Dubai, United Arab Emirates")
        #expect(service.error == nil)
        #expect(!service.isLoading)
        #expect(manager.didRequestLocation)
        #expect(!manager.didRequestAuthorization, "already authorized — no auth prompt")
    }

    @Test func requestLocationDeniedSetsSettingsError() async {
        let manager = FakeLocationManager()
        manager.authorizationStatus = .denied
        let service = AzanLocationService(manager: manager, geocodeName: { _ in nil })

        await service.requestLocation()

        #expect(service.error == "Location access denied — enable in Settings")
        #expect(!manager.didRequestLocation)
    }

    @Test func clNetworkErrorMapsToFriendlyMessage() async {
        let manager = FakeLocationManager()
        let service = AzanLocationService(manager: manager, geocodeName: { _ in nil })
        manager.onRequestLocation = { [weak manager] in
            manager?.delegate?.locationManager?(
                CLLocationManager(), didFailWithError: CLError(.network))
        }

        await service.requestLocation()

        #expect(service.error == "Network error while getting location — check your connection")
        #expect(!service.hasLocation)
    }

    @Test func geocodeFailureFallsBackToCoordinateString() async {
        struct Boom: Error {}
        let manager = FakeLocationManager()
        let service = AzanLocationService(manager: manager, geocodeName: { _ in throw Boom() })
        manager.onRequestLocation = { [weak manager] in
            manager?.delegate?.locationManager?(
                CLLocationManager(), didUpdateLocations: [CLLocation(latitude: 25.2048, longitude: 55.2708)])
        }

        await service.requestLocation()

        #expect(service.locationName == "25.20, 55.27")
    }

    @Test func setManualLocationClearsError() {
        let service = AzanLocationService(manager: FakeLocationManager(), geocodeName: { _ in nil })
        service.setManualLocation(latitude: 51.5074, longitude: -0.1278, name: "London")
        #expect(service.latitude == 51.5074)
        #expect(service.locationName == "London")
        #expect(service.error == nil)
        #expect(service.hasLocation)
    }

    @Test func authorizationChangeCallbackUpdatesStatus() async {
        let manager = FakeLocationManager()
        let service = AzanLocationService(manager: manager, geocodeName: { _ in nil })
        // The delegate hop reads the REAL manager's status — a fresh
        // CLLocationManager reports .notDetermined on a clean simulator.
        service.locationManagerDidChangeAuthorization(CLLocationManager())
        for _ in 0..<4 { await Task.yield() }
        #expect(service.authorizationStatus == CLLocationManager().authorizationStatus)
    }
}
```

Create `GrooTests/Core/PushServiceTests.swift`:

```swift
//
//  PushServiceTests.swift
//  GrooTests
//
//  APNs registration flows over the NotificationScheduling + keychain +
//  session + token seams: authorization, register (incl. the single
//  401-refresh retry), unregister, and notification routing.
//

import Foundation
import Testing
@testable import Groo

@MainActor
final class FakePushTokens: PushTokenProviding {
    var current = "tok-1"
    var refreshed = "tok-2"
    private(set) var refreshCount = 0
    func accessToken() async throws -> String { current }
    func forceRefresh() async throws -> String { refreshCount += 1; return refreshed }
}

extension NetworkStubbedSuites {

@MainActor
@Suite(.serialized)
struct PushServiceTests {
    static let tokenData = Data([0xCA, 0xFE, 0xBA, 0xBE])

    struct Env {
        let service: PushService
        let center: FakeNotificationCenter
        let keychain: InMemoryKeychain
        let tokens: FakePushTokens
        let registerCalls: () -> Int
    }

    static func makeEnv(authorize: Bool = true) -> Env {
        StubURLProtocol.reset()
        let center = FakeNotificationCenter()
        center.authorizationResult = .success(authorize)
        let keychain = InMemoryKeychain()
        var registerCount = 0
        let service = PushService(
            center: center, keychain: keychain,
            sessionConfiguration: StubURLProtocol.stubbedConfiguration(),
            registerForRemoteNotifications: { registerCount += 1 })
        let tokens = FakePushTokens()
        service.authService = tokens
        return Env(service: service, center: center, keychain: keychain,
                   tokens: tokens, registerCalls: { registerCount })
    }

    @Test func initLoadsCachedTokenFromKeychain() throws {
        StubURLProtocol.reset()
        let keychain = InMemoryKeychain()
        try keychain.save("cafebabe", for: KeychainService.Key.deviceToken)
        let service = PushService(center: FakeNotificationCenter(), keychain: keychain,
                                  sessionConfiguration: StubURLProtocol.stubbedConfiguration(),
                                  registerForRemoteNotifications: {})
        #expect(service.deviceToken == "cafebabe")
        #expect(service.isRegistered)
    }

    @Test func grantedAuthorizationTriggersRemoteRegistration() async throws {
        let env = Self.makeEnv(authorize: true)
        #expect(try await env.service.requestAuthorization())
        #expect(env.registerCalls() == 1)
    }

    @Test func deniedAuthorizationDoesNotRegister() async throws {
        let env = Self.makeEnv(authorize: false)
        #expect(!(try await env.service.requestAuthorization()))
        #expect(env.registerCalls() == 0)
    }

    @Test func registerDeviceTokenPostsAndCaches() async throws {
        let env = Self.makeEnv()
        StubURLProtocol.enqueue(method: "POST", pathSuffix: "/v1/devices", json: #"{"ok":true}"#)

        try await env.service.registerDeviceToken(Self.tokenData)

        #expect(env.service.deviceToken == "cafebabe")
        #expect(env.service.isRegistered)
        #expect(try env.keychain.loadString(for: KeychainService.Key.deviceToken) == "cafebabe")
        let request = try #require(StubURLProtocol.recordedRequests.first)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer tok-1")
    }

    @Test func registerRetriesExactlyOnceOn401() async throws {
        let env = Self.makeEnv()
        StubURLProtocol.enqueue(method: "POST", pathSuffix: "/v1/devices", status: 401, json: "{}")
        StubURLProtocol.enqueue(method: "POST", pathSuffix: "/v1/devices", json: #"{"ok":true}"#)

        try await env.service.registerDeviceToken(Self.tokenData)

        #expect(env.tokens.refreshCount == 1)
        #expect(StubURLProtocol.recordedRequests.count == 2)
        #expect(StubURLProtocol.recordedRequests.last?.value(forHTTPHeaderField: "Authorization") == "Bearer tok-2")
        #expect(env.service.isRegistered)
    }

    @Test func registerFailureThrowsRegistrationFailed() async {
        let env = Self.makeEnv()
        StubURLProtocol.enqueue(method: "POST", pathSuffix: "/v1/devices", status: 500, json: "{}")

        await #expect(throws: PushError.self) {
            try await env.service.registerDeviceToken(Self.tokenData)
        }
    }

    @Test func unregisterClearsLocalStateEvenWithoutAuth() async throws {
        let env = Self.makeEnv()
        StubURLProtocol.enqueue(method: "POST", pathSuffix: "/v1/devices", json: #"{"ok":true}"#)
        try await env.service.registerDeviceToken(Self.tokenData)
        env.service.authService = nil   // no auth → local clear only

        try await env.service.unregisterDeviceToken()

        #expect(env.service.deviceToken == nil)
        #expect(!env.service.isRegistered)
        #expect(!env.keychain.exists(for: KeychainService.Key.deviceToken))
    }

    @Test func handleRemoteNotificationRoutesSyncAction() {
        let env = Self.makeEnv()
        var syncs = 0
        env.service.onSyncRequested = { syncs += 1 }
        env.service.handleRemoteNotification(["action": "sync"])
        env.service.handleRemoteNotification(["action": "other"])
        env.service.handleRemoteNotification([:])
        #expect(syncs == 1)
    }

    @Test func handleRegistrationFailureSurfacesError() {
        struct Boom: Error, LocalizedError { var errorDescription: String? { "boom" } }
        let env = Self.makeEnv()
        env.service.handleRegistrationFailure(Boom())
        #expect(env.service.lastRegistrationError == "boom")
        #expect(!env.service.isRegistered)
    }
}
}
```

Create `GrooTests/Core/KeychainServiceTests.swift` (real Security-framework roundtrips — they work in the hosted test app; biometric variants need enrolled biometry and stay excluded):

```swift
//
//  KeychainServiceTests.swift
//  GrooTests
//
//  Plain-item roundtrips against the real keychain in the hosted app
//  (unique per-test keys, always cleaned up). Biometric-protected paths
//  need enrolled biometry — deliberately untested (stable exclusion list).
//

import Foundation
import Testing
@testable import Groo

@MainActor
struct KeychainServiceTests {
    static func uniqueKey() -> String { "test.p7.\(UUID().uuidString)" }

    @Test func stringRoundtripAndOverwrite() throws {
        let keychain = KeychainService()
        let key = Self.uniqueKey()
        defer { try? keychain.delete(for: key) }

        try keychain.save("first", for: key)
        #expect(try keychain.loadString(for: key) == "first")
        try keychain.save("second", for: key)
        #expect(try keychain.loadString(for: key) == "second")
        #expect(keychain.exists(for: key))
    }

    @Test func dataRoundtrip() throws {
        let keychain = KeychainService()
        let key = Self.uniqueKey()
        defer { try? keychain.delete(for: key) }

        let blob = Data((0..<64).map { UInt8($0) })
        try keychain.save(blob, for: key)
        #expect(try keychain.load(for: key) == blob)
    }

    @Test func deleteRemovesItem() throws {
        let keychain = KeychainService()
        let key = Self.uniqueKey()
        try keychain.save("gone", for: key)
        try keychain.delete(for: key)
        #expect(!keychain.exists(for: key))
    }

    @Test func loadMissingKeyThrows() {
        let keychain = KeychainService()
        #expect(throws: (any Error).self) {
            _ = try keychain.loadString(for: Self.uniqueKey())
        }
    }
}
```

Append to `GrooTests/Features/Pad/PadServiceTests.swift` (inside the suite, after the last existing test):

```swift

    // MARK: - Password unlock at injected KDF iterations (Phase 7 seam)

    /// Builds the GET /v1/state payload PadService.unlock expects, with the
    /// salt + encryption-test blob derived at 1k iterations (vault-test rule).
    static func stubStateForUnlock(password: String, iterations: UInt32) throws -> SymmetricKey {
        let crypto = CryptoService()
        let salt = Data("pad-unlock-salt-0123456789abcdef".utf8)
        let key = try crypto.deriveKey(password: password, salt: salt, iterations: iterations)
        let combined = try crypto.encryptData(Data("groo-encryption-test".utf8), using: key)
        let test = PadEncryptedPayload(
            ciphertext: combined.dropFirst(12).base64EncodedString(),
            iv: combined.prefix(12).base64EncodedString(), version: 1)
        let testJSON = String(decoding: try JSONEncoder().encode(test), as: UTF8.self)
        StubURLProtocol.enqueue(method: "GET", pathSuffix: "/v1/state", json:
            #"{"activeId":"pad-1","scratchpads":{},"list":[],"encryptionSalt":"\#(salt.base64EncodedString())","encryptionTest":\#(testJSON)}"#)
        return key
    }

    static func makeLockedService(kdfIterations: UInt32) throws -> (service: PadService, keychain: InMemoryKeychain) {
        let keychain = InMemoryKeychain()
        let service = PadService(
            api: APIClient(baseURL: URL(string: "https://pad.test")!,
                           sessionConfiguration: StubURLProtocol.stubbedConfiguration(),
                           tokenProvider: { "pad-token" }),
            keychain: keychain,
            store: try InMemoryLocalStore.make(),
            kdfIterations: kdfIterations)
        return (service, keychain)
    }

    @Test func passwordUnlockSucceedsAtInjectedIterations() async throws {
        StubURLProtocol.reset()
        _ = try Self.stubStateForUnlock(password: "pad-master", iterations: 1_000)
        let (service, keychain) = try Self.makeLockedService(kdfIterations: 1_000)

        #expect(try await service.unlock(password: "pad-master"))
        #expect(service.isUnlocked)
        #expect(keychain.biometricProtectedKeyExists(for: KeychainService.Key.padEncryptionKey),
                "unlock must store the key for the extensions")
    }

    @Test func wrongPasswordFailsVerificationWithoutUnlocking() async throws {
        StubURLProtocol.reset()
        _ = try Self.stubStateForUnlock(password: "pad-master", iterations: 1_000)
        let (service, keychain) = try Self.makeLockedService(kdfIterations: 1_000)

        #expect(!(try await service.unlock(password: "wrong-password")))
        #expect(!service.isUnlocked)
        #expect(!keychain.biometricProtectedKeyExists(for: KeychainService.Key.padEncryptionKey))
    }
```

Run: `bash scripts/test.sh --unit 2>&1 | tail -5`
Expected: **FAIL to compile** (no `NotificationScheduling`, no seamed inits). That is the red step.

- [ ] **Step 2: The seams (GREEN — all default-parameter, production wiring untouched)**

(a) Create `Groo/Core/Notifications/NotificationScheduling.swift`:

```swift
//
//  NotificationScheduling.swift
//  Groo
//
//  Phase 7 seam over UNUserNotificationCenter (the KeychainServicing
//  pattern): AzanNotificationService and PushService talk to this protocol;
//  production injects the real center, tests inject a recording fake.
//  UNNotificationSettings has no public initializer, so the protocol
//  exposes the one scalar the services actually read (authorizationStatus).
//

import UserNotifications

protocol NotificationScheduling: AnyObject {
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool
    func authorizationStatus() async -> UNAuthorizationStatus
    func setNotificationCategories(_ categories: Set<UNNotificationCategory>)
    func add(_ request: UNNotificationRequest) async throws
    func pendingNotificationRequests() async -> [UNNotificationRequest]
    func removePendingNotificationRequests(withIdentifiers identifiers: [String])
}

extension UNUserNotificationCenter: NotificationScheduling {
    func authorizationStatus() async -> UNAuthorizationStatus {
        await notificationSettings().authorizationStatus
    }
}
```

(b) Create `Groo/Features/Azan/Services/AudioPlaying.swift`:

```swift
//
//  AudioPlaying.swift
//  Groo
//
//  Phase 7 seams over AVAudioPlayer instances and the shared
//  AVAudioSession activate/deactivate pair. AVAudioPlayer conforms as-is.
//

import AVFoundation

protocol AudioPlaying: AnyObject {
    var isPlaying: Bool { get }
    var duration: TimeInterval { get }
    var currentTime: TimeInterval { get }
    var delegate: AVAudioPlayerDelegate? { get set }
    @discardableResult func prepareToPlay() -> Bool
    @discardableResult func play() -> Bool
    func stop()
}

extension AVAudioPlayer: AudioPlaying {}

protocol AudioSessionControlling {
    func activatePlayback() throws
    func deactivate()
}

struct SystemAudioSession: AudioSessionControlling {
    func activatePlayback() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default, options: [])
        try session.setActive(true)
    }

    func deactivate() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
```

(c) Create `Groo/Features/Azan/Services/LocationProviding.swift`:

```swift
//
//  LocationProviding.swift
//  Groo
//
//  Phase 7 seam over CLLocationManager. CLLocationManager conforms as-is.
//

import CoreLocation

protocol LocationProviding: AnyObject {
    var delegate: CLLocationManagerDelegate? { get set }
    var desiredAccuracy: CLLocationAccuracy { get set }
    var authorizationStatus: CLAuthorizationStatus { get }
    func requestWhenInUseAuthorization()
    func requestLocation()
}

extension CLLocationManager: LocationProviding {}
```

(d) In `Groo/Features/Azan/Services/AzanNotificationService.swift`, replace:

```swift
    private let center = UNUserNotificationCenter.current()
```

with:

```swift
    private let center: any NotificationScheduling

    /// Phase 7 seam: production talks to the real notification center.
    init(center: any NotificationScheduling = UNUserNotificationCenter.current()) {
        self.center = center
    }
```

and replace the body of `checkAuthorization()`:

```swift
    func checkAuthorization() async {
        let settings = await center.notificationSettings()
        isAuthorized = settings.authorizationStatus == .authorized
        authorizationDenied = settings.authorizationStatus == .denied
    }
```

with:

```swift
    func checkAuthorization() async {
        let status = await center.authorizationStatus()
        isAuthorized = status == .authorized
        authorizationDenied = status == .denied
    }
```

(every other `center.` call site — `requestAuthorization(options:)`, `setNotificationCategories`, `add`, `pendingNotificationRequests`, `removePendingNotificationRequests(withIdentifiers:)` — matches the protocol verbatim and compiles unchanged).

(e) In `Groo/Core/Notifications/PushService.swift`:

Add above `class PushService` (after the `DeviceRegistration` struct):

```swift
/// Phase 7 token seam for device registration. AuthService satisfies it as-is.
@MainActor
protocol PushTokenProviding: AnyObject {
    func accessToken() async throws -> String
    func forceRefresh() async throws -> String
}

extension AuthService: PushTokenProviding {}
```

Replace:

```swift
    private let keychain = KeychainService()

    /// Wired up by `GrooApp` after both services are constructed. Used to obtain
    /// the OAuth access token for device registration requests.
    weak var authService: AuthService?

    // Callback for when a sync notification is received
    var onSyncRequested: (() -> Void)?

    init() {
        // Load cached token
        deviceToken = try? keychain.loadString(for: KeychainService.Key.deviceToken)
        isRegistered = deviceToken != nil
    }
```

with:

```swift
    private let keychain: any KeychainServicing
    private let center: any NotificationScheduling
    private let session: URLSession
    private let registerForRemoteNotifications: @MainActor () -> Void

    /// Wired up by `GrooApp` after both services are constructed. Used to obtain
    /// the OAuth access token for device registration requests.
    weak var authService: (any PushTokenProviding)?

    // Callback for when a sync notification is received
    var onSyncRequested: (() -> Void)?

    /// Phase 7 seams (all production defaults — behavior unchanged).
    init(
        center: any NotificationScheduling = UNUserNotificationCenter.current(),
        keychain: any KeychainServicing = KeychainService(),
        sessionConfiguration: URLSessionConfiguration = .default,
        registerForRemoteNotifications: @escaping @MainActor () -> Void = {
            UIApplication.shared.registerForRemoteNotifications()
        }
    ) {
        self.center = center
        self.keychain = keychain
        self.session = URLSession(configuration: sessionConfiguration)
        self.registerForRemoteNotifications = registerForRemoteNotifications
        // Load cached token
        deviceToken = try? keychain.loadString(for: KeychainService.Key.deviceToken)
        isRegistered = deviceToken != nil
    }
```

Replace the whole `requestAuthorization()`:

```swift
    func requestAuthorization() async throws -> Bool {
        let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])

        if granted {
            // PushService is @MainActor — the previous MainActor.run hop was
            // redundant; the injected closure defaults to UIApplication.
            registerForRemoteNotifications()
        }

        return granted
    }
```

And in BOTH `registerDeviceToken` and `unregisterDeviceToken`, replace `URLSession.shared.data(for: request)` with `session.data(for: request)` (two sites — `grep -n 'URLSession.shared' Groo/Core/Notifications/PushService.swift` must return nothing afterwards).

(f) In `Groo/Features/Azan/Services/AzanAudioService.swift`, replace:

```swift
    private var audioPlayer: AVAudioPlayer?
    private var progressTimer: Timer?
```

with:

```swift
    private var audioPlayer: (any AudioPlaying)?
    private var progressTimer: Timer?

    private let makePlayer: (URL) throws -> any AudioPlaying
    private let audioSession: any AudioSessionControlling

    /// Phase 7 seams: production plays real AVAudioPlayers on the shared session.
    init(
        makePlayer: @escaping (URL) throws -> any AudioPlaying = { try AVAudioPlayer(contentsOf: $0) },
        audioSession: any AudioSessionControlling = SystemAudioSession()
    ) {
        self.makePlayer = makePlayer
        self.audioSession = audioSession
    }
```

In `playFullAzan`, replace the session `do` block (lines 29–36):

```swift
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setActive(true)
        } catch {
```

with:

```swift
        do {
            try audioSession.activatePlayback()
        } catch {
```

and `audioPlayer = try AVAudioPlayer(contentsOf: url)` with `audioPlayer = try makePlayer(url)`.
In `stopAzan`, replace `try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)` with `audioSession.deactivate()`.

(g) In `Groo/Features/Azan/Services/RecitationAudioService.swift`, replace:

```swift
    private var audioPlayer: AVAudioPlayer?
    private var playbackDelegate: PlaybackDelegate?

    private init() {}
```

with:

```swift
    private var audioPlayer: (any AudioPlaying)?
    private var playbackDelegate: PlaybackDelegate?

    private let makePlayer: (URL) throws -> any AudioPlaying
    private let audioSession: any AudioSessionControlling

    /// Phase 7: internal (was private) so tests build isolated instances;
    /// the production singleton keeps the real defaults.
    init(
        makePlayer: @escaping (URL) throws -> any AudioPlaying = { try AVAudioPlayer(contentsOf: $0) },
        audioSession: any AudioSessionControlling = SystemAudioSession()
    ) {
        self.makePlayer = makePlayer
        self.audioSession = audioSession
    }
```

In `play(_:)`, replace:

```swift
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setActive(true)

            audioPlayer = try AVAudioPlayer(contentsOf: url)
```

with:

```swift
        do {
            try audioSession.activatePlayback()

            audioPlayer = try makePlayer(url)
```

In `stop()`, replace `try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)` with `audioSession.deactivate()`.

(h) In `Groo/Features/Azan/Services/AzanLocationService.swift`, replace:

```swift
    private let locationManager = CLLocationManager()
    private let geocoder = CLGeocoder()
    private var locationContinuation: CheckedContinuation<CLLocation, Error>?

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyKilometer
        authorizationStatus = locationManager.authorizationStatus
    }
```

with:

```swift
    private let locationManager: any LocationProviding
    private let geocodeName: (CLLocation) async throws -> String?
    private var locationContinuation: CheckedContinuation<CLLocation, Error>?

    /// Phase 7 seams: production uses the real CLLocationManager and
    /// CLGeocoder; tests inject a fake manager + geocode closure.
    init(
        manager: any LocationProviding = CLLocationManager(),
        geocodeName: @escaping (CLLocation) async throws -> String? = AzanLocationService.systemGeocodeName
    ) {
        self.locationManager = manager
        self.geocodeName = geocodeName
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyKilometer
        authorizationStatus = locationManager.authorizationStatus
    }
```

and replace the whole `reverseGeocode(_:)`:

```swift
    private func reverseGeocode(_ location: CLLocation) async {
        do {
            if let name = try await geocodeName(location) {
                locationName = name
            }
        } catch {
            locationName = String(format: "%.2f, %.2f",
                                  location.coordinate.latitude, location.coordinate.longitude)
        }
    }

    /// Production geocode: CLGeocoder → "City, Country". Returns nil when
    /// the placemark has neither (leaves the previous name untouched —
    /// matching the old behavior for the no-placemark case).
    static func systemGeocodeName(_ location: CLLocation) async throws -> String? {
        let placemarks = try await CLGeocoder().reverseGeocodeLocation(location)
        guard let placemark = placemarks.first else { return nil }
        let city = placemark.locality ?? ""
        let country = placemark.country ?? ""
        if !city.isEmpty && !country.isEmpty { return "\(city), \(country)" }
        let single = city.isEmpty ? country : city
        return single.isEmpty ? nil : single
    }
```

(i) In `Groo/Features/Pad/PadService.swift`, extend the init:

```swift
    init(
        api: APIClient,
        crypto: CryptoService = CryptoService(),
        keychain: any KeychainServicing = KeychainService(),
        store: LocalStore = .shared
    ) {
        self.api = api
        self.crypto = crypto
        self.keychain = keychain
        self.store = store
    }
```

becomes:

```swift
    /// Phase 7: kdfIterations mirrors CryptoService.pbkdf2Iterations
    /// (600k); tests pass 1k — the vault-test rule.
    private let kdfIterations: UInt32

    init(
        api: APIClient,
        crypto: CryptoService = CryptoService(),
        keychain: any KeychainServicing = KeychainService(),
        store: LocalStore = .shared,
        kdfIterations: UInt32 = 600_000
    ) {
        self.api = api
        self.crypto = crypto
        self.keychain = keychain
        self.store = store
        self.kdfIterations = kdfIterations
    }
```

and in `unlock(password:)` replace `let key = try crypto.deriveKey(password: password, salt: salt)` with `let key = try crypto.deriveKey(password: password, salt: salt, iterations: kdfIterations)`. Then `grep -n 'deriveKey' Groo/Features/Pad/PadService.swift` — if any OTHER call site derives from a password (e.g. a setup-encryption path), thread `kdfIterations` there too and note it in the report.

- [ ] **Step 3: Verify (GREEN) + behavior audit**

Run: `bash scripts/test.sh --unit 2>&1 | tail -5`
Expected: PASS — **441 tests** (397 + 44). All pre-existing PadService/Pass/Azan suites still green (the seams are default-parameter).

Run: `xcodebuild build -project Groo.xcodeproj -scheme Groo -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **` — this proves `GrooApp`'s `PushService()` / `AzanAudioService()` / `pushService.authService = authService` call sites, `AzanView`'s `AzanNotificationService()` / `AzanAudioService()` / `AzanLocationService()`, `SettingsView`'s inline `AzanLocationService()`, and `ContentView`'s `PadService(api:keychain:)` all still compile against the new defaulted inits, in all 6 targets.

- [ ] **Step 4: Commit**

```bash
git add Groo/Core/Notifications Groo/Features/Azan/Services Groo/Features/Pad/PadService.swift GrooTests
git commit -m "feat: protocol seams for notification/location/audio system services + PadService KDF iterations; service tests"
```

---

### Task 8: ScratchpadStore extraction (REQUIRED for the gate; TDD; expected delta ≈ +600 covered lines)

**Files:**
- Create: `Groo/Features/Scratchpad/ScratchpadStore.swift`
- Modify: `Groo/Features/Scratchpad/Views/ScratchpadView.swift` (full-file replacement below)
- Create: `GrooTests/Features/Scratchpad/ScratchpadStoreTests.swift`
- Modify: `GrooTests/Features/Scratchpad/ScratchpadViewSnapshotTests.swift` (append the now-reachable view-state tests)

**Interfaces:**
- Consumes: the current `ScratchpadView.swift` (736 lines, read in full during recon — every store method below is a verbatim move of the corresponding view function); `WebSocketService(authService:makeConnection:makeTimer:)` + `onScratchpadUpdated/Created/Deleted`, `onConnected`, `onDisconnected(Error?)`, `connect()`, `disconnect()`; `FakeTokenProvider`/`FakeConnectionFactory`/`TimerRecorder` (existing WebSocketFakes); `SyncService` scratchpad CRUD (offline-first: `createScratchpad`/`updateScratchpad`/`deleteScratchpad` write locally + queue pending ops when `state.isOnline` is false — the `SyncServiceScratchpadTests` contract); `PadService.decryptScratchpad/encryptScratchpadContent/uploadFile/lock()`; `PadServiceTests.makeUnlockedEnv()`; `PadViewSnapshotTests.encryptedJSON(_:key:)`.
- Produces: `ScratchpadStore` (`@MainActor @Observable`) with seams `makeWebSocket` and `saveDebounce` (tests run the debounce at `.zero` and `await saveTask?.value` — no sleeps); `ScratchpadView(padService:syncService:store:)` test seam (`store: nil` in production).
- Behavior-preserving with three flagged micro-deviations: (a) `isUploadingFile` now covers the upload loop only (previously it also covered photo-data loading — the "Uploading…" capsule appears marginally later); (b) the debounce uses `Duration` (`.milliseconds(500)`) instead of raw nanoseconds; (c) remote-event handlers are `async` store methods wrapped in `Task` at the callback boundary (previously the Task lived inside the handler) — same ordering, now awaitable by tests.

- [ ] **Step 1: Tests first (RED — no `ScratchpadStore` yet)**

Create `GrooTests/Features/Scratchpad/ScratchpadStoreTests.swift`:

```swift
//
//  ScratchpadStoreTests.swift
//  GrooTests
//
//  Direct tests for the Phase 7 ScratchpadStore extraction: load/sort,
//  decrypt-failure warnings, selection, zero-debounce save (await the
//  task — no sleeps), CRUD, and remote WebSocket handlers.
//

import CryptoKit
import Foundation
import Testing
@testable import Groo

extension NetworkStubbedSuites {

@MainActor
@Suite(.serialized)
struct ScratchpadStoreTests {
    struct Env {
        let store: ScratchpadStore
        let pad: PadServiceTests.Env
        let sync: SyncService
        let factory: FakeConnectionFactory
        let editorPushes: () -> [String]
    }

    static func makeEnv(saveDebounce: Duration = .zero) throws -> Env {
        StubURLProtocol.reset()
        let padEnv = try PadServiceTests.makeUnlockedEnv()
        let sync = SyncService(
            api: APIClient(baseURL: URL(string: "https://pad.test")!,
                           sessionConfiguration: StubURLProtocol.stubbedConfiguration(),
                           tokenProvider: { "sync-token" }),
            store: padEnv.store, monitorsNetwork: false)
        let factory = FakeConnectionFactory()
        let tokens = FakeTokenProvider()
        let timers = TimerRecorder()
        let store = ScratchpadStore(
            padService: padEnv.service, syncService: sync,
            makeWebSocket: {
                WebSocketService(authService: tokens, makeConnection: factory.make,
                                 makeTimer: timers.make)
            },
            saveDebounce: saveDebounce)
        var pushes: [String] = []
        store.setEditorContent = { pushes.append($0) }
        return Env(store: store, pad: padEnv, sync: sync, factory: factory,
                   editorPushes: { pushes })
    }

    static func seed(_ env: Env, id: String, content: String, updatedAt: Int) throws {
        let scratchpad = LocalScratchpad(
            id: id,
            encryptedContentJSON: try PadViewSnapshotTests.encryptedJSON(content, key: env.pad.key),
            createdAt: Date(timeIntervalSince1970: 1_699_000_000),
            updatedAt: Date(timeIntervalSince1970: TimeInterval(updatedAt)))
        env.pad.store.context.insert(scratchpad)
        try env.pad.store.context.save()
    }

    static func decryptedContent(_ env: Env, id: String) throws -> String {
        let local = try #require(env.sync.getEncryptedScratchpad(id: id))
        return try env.pad.service.decryptScratchpad(local).content
    }

    // MARK: - Loading

    @Test func loadSortsNewestFirstAndClearsLoading() async throws {
        let env = try Self.makeEnv()
        try Self.seed(env, id: "p-old", content: "# Old", updatedAt: 1_700_000_000)
        try Self.seed(env, id: "p-new", content: "# New", updatedAt: 1_700_100_000)

        await env.store.loadAllScratchpads()

        #expect(env.store.allPads.map(\.id) == ["p-new", "p-old"])
        #expect(!env.store.isLoading)
        #expect(env.store.loadWarning == nil)
        #expect(env.store.error == nil)
    }

    @Test func decryptFailureCountsIntoLoadWarning() async throws {
        let env = try Self.makeEnv()
        try Self.seed(env, id: "p-good", content: "# Good", updatedAt: 1_700_100_000)
        // Valid payload JSON, garbage ciphertext → decryptScratchpad throws
        let garbage = LocalScratchpad(
            id: "p-bad",
            encryptedContentJSON: #"{"ciphertext":"Z2FyYmFnZQ==","iv":"AAAAAAAAAAAAAAAA","version":1}"#,
            createdAt: Date(timeIntervalSince1970: 1_699_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000))
        env.pad.store.context.insert(garbage)
        try env.pad.store.context.save()

        await env.store.loadAllScratchpads()

        #expect(env.store.allPads.map(\.id) == ["p-good"])
        #expect(env.store.loadWarning == "1 scratchpad couldn't be decrypted")
        env.store.dismissLoadWarning()
        #expect(env.store.loadWarning == nil)
    }

    // MARK: - Selection

    @Test func selectPadPushesEditorContentAndTracksSaved() async throws {
        let env = try Self.makeEnv()
        try Self.seed(env, id: "p-1", content: "# One", updatedAt: 1_700_000_000)
        await env.store.loadAllScratchpads()

        env.store.selectPad(try #require(env.store.allPads.first))

        #expect(env.store.selectedPad?.id == "p-1")
        #expect(env.store.lastSavedContent == "# One")
        #expect(env.editorPushes() == ["# One"])
    }

    // MARK: - Debounced save

    @Test func contentChangeSavesThroughTheDebounce() async throws {
        let env = try Self.makeEnv()
        try Self.seed(env, id: "p-1", content: "# One", updatedAt: 1_700_000_000)
        await env.store.loadAllScratchpads()
        env.store.selectPad(try #require(env.store.allPads.first))

        env.store.handleContentChange("# One edited", padId: "p-1")
        await env.store.saveTask?.value

        #expect(env.store.lastSavedContent == "# One edited")
        #expect(!env.store.saveFailed)
        #expect(!env.store.isSaving)
        #expect(try Self.decryptedContent(env, id: "p-1") == "# One edited")
        #expect(env.store.selectedPad?.content == "# One edited")
    }

    @Test func unchangedContentDoesNotScheduleASave() async throws {
        let env = try Self.makeEnv()
        try Self.seed(env, id: "p-1", content: "# One", updatedAt: 1_700_000_000)
        await env.store.loadAllScratchpads()
        env.store.selectPad(try #require(env.store.allPads.first))

        env.store.handleContentChange("# One", padId: "p-1")

        #expect(env.store.saveTask == nil)
    }

    @Test func saveFailureSetsFlagAndPreservesLastSaved() async throws {
        let env = try Self.makeEnv()
        try Self.seed(env, id: "p-1", content: "# One", updatedAt: 1_700_000_000)
        await env.store.loadAllScratchpads()
        env.store.selectPad(try #require(env.store.allPads.first))

        env.pad.service.lock()   // encryptScratchpadContent now throws
        env.store.handleContentChange("# Doomed edit", padId: "p-1")
        await env.store.saveTask?.value

        #expect(env.store.saveFailed)
        #expect(env.store.lastSavedContent == "# One", "failed save must leave the retry marker untouched")
    }

    // MARK: - Create / delete

    @Test func createPadSelectsTheNewPad() async throws {
        let env = try Self.makeEnv()
        await env.store.loadAllScratchpads()

        await env.store.createPad()

        #expect(env.store.allPads.count == 1)
        #expect(env.store.selectedPad != nil)
        #expect(env.store.selectedPad?.content == "# New Scratchpad\n")
        #expect(!env.store.isCreating)
        #expect(env.store.actionError == nil)
    }

    @Test func deleteSelectedPadReselectsFirstRemaining() async throws {
        let env = try Self.makeEnv()
        try Self.seed(env, id: "p-1", content: "# One", updatedAt: 1_700_100_000)
        try Self.seed(env, id: "p-2", content: "# Two", updatedAt: 1_700_000_000)
        await env.store.loadAllScratchpads()
        env.store.selectPad(try #require(env.store.allPads.first))   // p-1

        await env.store.deletePad(try #require(env.store.selectedPad))

        #expect(env.store.allPads.map(\.id) == ["p-2"])
        #expect(env.store.selectedPad?.id == "p-2")
        #expect(env.editorPushes().last == "# Two")
    }

    // MARK: - Remote events

    @Test func remoteUpdateRefreshesPadAndEditor() async throws {
        let env = try Self.makeEnv()
        try Self.seed(env, id: "p-1", content: "# One", updatedAt: 1_700_000_000)
        await env.store.loadAllScratchpads()
        env.store.selectPad(try #require(env.store.allPads.first))

        // Another device updated the encrypted content behind our back
        let local = try #require(env.sync.getEncryptedScratchpad(id: "p-1"))
        local.encryptedContentJSON = try PadViewSnapshotTests.encryptedJSON("# One (remote)", key: env.pad.key)
        try env.pad.store.context.save()

        await env.store.remoteScratchpadUpdated(id: "p-1")

        #expect(env.store.allPads.first?.content == "# One (remote)")
        #expect(env.store.selectedPad?.content == "# One (remote)")
        #expect(env.store.lastSavedContent == "# One (remote)")
        #expect(env.editorPushes().last == "# One (remote)")
    }

    @Test func remoteDeleteRemovesAndReselects() async throws {
        let env = try Self.makeEnv()
        try Self.seed(env, id: "p-1", content: "# One", updatedAt: 1_700_100_000)
        try Self.seed(env, id: "p-2", content: "# Two", updatedAt: 1_700_000_000)
        await env.store.loadAllScratchpads()
        env.store.selectPad(try #require(env.store.allPads.first))   // p-1

        env.store.remoteScratchpadDeleted(id: "p-1")

        #expect(env.store.allPads.map(\.id) == ["p-2"])
        #expect(env.store.selectedPad?.id == "p-2")
    }

    @Test func setupWebSocketConnectsThroughTheFactory() async throws {
        let env = try Self.makeEnv()

        await env.store.setupWebSocket()

        #expect(env.store.webSocketService != nil)
        #expect(env.factory.connections.count == 1)
        let connection = try #require(env.factory.connections.first)
        connection.open()
        for _ in 0..<4 { await Task.yield() }
        #expect(env.store.isWebSocketConnected)
        env.store.disconnect()
    }
}
}
```

Run: `bash scripts/test.sh --unit 2>&1 | tail -3` → **FAIL to compile** (no ScratchpadStore). Red step done.

- [ ] **Step 2: Create `Groo/Features/Scratchpad/ScratchpadStore.swift`**

```swift
//
//  ScratchpadStore.swift
//  Groo
//
//  Phase 7 extraction of ScratchpadView's state/logic: loading, selection,
//  debounced auto-save, CRUD, file-attachment bookkeeping, and real-time
//  WebSocket handling. Behavior-identical to the former view functions;
//  the view owns only WebKit/picker plumbing.
//

import Foundation
import os

@MainActor
@Observable
final class ScratchpadStore {
    struct PendingUpload {
        let name: String
        let type: String
        let data: Data
    }

    private(set) var allPads: [DecryptedScratchpad] = []
    var selectedPad: DecryptedScratchpad?
    private(set) var isLoading = true
    private(set) var error: String?
    private(set) var isSaving = false
    private(set) var saveFailed = false
    private(set) var lastSavedContent: String = ""
    var actionError: String?
    private(set) var loadWarning: String?
    private(set) var isCreating = false
    private(set) var isUploadingFile = false
    private(set) var isWebSocketConnected = false
    private(set) var saveTask: Task<Void, Never>?
    private(set) var webSocketService: WebSocketService?

    /// Assigned by the hosting view — pushes content into the WKWebView
    /// editor. Tests assign a recorder.
    var setEditorContent: (String) -> Void = { _ in }

    private let padService: PadService
    private let syncService: SyncService
    private let makeWebSocket: @MainActor () -> WebSocketService
    private let saveDebounce: Duration

    init(
        padService: PadService,
        syncService: SyncService,
        makeWebSocket: @escaping @MainActor () -> WebSocketService,
        saveDebounce: Duration = .milliseconds(500)
    ) {
        self.padService = padService
        self.syncService = syncService
        self.makeWebSocket = makeWebSocket
        self.saveDebounce = saveDebounce
    }

    func dismissLoadWarning() {
        loadWarning = nil
    }

    // MARK: - Data Loading

    func loadAllScratchpads() async {
        isLoading = true
        error = nil

        // Ensure we have synced data
        await syncService.sync()

        // Get all scratchpads
        let encryptedPads = syncService.getEncryptedScratchpads()

        var decrypted: [DecryptedScratchpad] = []
        var failedCount = 0
        for encryptedPad in encryptedPads {
            do {
                decrypted.append(try padService.decryptScratchpad(encryptedPad))
            } catch {
                failedCount += 1
                Log.scratchpad.error("Failed to decrypt scratchpad \(encryptedPad.id): \(String(describing: error))")
            }
        }

        // Distinguish decrypt failures from an empty list
        loadWarning = failedCount > 0
            ? "\(failedCount) scratchpad\(failedCount == 1 ? "" : "s") couldn't be decrypted"
            : nil

        // Sort by updatedAt descending
        allPads = decrypted.sorted { $0.updatedAt > $1.updatedAt }

        // Don't auto-select - let user tap to open a pad

        isLoading = false
    }

    // MARK: - Pad Selection

    func selectPad(_ pad: DecryptedScratchpad) {
        // Save any pending changes before switching
        saveTask?.cancel()

        selectedPad = pad
        lastSavedContent = pad.content

        // Update webview content
        setEditorContent(pad.content)
    }

    /// Reset saved-content tracking when the editor switches pads.
    func resetSavedContent(to content: String) {
        lastSavedContent = content
    }

    // MARK: - Create Pad

    func createPad() async {
        isCreating = true

        do {
            let newId = try await syncService.createScratchpad(
                encryptedContent: padService.encryptScratchpadContent("# New Scratchpad\n")
            )

            // Reload to get the new pad
            await loadAllScratchpads()

            // Select the new pad
            if let newPad = allPads.first(where: { $0.id == newId }) {
                selectPad(newPad)
            }
        } catch {
            Log.scratchpad.error("Create failed: \(String(describing: error))")
            actionError = "Couldn't create scratchpad: \(error.localizedDescription)"
        }

        isCreating = false
    }

    // MARK: - Delete Pad

    func deletePad(_ pad: DecryptedScratchpad) async {
        do {
            try await syncService.deleteScratchpad(id: pad.id)

            // Remove from local list
            allPads.removeAll { $0.id == pad.id }

            // Select another pad if we deleted the selected one
            if selectedPad?.id == pad.id {
                selectedPad = allPads.first
                if let newPad = selectedPad {
                    lastSavedContent = newPad.content
                    setEditorContent(newPad.content)
                }
            }
        } catch {
            Log.scratchpad.error("Delete failed for pad \(pad.id): \(String(describing: error))")
            actionError = "Couldn't delete scratchpad: \(error.localizedDescription)"
        }
    }

    // MARK: - Content Changes

    func handleContentChange(_ newContent: String, padId: String) {
        // Skip if content hasn't actually changed
        guard newContent != lastSavedContent else { return }

        // Update local state
        if let index = allPads.firstIndex(where: { $0.id == padId }) {
            allPads[index].content = newContent
        }
        if selectedPad?.id == padId {
            selectedPad?.content = newContent
        }

        // Cancel any pending save
        saveTask?.cancel()

        // Debounce save (500ms in production; tests inject .zero)
        saveTask = Task {
            try? await Task.sleep(for: saveDebounce)

            guard !Task.isCancelled else { return }

            await saveContent(newContent, padId: padId)
        }
    }

    private func saveContent(_ content: String, padId: String) async {
        isSaving = true

        do {
            let encrypted = try padService.encryptScratchpadContent(content)
            try await syncService.updateScratchpad(id: padId, encryptedContent: encrypted)
            lastSavedContent = content
            saveFailed = false
        } catch {
            // Leave lastSavedContent untouched so the next edit retries the save
            Log.scratchpad.error("Save failed for pad \(padId): \(String(describing: error))")
            saveFailed = true
        }

        isSaving = false
    }

    // MARK: - File Attachments

    func uploadFiles(_ uploads: [PendingUpload], to pad: DecryptedScratchpad) async {
        guard !uploads.isEmpty else { return }
        isUploadingFile = true
        for upload in uploads {
            await uploadFile(name: upload.name, type: upload.type, data: upload.data, to: pad)
        }
        isUploadingFile = false
    }

    private func uploadFile(name: String, type: String, data: Data, to pad: DecryptedScratchpad) async {
        do {
            // Upload the file
            let attachment = try await padService.uploadFile(name: name, type: type, data: data)

            // Add to scratchpad
            try await syncService.addFileToScratchpad(id: pad.id, file: attachment)

            // Update local state
            let decryptedFile = DecryptedFileAttachment(
                id: attachment.id,
                name: name,
                type: type,
                size: attachment.size,
                r2Key: attachment.r2Key
            )

            if let index = allPads.firstIndex(where: { $0.id == pad.id }) {
                var updatedFiles = allPads[index].files
                updatedFiles.append(decryptedFile)
                allPads[index] = DecryptedScratchpad(
                    id: allPads[index].id,
                    content: allPads[index].content,
                    files: updatedFiles,
                    createdAt: Int(allPads[index].createdAt.timeIntervalSince1970 * 1000),
                    updatedAt: Int(Date().timeIntervalSince1970 * 1000)
                )

                if selectedPad?.id == pad.id {
                    selectedPad = allPads[index]
                }
            }

            Log.scratchpad.info("File uploaded: \(name)")
        } catch {
            Log.scratchpad.error("File upload failed for \(name): \(String(describing: error))")
            actionError = "Couldn't upload \(name): \(error.localizedDescription)"
        }
    }

    // MARK: - WebSocket

    func setupWebSocket() async {
        let ws = makeWebSocket()
        ws.onScratchpadUpdated = { [weak self] id in
            Task { await self?.remoteScratchpadUpdated(id: id) }
        }
        ws.onScratchpadCreated = { [weak self] _ in
            Task { await self?.loadAllScratchpads() }
        }
        ws.onScratchpadDeleted = { [weak self] id in
            self?.remoteScratchpadDeleted(id: id)
        }
        ws.onConnected = { [weak self] in
            self?.isWebSocketConnected = true
            Log.scratchpad.info("WebSocket connected")
        }
        ws.onDisconnected = { [weak self] (error: Error?) in
            self?.isWebSocketConnected = false
            if let error = error {
                Log.scratchpad.error("WebSocket disconnected: \(String(describing: error))")
            } else {
                Log.scratchpad.info("WebSocket disconnected")
            }
        }
        await ws.connect()
        webSocketService = ws
    }

    func disconnect() {
        webSocketService?.disconnect()
    }

    /// Handle real-time update from another device
    func remoteScratchpadUpdated(id: String) async {
        // Don't refresh if we're currently editing this pad
        if selectedPad?.id == id && isSaving {
            return
        }

        // Sync first to get latest data
        await syncService.sync()

        // Refresh the specific scratchpad
        if let encryptedPad = syncService.getEncryptedScratchpad(id: id) {
            let decrypted: DecryptedScratchpad
            do {
                decrypted = try padService.decryptScratchpad(encryptedPad)
            } catch {
                Log.scratchpad.error("Failed to decrypt remote update for pad \(id): \(String(describing: error))")
                return
            }

            if let index = allPads.firstIndex(where: { $0.id == id }) {
                allPads[index] = decrypted
            }

            // If this is the selected pad, update the editor
            if selectedPad?.id == id {
                selectedPad = decrypted
                lastSavedContent = decrypted.content
                setEditorContent(decrypted.content)
            }
        }
    }

    /// Handle scratchpad deleted on another device
    func remoteScratchpadDeleted(id: String) {
        allPads.removeAll { $0.id == id }

        if selectedPad?.id == id {
            selectedPad = allPads.first
            if let newPad = selectedPad {
                lastSavedContent = newPad.content
                setEditorContent(newPad.content)
            }
        }
    }
}
```

(The original view's callback closures captured `self` strongly — a value-type View. The store is a class, so the callbacks use `[weak self]`; the store outlives the connection in all production paths, and `deletePad` no longer touches `padToDelete` — that is UI state and stays in the view.)

- [ ] **Step 3: Replace `Groo/Features/Scratchpad/Views/ScratchpadView.swift` (full file)**

```swift
//
//  ScratchpadView.swift
//  Groo
//
//  Main scratchpad container with list and editor. State/logic lives in
//  ScratchpadStore (Phase 7 extraction); this view owns only the WebKit
//  editor plumbing and the photo/file picker UI.
//

import SwiftUI
import WebKit
import PhotosUI
import UniformTypeIdentifiers
import os

struct ScratchpadView: View {
    let padService: PadService
    let syncService: SyncService
    /// Test seam: inject a pre-built (possibly pre-loaded) store. Production
    /// leaves this nil and resolves one with a real WebSocket factory.
    var store: ScratchpadStore? = nil

    @Environment(AuthService.self) private var authService
    @State private var resolvedStore: ScratchpadStore?

    var body: some View {
        Group {
            if let resolvedStore {
                ScratchpadContentView(store: resolvedStore, padService: padService)
            } else {
                Color.clear
            }
        }
        .onAppear {
            guard resolvedStore == nil else { return }
            if let store {
                resolvedStore = store
            } else {
                let auth = authService
                resolvedStore = ScratchpadStore(
                    padService: padService,
                    syncService: syncService,
                    makeWebSocket: { WebSocketService(authService: auth) }
                )
            }
        }
    }
}

private struct ScratchpadContentView: View {
    @Bindable var store: ScratchpadStore
    let padService: PadService

    @State private var webView: WKWebView?
    @State private var showDeleteConfirmation = false
    @State private var padToDelete: DecryptedScratchpad?

    // File attachment state
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var showFilePicker = false

    // For iPad split view
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        Group {
            if store.isLoading {
                loadingView
            } else if let error = store.error {
                errorView(error)
            } else if store.allPads.isEmpty {
                emptyView
            } else {
                contentView
            }
        }
        .task {
            store.setEditorContent = { [bind = $webView] content in
                bind.wrappedValue?.evaluateJavaScript(EditorCommand.setContent(content).jsCall) { _, error in
                    if let error = error {
                        Log.scratchpad.error("Failed to set editor content: \(error.localizedDescription)")
                    }
                }
            }
            await store.loadAllScratchpads()
            await store.setupWebSocket()
        }
        .onDisappear {
            store.disconnect()
        }
        .safeAreaInset(edge: .top) {
            if let warning = store.loadWarning {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text(warning)
                    Spacer()
                    Button {
                        store.dismissLoadWarning()
                    } label: {
                        Image(systemName: "xmark")
                    }
                }
                .font(.caption)
                .foregroundStyle(.orange)
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial)
            }
        }
        .alert(
            "Something Went Wrong",
            isPresented: Binding(
                get: { store.actionError != nil },
                set: { if !$0 { store.actionError = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.actionError ?? "")
        }
        .confirmationDialog(
            "Delete Scratchpad",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let pad = padToDelete {
                    Task {
                        await store.deletePad(pad)
                        padToDelete = nil
                    }
                }
            }
            Button("Cancel", role: .cancel) {
                padToDelete = nil
            }
        } message: {
            Text("This scratchpad will be permanently deleted.")
        }
    }

    // MARK: - Content View

    @ViewBuilder
    private var contentView: some View {
        if horizontalSizeClass == .regular {
            // iPad: Side-by-side layout
            HStack(spacing: 0) {
                // Sidebar
                ScratchpadListView(
                    pads: store.allPads,
                    selectedId: store.selectedPad?.id,
                    onSelect: store.selectPad,
                    onDelete: confirmDelete,
                    onCreate: { Task { await store.createPad() } }
                )
                .frame(width: 280)

                Divider()

                // Editor
                if let pad = store.selectedPad {
                    editorView(pad)
                } else {
                    noSelectionView
                }
            }
        } else {
            // iPhone: Navigation-based layout
            NavigationStack {
                ScratchpadListView(
                    pads: store.allPads,
                    selectedId: store.selectedPad?.id,
                    onSelect: store.selectPad,
                    onDelete: confirmDelete,
                    onCreate: { Task { await store.createPad() } }
                )
                .navigationTitle("Scratchpads")
                .navigationDestination(item: $store.selectedPad) { pad in
                    editorView(pad)
                        .navigationTitle(pad.title)
                        .navigationBarTitleDisplayMode(.inline)
                }
            }
        }
    }

    // MARK: - Views

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Loading scratchpads...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundStyle(.orange)

            Text("Failed to load scratchpads")
                .font(.headline)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Retry") {
                Task { await store.loadAllScratchpads() }
            }
            .buttonStyle(.bordered)
        }
        .padding()
    }

    private var emptyView: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("No scratchpads")
                .font(.headline)

            Text("Create your first scratchpad to get started")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button {
                Task { await store.createPad() }
            } label: {
                Label("New Scratchpad", systemImage: "square.and.pencil")
            }
            .buttonStyle(.bordered)
            .disabled(store.isCreating)
        }
        .padding()
    }

    private var noSelectionView: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Select a scratchpad")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
    }

    private func editorView(_ pad: DecryptedScratchpad) -> some View {
        VStack(spacing: 0) {
            // Editor
            ZStack(alignment: .bottomTrailing) {
                ScratchpadWebView(
                    initialContent: pad.content,
                    onContentChange: { newContent in
                        store.handleContentChange(newContent, padId: pad.id)
                    },
                    onReady: {
                        Log.scratchpad.info("Editor ready for pad: \(pad.id)")
                    },
                    onError: { errorMessage in
                        Log.scratchpad.error("Editor error: \(errorMessage)")
                    },
                    webView: $webView
                )

                // Status indicator
                HStack(spacing: 8) {
                    // Sync indicator
                    if store.isSaving || store.isUploadingFile {
                        HStack(spacing: 6) {
                            ProgressView()
                                .scaleEffect(0.7)
                            Text(store.isUploadingFile ? "Uploading..." : "Saving...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else if store.saveFailed {
                        // Save failure - distinct from offline so data loss is visible
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 6, height: 6)
                            Text("Save failed")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    } else {
                        // Connection status
                        HStack(spacing: 4) {
                            Circle()
                                .fill(store.isWebSocketConnected ? Color.green : Color.orange)
                                .frame(width: 6, height: 6)
                            Text(store.isWebSocketConnected ? "Synced" : "Offline")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
                .padding()
            }

            // File attachments section
            if !pad.files.isEmpty {
                Divider()
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(pad.files) { file in
                            FileAttachmentChip(file: file, padService: padService)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                }
                .background(Color(.systemGray6).opacity(0.5))
            }

            // Attachment toolbar
            Divider()
            HStack(spacing: 16) {
                Menu {
                    PhotosPicker(
                        selection: $selectedPhotos,
                        maxSelectionCount: 10,
                        matching: .any(of: [.images, .videos])
                    ) {
                        Label("Photo Library", systemImage: "photo.on.rectangle")
                    }

                    Button {
                        showFilePicker = true
                    } label: {
                        Label("Files", systemImage: "folder")
                    }
                } label: {
                    Label("Attach", systemImage: "paperclip")
                        .font(.subheadline)
                }
                .disabled(store.isUploadingFile)

                Spacer()

                Text("\(pad.files.count) attachment\(pad.files.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
            .background(Color(.systemGray6).opacity(0.3))
        }
        .onChange(of: pad.id) { _, _ in
            // Reset saved content tracking when switching pads
            store.resetSavedContent(to: pad.content)
        }
        .onChange(of: selectedPhotos) { _, newItems in
            Task {
                await loadSelectedPhotos(newItems, for: pad)
                selectedPhotos = []
            }
        }
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true
        ) { result in
            handleFileImport(result, for: pad)
        }
    }

    // MARK: - File Attachment Handling (data collection only — uploads live in the store)

    private func loadSelectedPhotos(_ items: [PhotosPickerItem], for pad: DecryptedScratchpad) async {
        guard !items.isEmpty else { return }

        var uploads: [ScratchpadStore.PendingUpload] = []
        var failedCount = 0

        for item in items {
            let data: Data?
            do {
                data = try await item.loadTransferable(type: Data.self)
            } catch {
                Log.scratchpad.error("Failed to load selected photo: \(String(describing: error))")
                failedCount += 1
                continue
            }

            guard let data else {
                Log.scratchpad.error("Selected photo returned no data")
                failedCount += 1
                continue
            }

            let mimeType: String
            let fileName: String

            if let uti = item.supportedContentTypes.first {
                mimeType = uti.preferredMIMEType ?? "application/octet-stream"
                let ext = uti.preferredFilenameExtension ?? "bin"
                fileName = "photo_\(Int(Date().timeIntervalSince1970)).\(ext)"
            } else {
                mimeType = "image/jpeg"
                fileName = "photo_\(Int(Date().timeIntervalSince1970)).jpg"
            }

            uploads.append(ScratchpadStore.PendingUpload(name: fileName, type: mimeType, data: data))
        }

        if failedCount > 0 {
            store.actionError = "\(failedCount) photo\(failedCount == 1 ? "" : "s") couldn't be loaded"
        }

        await store.uploadFiles(uploads, to: pad)
    }

    private func handleFileImport(_ result: Result<[URL], Error>, for pad: DecryptedScratchpad) {
        switch result {
        case .success(let urls):
            Task {
                var uploads: [ScratchpadStore.PendingUpload] = []
                var failedCount = 0

                for url in urls {
                    guard url.startAccessingSecurityScopedResource() else {
                        Log.scratchpad.error("Skipped imported file (security-scoped access denied): \(url.lastPathComponent)")
                        failedCount += 1
                        continue
                    }
                    defer { url.stopAccessingSecurityScopedResource() }

                    do {
                        let data = try Data(contentsOf: url)
                        let fileName = url.lastPathComponent
                        let mimeType = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
                        uploads.append(ScratchpadStore.PendingUpload(name: fileName, type: mimeType, data: data))
                    } catch {
                        Log.scratchpad.error("Failed to read imported file \(url.lastPathComponent): \(String(describing: error))")
                        failedCount += 1
                    }
                }

                if failedCount > 0 {
                    store.actionError = "\(failedCount) file\(failedCount == 1 ? "" : "s") couldn't be read"
                }

                await store.uploadFiles(uploads, to: pad)
            }
        case .failure(let error):
            Log.scratchpad.error("File import failed: \(String(describing: error))")
            store.actionError = error.localizedDescription
        }
    }

    private func confirmDelete(_ pad: DecryptedScratchpad) {
        padToDelete = pad
        showDeleteConfirmation = true
    }
}

// MARK: - Hashable conformance for navigationDestination

extension DecryptedScratchpad: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

#Preview {
    ScratchpadView(
        padService: PadService(api: APIClient(baseURL: Config.padAPIBaseURL)),
        syncService: SyncService(api: APIClient(baseURL: Config.padAPIBaseURL))
    )
    .environment(AuthService())
}
```

- [ ] **Step 4: Append the now-reachable view states to `GrooTests/Features/Scratchpad/ScratchpadViewSnapshotTests.swift`** (inside the suite, after `coordinatorRoutesScriptMessages`):

```swift

    // MARK: - Store-injected view states (Phase 7 Task 8)

    @Test func scratchpadViewStoreStates() async throws {
        let env = try ScratchpadStoreTests.makeEnv()
        try ScratchpadStoreTests.seed(env, id: "p-1", content: "# Shopping\nmilk, eggs", updatedAt: 1_700_100_000)
        try ScratchpadStoreTests.seed(env, id: "p-2", content: "# Ideas", updatedAt: 1_700_000_000)
        await env.store.loadAllScratchpads()

        let view = ScratchpadView(padService: env.pad.service, syncService: env.sync, store: env.store)
            .environment(AuthService())
        assertViewSnapshot(of: view, named: "populated-list")

        let emptyEnv = try ScratchpadStoreTests.makeEnv()
        await emptyEnv.store.loadAllScratchpads()
        assertViewSnapshot(
            of: ScratchpadView(padService: emptyEnv.pad.service, syncService: emptyEnv.sync,
                               store: emptyEnv.store)
                .environment(AuthService()),
            named: "empty")
    }

    @Test func scratchpadViewEditorStateRendersOnly() async throws {
        let env = try ScratchpadStoreTests.makeEnv()
        try ScratchpadStoreTests.seed(env, id: "p-1", content: "# Editing", updatedAt: 1_700_000_000)
        await env.store.loadAllScratchpads()
        env.store.selectPad(try #require(env.store.allPads.first))
        // Editor hosts a live WKWebView — render-only.
        await ViewRender.assertSettledRenders(
            ScratchpadView(padService: env.pad.service, syncService: env.sync, store: env.store)
                .environment(AuthService()))
    }
```

- [ ] **Step 5: Verify (GREEN + behavior-preservation)**

Run: `bash scripts/test.sh --unit 2>&1 | tail -20` → first run records the 2 new PNGs and fails those; runs 2–3 fully green: **454 tests** (441 + 13).

Run: `bash scripts/test.sh --ui 2>&1 | tail -5`
Expected: PASS — **7 UI tests** (the UI suite traverses the scratchpad tab's unlock screen; the extraction must not disturb it).

Run: `xcodebuild build -project Groo.xcodeproj -scheme Groo -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -3` → `** BUILD SUCCEEDED **`.

Manual smoke (simulator, normal launch): open Scratchpad → unlock → list loads → open a pad → type (autosave "Saving…" then "Synced/Offline") → create + delete a pad. Any behavioral difference from main is a STOP-and-report.

- [ ] **Step 6: Commit**

```bash
git add Groo/Features/Scratchpad GrooTests/Features/Scratchpad
git commit -m "refactor: extract ScratchpadStore from ScratchpadView (behavior-preserving) + store tests and view snapshots"
```

---

### Task 9: Final verification — the 80% gate, stability, runtime, builds, docs, summary

**Files:**
- Modify: `README.md` (only if the Task 1 section needs corrections discovered en route)
- Possibly modify (gap levers only, in order, until the gate passes): `GrooTests/Views/RootViewSnapshotTests.swift`, `Groo/Features/Azan/Views/AzanSettingsView.swift` (visibility-only), `GrooTests/Features/Azan/AzanViewSnapshotTests.swift`, `GrooTests/Features/Pass/PassViewSnapshotTests.swift`, `GrooTests/Features/Pad/PadViewSnapshotTests.swift`

- [ ] **Step 1: THE GATE**

Run: `bash scripts/test.sh --unit --coverage 2>&1 | tail -70`
Expected: `** TEST SUCCEEDED **` and **Groo.app ≥ 80.00%**.

If below 80%, execute the pre-authorized gap-closing menu IN ORDER until the gate passes (re-run `--coverage` after each; each lever states its estimated recovery):

1. **ContentView logged-out branch (+~35):** append to `RootViewSnapshotTests`:
   ```swift
   @Test func contentViewLoggedOutRendersOnly() {
       StubURLProtocol.reset()
       ViewRender.assertRenders(
           ContentView().environment(AuthService()).environment(PushService()))
   }
   ```
   (`PushService()` now has the Task 7 defaulted init — it constructs cleanly.)
2. **`SoundPickerSheet` visibility lever (+~250):** in `AzanSettingsView.swift`, change `private struct SoundPickerSheet` (and, if also private, `DefaultSoundRow`/`SoundCard`) to internal by deleting the `private` keyword — a visibility-only, zero-behavior diff. Then append to `AzanViewSnapshotTests` a snapshot of `SoundPickerSheet` for the notification-sound case (constructor per its definition — read the file for the exact init; it takes the picker type, the current selection, an `AzanAudioService`, and an onSelect closure).
3. **PrayerDetail remaining roles (+~80):** add `imam`/`muqtadi` variants to `prayerDetailVariants` (two more `withPinnedDefaults` blocks pinning `prayerGuideRole`).
4. **PadUnlockView biometric-available state (+~60):** build a `PadService` over an `InMemoryKeychain` pre-seeded with `KeychainService.Key.padEncryptionKey` (the `makeUnlockedEnv` seeding line, without calling `unlockWithBiometric`) → `canUnlockWithBiometric` is true → snapshot the Face-ID-button branch. NOTE: `biometricType` still reads `.none` from `LAContext` on the simulator, so check `canUseBiometric`'s conjunction first — if the branch is unreachable headless, skip this lever and say so.
5. **PassItemDetail/SendView extra states (+~150):** detail with `favorite: false`, `notes: nil`, multiple URLs; `SendView` for an asset while `passService` is locked (unlock-prompt branch reachable? only if gated by `isUnlocked` at render — verify in source first).

Record the final percentage and which levers ran in the phase summary. If the menu is exhausted below 80%: STOP and report with the per-file coverage table — do not invent new production seams without adjudication.

- [ ] **Step 2: Stability + runtime + suites**

Run: `time bash scripts/test.sh --unit 2>&1 | tail -3` **twice**
Expected: `** TEST SUCCEEDED **` both times (snapshot byte-stability across consecutive runs — the spec's determinism gate) and wall-clock **under ~3 minutes** each. If over budget: the levers are (a) drop `yields:` overrides that exceeded 8, (b) merge single-state snapshot tests into batch tests per feature (fewer host/window cycles), (c) report if still over — do NOT delete coverage to make time without adjudication.

Run: `bash scripts/test.sh --ui 2>&1 | tail -3 && bash scripts/test.sh --ui 2>&1 | tail -3`
Expected: **7 UI tests**, green twice — untouched by the phase.

- [ ] **Step 3: All targets, both configurations**

Run: `xcodebuild build -project Groo.xcodeproj -scheme Groo -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -3` → `** BUILD SUCCEEDED **`
Run: `xcodebuild build -project Groo.xcodeproj -scheme Groo -configuration Release -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -3` → `** BUILD SUCCEEDED **` (SnapshotTesting must not leak into any shipping target; the Release build proves it).

- [ ] **Step 4: Snapshot hygiene check**

```bash
git status --short                    # committed tree only — no stray recordings
find GrooTests -name '*.png' | wc -l  # matches the sum of recorded references (~110)
git log --oneline main..HEAD | head -20
```
Every `__Snapshots__` PNG must belong to a committed suite; delete any orphans from renamed tests.

- [ ] **Step 5: Commit any Step-1 lever work**

```bash
git add -A GrooTests Groo/Features/Azan/Views/AzanSettingsView.swift README.md
git commit -m "test: Phase 7 gap-closing states + final gate" # only if levers ran
```

- [ ] **Step 6: Final report (phase summary)**

Report to the user:
- **Coverage:** Groo.app 36.69% → final % (per-file table for the former zero-coverage views), which checkpoints/levers were needed.
- **Totals:** 316 → final unit-test count (expected 454 + any levers) in ~55 suites + 7 UI; `--unit` wall-clock; snapshot reference count and repo size delta.
- **Production changes shipped:** the six Task 7 seams (one paragraph each, incl. the three approved micro-deviations), the Task 8 ScratchpadStore extraction (+ its three micro-deviations), any Task 9 visibility levers.
- **Deviations from spec:** dark/Dynamic-Type representative set substituted (Pass list, PrayerDetail, StockPortfolio — Home/Azan are countdown-live); render-only list with per-view reasons (the determinism rule applied); exclusions (CameraPicker, live editor JS bridge, LocationSearch live results, biometric keychain, ContentView auth-service init path).
- **New conventions now binding:** snapshot two-run record→assert workflow, re-record env var, `ViewRenderHarness` wrappers, `withPinnedDefaults`/`withFixedAzanLocation`, "no snapshots of wall-clock pixels".
- **Ledger:** append the Phase 7 lines to `.superpowers/sdd/progress.md` (same format as P1–P6: per-task commits, review status, test counts, final coverage).

---

## Post-plan

Phase 7 closes the 80% coverage goal from the Phase 7 spec. Follow-ups that belong to future product/priority decisions, not this plan: CI snapshot infrastructure (references are pinned to the local iPhone 17 Pro simulator by design), gesture-flow XCUITests, the live scratchpad editor JS bridge, and the P5 backgrounding-relock USER DECISION still pending from the Phase 6 summary.

## Self-review checklist (planner ran this; executor re-runs it before Task 1)

- **Spec coverage:** every spec decision maps to a task — rendering technique (T1 harness), snapshot library + conventions (T1), fixture wiring via P1–P6 fakes (T2–T6), state coverage 2–4 per view (per-task fixtures), view-model extraction only where renders can't reach (T8, ScratchpadView — PassItemFormView validation was assessed and NOT extracted: its form states render and its `buildItem` fatalError arm is UI-unreachable), system-service seams incl. RecitationAudioService's singleton shape + PadService KDF param (T7), coverage gate + runtime budget + README + builds (T9), out-of-scope list respected (no extension UI, no full appearance matrix, no CI).
- **Placeholder scan:** no TODO/TBD/"fill in" in any code block; the only deliberate look-before-run adjustments are called out explicitly (WebViewBridge event keys, assertSnapshot label drift, azan sound basenames, SoundPickerSheet init) with instructions to verify against source — never to invent.
- **Type consistency:** every view/model/service initializer in test code was transcribed from recon of the actual sources (PassModels/PadModels/StockModels/CryptoModels/AzanModels/PrayerGuideModels memberwise inits; `makeEnv`/`makeUnlockedEnv` shapes; `WalletManager(passService:defaults:)`; `PrayerTimeEntry` 10-field order; `StockHolding` 8-field order; `ScratchpadWebView` binding-last order). The Task 7 "Replace/With" pairs quote the current files verbatim.
- **Counting rule:** running totals assume one `@Test` declaration each (parameterized tests count once) — recount from the xcodebuild summary at every task and reconcile before committing.
