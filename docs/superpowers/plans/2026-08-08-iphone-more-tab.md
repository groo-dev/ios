# iPhone "More" Tab Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace iOS's system "More" overflow on iPhone with an app-owned More tab, and let the user order which features occupy the tab bar — while leaving the iPad rendering path pixel-identical.

**Architecture:** Feature screens stop owning a root `NavigationStack`; hosts supply it. One `FeatureContent` factory maps `TabID` → screen and is consumed by two sibling roots — the existing `MainTabView` (iPad) and a new `PhoneTabView` (iPhone). A `TabConfiguration` value type holds the user's order plus a Home toggle, persisted by `TabConfigurationStore`, and an `AppRouter` resolves `open(_:)` against the live configuration.

**Tech Stack:** SwiftUI (iOS 26), `@Observable`/`@MainActor`, Swift Testing (`@Test`/`#expect`/`#require`), swift-snapshot-testing via the in-repo `ViewRender` harness, XCUITest.

**Spec:** `docs/superpowers/specs/2026-08-08-iphone-more-tab-design.md`

## Global Constraints

- Work on branch `iphone-more-tab`. It already contains the spec commit.
- Build: `xcodebuild -project Groo.xcodeproj -scheme Groo -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build`
- Unit tests: `scripts/test.sh --unit`. All tests: `scripts/test.sh --all`.
- **The unit suite has ~16 pre-existing failures, and the count is not fixed** — some are date-dependent. Diff the failing *set*, never the count:
  `scripts/test.sh --unit 2>&1 | sed -n '/^Failing tests:/,/^\*\* TEST/p'`
  Capture that set once before Task 1 and compare after every task.
- New files under `Groo/` and `GrooTests/` are picked up automatically (filesystem-synchronized groups). **Do not edit `project.pbxproj`.**
- `Shared/` is NOT touched by this plan. No `scripts/register_shared_file.rb` runs, no extension changes.
- **iPad must stay pixel-identical.** The existing snapshot suites are the gate: `PadViewSnapshotTests`, `PassViewSnapshotTests`, `AzanViewSnapshotTests`, `ScratchpadViewSnapshotTests`, `StocksViewSnapshotTests`, `CryptoViewSnapshotTests`, `RootViewSnapshotTests`.
- `SettingsView.swift` gets exactly one change in this whole plan (Task 12, one destination line). Nothing else in it moves.
- Sheet-local `NavigationStack`s are never touched. Only *root* stacks move.
- Swift Testing, not XCTest, for unit tests. XCUITest files stay XCTest.
- Never construct `UserDefaults.standard` in a unit test — use a suite-named instance and `removePersistentDomain` in a `defer`, matching `GrooTests/Core/ConfigTests.swift`.

---

## File Structure

**Created**

| File | Responsibility |
|---|---|
| `Groo/Core/TabConfiguration.swift` | Value type: order + Home toggle, sanitizing init, `barTabs`/`moreTabs` derivation |
| `Groo/Core/TabConfigurationStore.swift` | Observable persistence of `TabConfiguration` under `phoneTabBar` |
| `Groo/Core/AppRouter.swift` | `PhoneSelection` + observable router, selection persistence, reconciliation |
| `Groo/Views/FeatureContent.swift` | `TabID` → screen factory, shared by both sibling roots |
| `Groo/Views/PhoneTabView.swift` | iPhone sibling: 4 feature tabs + More |
| `Groo/Views/MoreView.swift` | More screen: index list + single `navigationDestination` |
| `Groo/Views/PhoneTabBarEditor.swift` | Three-zone editor (Home toggle / draggable order / frozen Settings) |
| `Groo/Views/CustomizeTabsEntry.swift` | 10-line idiom branch: editor on iPhone, `CustomizeTabsView` on iPad |
| `GrooTests/Core/TabConfigurationTests.swift` | Invariant coverage for the value type |
| `GrooTests/Core/TabConfigurationStoreTests.swift` | Persistence + defensive decode |
| `GrooTests/Core/AppRouterTests.swift` | Routing + restore + reconciliation |
| `GrooTests/Views/PhoneTabSnapshotTests.swift` | Phone root, More screen, editor renders |

**Modified**

| File | Change |
|---|---|
| `Groo/Views/MainTabView.swift` | Delegates to `FeatureContent`, wraps each tab in `NavigationStack`, binds to router |
| `Groo/ContentView.swift` | Idiom branch; owns store + router |
| `Groo/Views/HomeView.swift` | Root stack hoisted; card taps call `router.open(_:)` |
| `Groo/Features/Azan/Views/AzanView.swift` | Root stack hoisted |
| `Groo/Features/Drive/Views/DrivePlaceholderView.swift` | Root stack hoisted |
| `Groo/Features/Pass/Views/PassView.swift` | Root stack hoisted |
| `Groo/Features/Pad/Views/PadView.swift` | `unlockedView` stack hoisted |
| `Groo/Features/Pad/Views/PadUnlockView.swift` | `.toolbar(.hidden, for: .navigationBar)` |
| `Groo/Features/Scratchpad/Views/ScratchpadTabView.swift` | `ScratchpadUnlockView` stack hoisted |
| `Groo/Features/Scratchpad/Views/ScratchpadView.swift` | Compact-branch stack hoisted; regular branch hides bar |
| `Groo/Features/Stocks/Views/StockPortfolioView.swift` | Root stack hoisted |
| `Groo/Features/Stocks/Views/StockOnboardingView.swift` | Root stack hoisted |
| `Groo/Features/Crypto/Views/PortfolioView.swift` | Root stack hoisted |
| `Groo/Features/Crypto/Views/WalletOnboardingView.swift` | Root stack hoisted |
| `Groo/Views/SettingsView.swift` | One line: Customize Tabs destination |
| `GrooUITests/UITestHelpers.swift` | `phoneTabBar` launch override; `openTab` rewritten |
| `GrooUITests/TabNavigationUITests.swift` | New structure; Settings asserts nav bar title |

---

## Phase A — Stack hoisting

Behavior-neutral **measured against the merge base** (`ae11ce5`), not against the immediately preceding commit. **Phase A introduces no new behavior — if a snapshot changes, you broke something, do not re-record it.**

**Correction, learned during Task 3 — read before doing Tasks 4 or 5.** Task 1 wrapped all nine tabs in a host `NavigationStack` while hoisting only three screens (Home, Azan, Drive). Every screen not yet hoisted is therefore *transiently double-stacked* between Task 1 and its own hoist task. At the time of writing, Scratchpad, Stocks and Wallet are still in that state. Consequently:

- A hoist in Tasks 4-5 **removes a double stack and therefore legitimately changes rendering versus the current `HEAD`** — content that was pushed down by a redundant second navigation bar moves back up (~86px was measured for Pad). That is the fix, not a regression. It must still match the **merge base** rendering.
- **The snapshot suites cannot see this.** They render screens directly (`ViewRender.assertRenders(SomeView())`), never through `MainTabView`, so a double stack is invisible to them and the failing-set diff stays empty either way. An empty diff is necessary but **not sufficient** evidence in Phase A.
- Therefore each remaining hoist must additionally prove itself **through the host**, the way Task 3's fix did: render the screen wrapped in exactly one `NavigationStack` at the merge base and at `HEAD`, and compare the images with a scratch `snapshotDirectory:` outside `__Snapshots__`. Never write a reference image to prove a point.

### Task 1: Extract the `FeatureContent` factory

Pure refactor. `MainTabView.tabContent(for:)` becomes a standalone type both roots can use, and each tab gains a host-provided `NavigationStack`. Screens still own their own stacks at this point, so this task creates *temporary* double stacks; it hoists the three simplest screens (Home, Azan, Drive) in the same commit.

> **Retrospective correction (written after Task 3).** The original rationale here claimed this arrangement meant "nothing is ever left double-wrapped at a commit boundary." That was wrong: wrapping all nine tabs while hoisting three leaves the other six double-wrapped until their own hoist task. No user-visible harm — the branch was never released mid-Phase-A — but it invalidated the "empty failing-set diff proves neutrality" reasoning for Tasks 2-5, because the snapshot suites bypass the host and cannot see a double stack. See the corrected Phase A preamble above.

**Files:**
- Create: `Groo/Views/FeatureContent.swift`
- Modify: `Groo/Views/MainTabView.swift:60-90` (replace `tabContent(for:)`), `:92-161` (wrap each `Tab`)
- Modify: `Groo/Views/HomeView.swift:40-70`
- Modify: `Groo/Features/Azan/Views/AzanView.swift:30-...`
- Modify: `Groo/Features/Drive/Views/DrivePlaceholderView.swift:11-37`
- Test: `GrooTests/Views/RootViewSnapshotTests.swift` (existing, must stay green)

**Interfaces:**
- Produces: `FeatureContent` — a struct with `padService`, `syncService`, `passService`, `onSignOut: () -> Void`, `onLock: () -> Void`, and `@ViewBuilder func view(for tab: TabID) -> some View` returning **stack-free** content.

- [ ] **Step 1: Capture the pre-existing failure set**

```bash
scripts/test.sh --unit 2>&1 | sed -n '/^Failing tests:/,/^\*\* TEST/p' > /tmp/baseline-failures.txt
cat /tmp/baseline-failures.txt
```

Keep this file for the whole plan. Every later comparison is against it.

- [ ] **Step 2: Create the factory**

Create `Groo/Views/FeatureContent.swift`:

```swift
//
//  FeatureContent.swift
//  Groo
//
//  Maps a TabID to its screen. The single place that mapping lives — both
//  MainTabView (iPad) and PhoneTabView (iPhone) consume it. Everything
//  returned here is stack-free: hosts supply the NavigationStack, so the same
//  screen renders correctly as a tab root or as a pushed More destination.
//

import SwiftUI

struct FeatureContent {
    let padService: PadService
    let syncService: SyncService
    let passService: PassService
    let onSignOut: () -> Void
    let onLock: () -> Void

    @ViewBuilder
    func view(for tab: TabID) -> some View {
        switch tab {
        case .home:
            HomeView(padService: padService, syncService: syncService, passService: passService)
        case .pad:
            PadView(padService: padService, syncService: syncService, onSignOut: onSignOut)
        case .pass:
            PassView(passService: passService, onSignOut: onSignOut)
        case .scratchpad:
            ScratchpadTabView(padService: padService, syncService: syncService)
        case .drive:
            DrivePlaceholderView()
        case .crypto:
            CryptoView(passService: passService)
        case .azan:
            AzanView()
        case .stocks:
            StocksView()
        case .settings:
            SettingsView(
                padService: padService,
                passService: passService,
                onSignOut: onSignOut,
                onLock: onLock
            )
        }
    }
}
```

- [ ] **Step 3: Point `MainTabView` at the factory and wrap each tab**

In `Groo/Views/MainTabView.swift`, delete the whole `tabContent(for:)` method (`:60-90`) and add a computed factory. Replace it with:

```swift
    private var content: FeatureContent {
        FeatureContent(
            padService: padService,
            syncService: syncService,
            passService: passService,
            onSignOut: onSignOut,
            onLock: {
                padService.lock()
                passService.lock()
            }
        )
    }
```

Then change **every one of the nine** `Tab` bodies from `tabContent(for: .x)` to `NavigationStack { content.view(for: .x) }`. For example:

```swift
            Tab(value: TabID.home) {
                NavigationStack { content.view(for: .home) }
            } label: {
                tabLabel(for: .home)
            }
            .customizationID(TabID.home.rawValue)
```

Do this for `.home`, `.stocks`, `.crypto`, `.azan`, `.pad`, `.pass`, `.drive`, `.scratchpad`, `.settings`. Leave `tabLabel(for:)`, `.customizationID`, `.tabViewCustomization`, `.tabViewStyle`, the minimize modifier and `.tint` exactly as they are.

- [ ] **Step 4: Hoist Home's stack**

In `Groo/Views/HomeView.swift`, the body is `NavigationStack { ScrollView { … } … }` with `.toast`, `.onAppear` and `.task` applied *outside* the stack. Remove the `NavigationStack {` wrapper (`:41`) and its matching closing brace (`:66`), de-indenting the contents one level. The modifiers that were attached to the `ScrollView` (`.onScrollGeometryChange`, `.background`, `.navigationBarTitleDisplayMode`, `.toolbar`) stay on the `ScrollView`; `.toast`/`.onAppear`/`.task` stay where they are, now applied to the `ScrollView` instead of the stack. Result:

```swift
    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.lg) {
                stocksCard
                cryptoCard
                prayerCard
                padCard
            }
            .padding(Theme.Spacing.lg)
        }
        .onScrollGeometryChange(for: CGFloat.self) { geo in
            -geo.contentOffset.y - geo.contentInsets.top
        } action: { _, new in
            scrollOffset = new
        }
        .background(Color(.systemGroupedBackground))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Image(.grooLogo)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(height: 30)
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                    .scaleEffect(logoScale, anchor: .top)
            }
        }
        .toast(isPresented: $toastState.isPresented, message: toastState.message, style: toastState.style)
        .onAppear { loadCachedData() }
        .task { await refreshData() }
    }
```

Update the `#Preview` at the bottom of the file to wrap in `NavigationStack { … }` so the preview still shows the toolbar.

- [ ] **Step 5: Hoist Azan's and Drive's stacks**

`AzanView.swift`: remove the `NavigationStack {` at `:31` and its matching close, de-indent. **Do not touch the sheet-local stacks at `:91` and `:102`.** Wrap the `#Preview` in `NavigationStack`.

`DrivePlaceholderView.swift`: body becomes

```swift
    var body: some View {
        VStack(spacing: Theme.Spacing.xl) {
            Spacer()

            Image(systemName: "folder.fill")
                .font(.system(size: Theme.Size.iconHero))
                .foregroundStyle(Theme.Brand.primary.opacity(0.5))

            Text("Drive")
                .font(.title)
                .fontWeight(.bold)

            Text("Coming Soon")
                .font(.headline)
                .foregroundStyle(.secondary)

            Text("Cloud file storage with end-to-end encryption")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Theme.Spacing.xxl)

            Spacer()
        }
        .navigationTitle("Drive")
    }
}

#Preview {
    NavigationStack { DrivePlaceholderView() }
}
```

- [ ] **Step 6: Build**

```bash
xcodebuild -project Groo.xcodeproj -scheme Groo -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | tail -20
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 7: Run the suite and diff the failure set**

```bash
scripts/test.sh --unit 2>&1 | sed -n '/^Failing tests:/,/^\*\* TEST/p' > /tmp/after-task1.txt
diff /tmp/baseline-failures.txt /tmp/after-task1.txt
```

Expected: **no diff.** Any new failure in `AzanViewSnapshotTests` or `RootViewSnapshotTests` means a stack ended up in the wrong place — fix the hoist, do not re-record the reference image.

- [ ] **Step 8: Commit**

```bash
git add Groo/Views/FeatureContent.swift Groo/Views/MainTabView.swift Groo/Views/HomeView.swift \
        Groo/Features/Azan/Views/AzanView.swift Groo/Features/Drive/Views/DrivePlaceholderView.swift
git commit -m "refactor: extract FeatureContent factory, host-provided navigation stacks"
```

---

### Task 2: Hoist Pass

**Files:**
- Modify: `Groo/Features/Pass/Views/PassView.swift:22-...`
- Test: `GrooTests/Features/Pass/PassViewSnapshotTests.swift` (existing, must stay green)

**Interfaces:**
- Consumes: `FeatureContent.view(for:)` from Task 1.
- Produces: nothing new.

`PassView` is the simplest branching case — a single `NavigationStack` at `:23` wrapping a `Group` that holds both the locked and unlocked states, so both states already render inside a stack and neither needs a toolbar-hiding fix.

- [ ] **Step 1: Remove the root stack**

In `Groo/Features/Pass/Views/PassView.swift`, delete the `NavigationStack {` at `:23` and its matching closing brace, de-indenting the `Group { … }` and every modifier chained onto it one level. The body becomes:

```swift
    var body: some View {
        Group {
            if passService.isUnlocked || isUnlocked {
                PassItemListView(…)
                    .navigationTitle("Pass")
                    .toolbar { … }
            } else {
                PassUnlockView(…)
            }
        }
        .sheet(item: $selectedItem) { item in
            NavigationStack { … }      // unchanged — sheet root
        }
        // … every other .sheet unchanged
    }
```

**Do not touch the sheet-local `NavigationStack` at `:85` or any other sheet root.**

- [ ] **Step 2: Wrap the preview**

Wrap the `#Preview` body in `NavigationStack { … }`.

- [ ] **Step 3: Build and run the Pass suites**

```bash
xcodebuild -project Groo.xcodeproj -scheme Groo -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | tail -5
scripts/test.sh --unit 2>&1 | sed -n '/^Failing tests:/,/^\*\* TEST/p' > /tmp/after-task2.txt
diff /tmp/baseline-failures.txt /tmp/after-task2.txt
```

Expected: build succeeds, no diff in the failure set.

- [ ] **Step 4: Commit**

```bash
git add Groo/Features/Pass/Views/PassView.swift
git commit -m "refactor: hoist PassView navigation stack to host"
```

---

### Task 3: Hoist Pad

**Files:**
- Modify: `Groo/Features/Pad/Views/PadView.swift:39-...` (`unlockedView`)
- Modify: `Groo/Features/Pad/Views/PadUnlockView.swift:32`
- Test: `GrooTests/Features/Pad/PadViewSnapshotTests.swift` (existing, must stay green)

**Interfaces:**
- Consumes: `FeatureContent.view(for:)` from Task 1.
- Produces: nothing new.

Pad's stack lives in `unlockedView`, not at the body root. `PadUnlockView` has no stack at all today, so once the host always supplies one, the lock screen would gain an empty navigation bar — hence the toolbar-hiding step.

- [ ] **Step 1: Remove the stack from `unlockedView`**

In `Groo/Features/Pad/Views/PadView.swift`, `unlockedView` currently opens with `NavigationStack {` at `:40`. Delete it and its matching closing brace, de-indenting one level. `PadListView`'s `.navigationTitle("Pad")`, `.toolbar` and `.sheet` chain stay attached to `PadListView`:

```swift
    private var unlockedView: some View {
        PadListView(
            padService: padService,
            syncService: syncService,
            refreshTrigger: listRefreshTrigger
        )
        .navigationTitle("Pad")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showAddItem = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showAddItem, onDismiss: {
            listRefreshTrigger = UUID()
        }) {
            AddItemSheet(padService: padService, syncService: syncService)
        }
        // … any remaining modifiers unchanged
    }
```

`PadView.body` (the `Group` with the `isUnlocked` branch and `.onAppear`) is unchanged.

- [ ] **Step 2: Preserve the lock screen's appearance**

In `Groo/Features/Pad/Views/PadUnlockView.swift`, the body starts at `:32`. Append `.toolbar(.hidden, for: .navigationBar)` to the outermost view in `body` — this keeps the locked state pixel-identical now that a host stack always exists above it. Add a comment saying why:

```swift
        // Hosts always supply a NavigationStack now (FeatureContent is
        // stack-free). This screen never had one, so hide the bar it would
        // otherwise inherit — pinned by PadViewSnapshotTests.
        .toolbar(.hidden, for: .navigationBar)
```

- [ ] **Step 3: Wrap the previews**

Wrap the `#Preview` in both files in `NavigationStack { … }`.

- [ ] **Step 4: Build and diff**

```bash
xcodebuild -project Groo.xcodeproj -scheme Groo -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | tail -5
scripts/test.sh --unit 2>&1 | sed -n '/^Failing tests:/,/^\*\* TEST/p' > /tmp/after-task3.txt
diff /tmp/baseline-failures.txt /tmp/after-task3.txt
```

Expected: no diff. A new `PadViewSnapshotTests` failure means the toolbar-hiding modifier is missing or on the wrong view.

- [ ] **Step 5: Commit**

```bash
git add Groo/Features/Pad/Views/PadView.swift Groo/Features/Pad/Views/PadUnlockView.swift
git commit -m "refactor: hoist PadView navigation stack, hide bar on lock screen"
```

---

### Task 4: Hoist Scratchpad

**Files:**
- Modify: `Groo/Features/Scratchpad/Views/ScratchpadTabView.swift:47` (`ScratchpadUnlockView`)
- Modify: `Groo/Features/Scratchpad/Views/ScratchpadView.swift:146-185` (`contentView`)
- Test: `GrooTests/Features/Scratchpad/ScratchpadViewSnapshotTests.swift` (existing, must stay green)

**Interfaces:**
- Consumes: `FeatureContent.view(for:)` from Task 1.
- Produces: nothing new.

The trickiest hoist. `ScratchpadView.contentView` branches on `horizontalSizeClass`: the regular branch is a bare `HStack` with **no** stack, the compact branch owns a `NavigationStack` carrying a `navigationDestination(item:)`.

- [ ] **Step 1: Hoist the unlock view's stack**

In `ScratchpadTabView.swift`, `ScratchpadUnlockView.body` opens with `NavigationStack {` at `:47`. Delete it and its matching close, and de-indent one level.

> **Correction (applied during execution — the original instruction here was wrong).** This step originally also told the implementer to append `.toolbar(.hidden, for: .navigationBar)`, on the rationale that "this screen never had a visible bar." That rationale was copied from `PadUnlockView` without checking Scratchpad, and it is false: at the merge base `ScratchpadUnlockView` carries `.navigationTitle("Scratchpad")` and renders a real, titled navigation bar. Hiding the bar deletes a title users currently see — a regression, not a neutral hoist, and it dropped `scratchpadTabLocked` to an 89% pixel match. **Keep `.navigationTitle("Scratchpad")` and do NOT add the toolbar-hiding modifier here.** Only `ScratchpadView`'s regular (iPad) branch needs it, in Step 2.

```swift
    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "note.text")
                .font(.system(size: 64))
                .foregroundStyle(Theme.Brand.primary)

            Text("Scratchpad Locked")
                .font(.title2)
                .fontWeight(.semibold)

            // … rest of the existing content, de-indented one level
        }
        .navigationTitle("Scratchpad")   // keep — the host stack renders it
    }
```

- [ ] **Step 2: Rework `contentView`'s two branches**

In `ScratchpadView.swift`, replace the `contentView` body (`:144-185`) with:

```swift
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
            // This branch never had a NavigationStack of its own; the host
            // supplies one now, so suppress the bar it would inherit.
            .toolbar(.hidden, for: .navigationBar)
        } else {
            // iPhone: Navigation-based layout. The stack is the host's; the
            // destination registers against it.
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
```

- [ ] **Step 3: Wrap the previews**

Wrap the `#Preview` in both files in `NavigationStack { … }`.

- [ ] **Step 4: Build and diff**

```bash
xcodebuild -project Groo.xcodeproj -scheme Groo -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | tail -5
scripts/test.sh --unit 2>&1 | sed -n '/^Failing tests:/,/^\*\* TEST/p' > /tmp/after-task4.txt
diff /tmp/baseline-failures.txt /tmp/after-task4.txt
```

Expected: no diff.

- [ ] **Step 5: Manually verify iPhone scratchpad navigation still pushes**

```bash
scripts/test.sh --all 2>&1 | tail -30
```

Expected: the existing UI tests still pass. Selecting a pad on iPhone must push the editor; if it no longer does, the `navigationDestination` is registered outside the host stack.

- [ ] **Step 6: Commit**

```bash
git add Groo/Features/Scratchpad/Views/ScratchpadTabView.swift Groo/Features/Scratchpad/Views/ScratchpadView.swift
git commit -m "refactor: hoist Scratchpad navigation stack to host"
```

---

### Task 5: Hoist Stocks and Wallet

**Files:**
- Modify: `Groo/Features/Stocks/Views/StockPortfolioView.swift:20-21`
- Modify: `Groo/Features/Stocks/Views/StockOnboardingView.swift:16-17`
- Modify: `Groo/Features/Crypto/Views/PortfolioView.swift:50-51`
- Modify: `Groo/Features/Crypto/Views/WalletOnboardingView.swift:26-27`
- Test: `GrooTests/Features/Stocks/StocksViewSnapshotTests.swift`, `GrooTests/Features/Crypto/CryptoViewSnapshotTests.swift` (existing, must stay green)

**Interfaces:**
- Consumes: `FeatureContent.view(for:)` from Task 1.
- Produces: nothing new.

These four are the "one stack per branch" cases. `StocksView` and `CryptoView` are thin routers with no stack of their own, so after this task their host's single stack spans both branches — which also stops the stack being torn down when the user adds a first holding or wallet.

- [ ] **Step 1: Remove the four root stacks**

In each of the four files, delete the `NavigationStack {` at the top of `body` and its matching closing brace, de-indenting the contents one level. Their `.navigationTitle` calls (`StockOnboardingView:51` `"Stocks"`, `WalletOnboardingView:85` `"Wallet"`, and the `.navigationTitle("")` calls in the portfolio views) stay attached to the content they are already on.

**Do not touch these sheet-local stacks:** `StockPortfolioView:159,177`, `PortfolioView:214,231,240`, `WalletOnboardingView:127,226`. Only the *first* `NavigationStack` in each file — the one directly inside `body` — is removed. `WalletOnboardingView` is the one to be careful with: it has three, and only the one at `:27` goes.

- [ ] **Step 2: Wrap the previews**

Wrap the `#Preview` in all four files in `NavigationStack { … }`.

- [ ] **Step 3: Build and diff**

```bash
xcodebuild -project Groo.xcodeproj -scheme Groo -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | tail -5
scripts/test.sh --unit 2>&1 | sed -n '/^Failing tests:/,/^\*\* TEST/p' > /tmp/after-task5.txt
diff /tmp/baseline-failures.txt /tmp/after-task5.txt
```

Expected: no diff.

- [ ] **Step 4: Verify the wallet onboarding sheet still works**

```bash
scripts/test.sh --all 2>&1 | grep -A5 "WalletOnboardingUITests"
```

Expected: `WalletOnboardingUITests` passes. This test exercises the recovery-phrase sheet, which depends on a sheet-local stack you must not have removed.

- [ ] **Step 5: Commit**

```bash
git add Groo/Features/Stocks/Views/StockPortfolioView.swift Groo/Features/Stocks/Views/StockOnboardingView.swift \
        Groo/Features/Crypto/Views/PortfolioView.swift Groo/Features/Crypto/Views/WalletOnboardingView.swift
git commit -m "refactor: hoist Stocks and Wallet navigation stacks to host"
```

Phase A is complete. Every feature screen is now stack-free and iPad renders exactly as it did before the branch.

---

## Phase B — Configuration model

### Task 6: `TabConfiguration` value type

**Files:**
- Create: `Groo/Core/TabConfiguration.swift`
- Test: `GrooTests/Core/TabConfigurationTests.swift`

**Interfaces:**
- Consumes: `TabID` from `Groo/Views/MainTabView.swift:10`.
- Produces:
  - `struct TabConfiguration: Equatable, Codable, Sendable`
  - `static let barSlots = 4`
  - `static let reorderable: [TabID]` — the seven draggable features
  - `static let `default`: TabConfiguration`
  - `init(order: [TabID], showsHome: Bool)` — sanitizing
  - `var order: [TabID]` (get-only outside), `var showsHome: Bool` (get-only outside)
  - `var allTabs: [TabID]`, `var barTabs: [TabID]`, `var moreTabs: [TabID]`
  - `mutating func move(fromOffsets: IndexSet, toOffset: Int)`
  - `mutating func setShowsHome(_ value: Bool)`

- [ ] **Step 1: Write the failing tests**

Create `GrooTests/Core/TabConfigurationTests.swift`:

```swift
//
//  TabConfigurationTests.swift
//  GrooTests
//
//  Invariants of the iPhone tab-bar configuration: the sanitizing init must
//  make an invalid configuration unrepresentable, so no consumer has to
//  defend against one.
//

import Foundation
import Testing
@testable import Groo

struct TabConfigurationTests {
    @Test func defaultPutsHomeAzanPassPadInTheBar() {
        #expect(TabConfiguration.default.barTabs == [.home, .azan, .pass, .pad])
    }

    @Test func defaultLeavesFourFeaturesInMore() {
        #expect(TabConfiguration.default.moreTabs == [.stocks, .crypto, .drive, .scratchpad])
    }

    @Test func settingsIsNeverOrderableAndNeverInTheBar() {
        let config = TabConfiguration(order: [.settings, .stocks], showsHome: true)
        #expect(!config.order.contains(.settings))
        #expect(!config.barTabs.contains(.settings))
        #expect(!config.moreTabs.contains(.settings))
    }

    @Test func homeIsNeverInTheOrderedList() {
        let config = TabConfiguration(order: [.home, .stocks], showsHome: true)
        #expect(!config.order.contains(.home))
    }

    @Test func disablingHomePromotesTheNextFeature() {
        var config = TabConfiguration.default
        config.setShowsHome(false)
        #expect(config.barTabs == [.azan, .pass, .pad, .stocks])
        #expect(config.moreTabs == [.crypto, .drive, .scratchpad])
    }

    @Test func duplicatesAreCollapsed() {
        let config = TabConfiguration(order: [.pass, .pass, .pad], showsHome: true)
        #expect(config.order.filter { $0 == .pass }.count == 1)
    }

    @Test func missingFeaturesAreAppendedInDefaultOrder() {
        let config = TabConfiguration(order: [.drive], showsHome: true)
        #expect(config.order.first == .drive)
        #expect(Set(config.order) == Set(TabConfiguration.reorderable))
    }

    @Test func orderAlwaysHoldsEverySevenReorderableFeatures() {
        let config = TabConfiguration(order: [], showsHome: false)
        #expect(config.order.count == 7)
    }

    @Test func moveReordersAndPreservesInvariants() {
        var config = TabConfiguration.default   // [azan, pass, pad, stocks, crypto, drive, scratchpad]
        config.move(fromOffsets: IndexSet(integer: 5), toOffset: 0)   // drive to front
        #expect(config.order.first == .drive)
        #expect(config.barTabs == [.home, .drive, .azan, .pass])
        #expect(Set(config.order) == Set(TabConfiguration.reorderable))
    }

    @Test func decodingDropsUnknownIdentifiersAndRefills() throws {
        let json = #"{"order":["drive","not-a-tab","pass"],"showsHome":false}"#
        let config = try JSONDecoder().decode(TabConfiguration.self, from: Data(json.utf8))
        #expect(config.order.prefix(2) == [.drive, .pass])
        #expect(Set(config.order) == Set(TabConfiguration.reorderable))
        #expect(config.showsHome == false)
    }

    @Test func encodeDecodeRoundTrips() throws {
        var config = TabConfiguration.default
        config.move(fromOffsets: IndexSet(integer: 6), toOffset: 0)
        config.setShowsHome(false)
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(TabConfiguration.self, from: data)
        #expect(decoded == config)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
scripts/test.sh --unit 2>&1 | grep -i "TabConfigurationTests\|cannot find"
```

Expected: compilation failure — `cannot find 'TabConfiguration' in scope`.

- [ ] **Step 3: Implement the type**

Create `Groo/Core/TabConfiguration.swift`:

```swift
//
//  TabConfiguration.swift
//  Groo
//
//  The iPhone tab bar's composition: an ordered list of features plus a Home
//  toggle. The first `barSlots` entries render as tabs, slot five is More, and
//  everything past the cut falls into More's list.
//
//  The initializer sanitizes, so an invalid configuration is unrepresentable
//  and no consumer needs to defend against one. Home is pinned first (or
//  absent) and is never a member of `order`; Settings is not part of this
//  model at all — it is always the last row of More.
//

import Foundation

struct TabConfiguration: Equatable, Codable, Sendable {
    /// Tab-bar slots available to features. The fifth slot is always More.
    static let barSlots = 4

    /// Features the user can drag, in their default order.
    static let reorderable: [TabID] = [.azan, .pass, .pad, .stocks, .crypto, .drive, .scratchpad]

    static let `default` = TabConfiguration(order: reorderable, showsHome: true)

    private(set) var order: [TabID]
    private(set) var showsHome: Bool

    init(order: [TabID], showsHome: Bool) {
        var seen = Set<TabID>()
        // Keep only draggable features, first occurrence wins…
        var sanitized = order.filter { Self.reorderable.contains($0) && seen.insert($0).inserted }
        // …then refill anything absent, in default order.
        sanitized += Self.reorderable.filter { !seen.contains($0) }
        self.order = sanitized
        self.showsHome = showsHome
    }

    /// Every feature the user can reach through the bar or More, in order.
    var allTabs: [TabID] {
        showsHome ? [.home] + order : order
    }

    /// The features rendered as tab-bar items.
    var barTabs: [TabID] {
        Array(allTabs.prefix(Self.barSlots))
    }

    /// The features that fall past the cut into More. Settings is appended by
    /// the More screen itself and is deliberately not part of this list.
    var moreTabs: [TabID] {
        Array(allTabs.dropFirst(Self.barSlots))
    }

    mutating func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        var next = order
        next.move(fromOffsets: source, toOffset: destination)
        self = TabConfiguration(order: next, showsHome: showsHome)
    }

    mutating func setShowsHome(_ value: Bool) {
        self = TabConfiguration(order: order, showsHome: value)
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey { case order, showsHome }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let raw = (try? container.decode([String].self, forKey: .order)) ?? []
        let showsHome = (try? container.decode(Bool.self, forKey: .showsHome)) ?? true
        self.init(order: raw.compactMap(TabID.init(rawValue:)), showsHome: showsHome)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(order.map(\.rawValue), forKey: .order)
        try container.encode(showsHome, forKey: .showsHome)
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
scripts/test.sh --unit 2>&1 | sed -n '/^Failing tests:/,/^\*\* TEST/p' > /tmp/after-task6.txt
diff /tmp/baseline-failures.txt /tmp/after-task6.txt
```

Expected: no diff (all eleven new tests pass).

- [ ] **Step 5: Commit**

```bash
git add Groo/Core/TabConfiguration.swift GrooTests/Core/TabConfigurationTests.swift
git commit -m "feat: TabConfiguration value type with sanitizing invariants"
```

---

### Task 7: `TabConfigurationStore`

**Files:**
- Create: `Groo/Core/TabConfigurationStore.swift`
- Test: `GrooTests/Core/TabConfigurationStoreTests.swift`

**Interfaces:**
- Consumes: `TabConfiguration` from Task 6.
- Produces:
  - `@Observable @MainActor final class TabConfigurationStore`
  - `static let defaultsKey = "phoneTabBar"`
  - `init(defaults: UserDefaults = .standard)`
  - `var configuration: TabConfiguration` — settable, persists on write

The value is stored as a **JSON string**, not `Data`, so an NSArgumentDomain launch argument (`-phoneTabBar '{…}'`) can seed it in UI tests exactly the way `-selectedTab` already does.

- [ ] **Step 1: Write the failing tests**

Create `GrooTests/Core/TabConfigurationStoreTests.swift`:

```swift
//
//  TabConfigurationStoreTests.swift
//  GrooTests
//
//  Persistence for the iPhone tab bar. Stored as a JSON *string* so a UI test
//  can seed it through NSArgumentDomain. Every malformed input resolves to the
//  default rather than propagating a broken configuration.
//

import Foundation
import Testing
@testable import Groo

@MainActor
struct TabConfigurationStoreTests {
    private func makeDefaults() throws -> (UserDefaults, String) {
        let suiteName = "tabconfig-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        return (defaults, suiteName)
    }

    @Test func emptyStoreYieldsTheDefaultConfiguration() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = TabConfigurationStore(defaults: defaults)

        #expect(store.configuration == .default)
    }

    @Test func writingPersistsAcrossStoreInstances() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = TabConfigurationStore(defaults: defaults)
        var config = store.configuration
        config.setShowsHome(false)
        store.configuration = config

        let reloaded = TabConfigurationStore(defaults: defaults)

        #expect(reloaded.configuration.showsHome == false)
        #expect(reloaded.configuration.barTabs == [.azan, .pass, .pad, .stocks])
    }

    @Test func corruptJSONFallsBackToDefault() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("{ not json", forKey: TabConfigurationStore.defaultsKey)

        let store = TabConfigurationStore(defaults: defaults)

        #expect(store.configuration == .default)
    }

    @Test func partialJSONIsRepairedNotRejected() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(#"{"order":["drive"],"showsHome":true}"#, forKey: TabConfigurationStore.defaultsKey)

        let store = TabConfigurationStore(defaults: defaults)

        #expect(store.configuration.order.first == .drive)
        #expect(store.configuration.order.count == 7)
    }

    @Test func storedValueIsAStringSoLaunchArgumentsCanSeedIt() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = TabConfigurationStore(defaults: defaults)
        var config = store.configuration
        config.setShowsHome(false)
        store.configuration = config

        #expect(defaults.string(forKey: TabConfigurationStore.defaultsKey) != nil)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
scripts/test.sh --unit 2>&1 | grep -i "cannot find 'TabConfigurationStore'"
```

Expected: `cannot find 'TabConfigurationStore' in scope`.

- [ ] **Step 3: Implement the store**

Create `Groo/Core/TabConfigurationStore.swift`:

```swift
//
//  TabConfigurationStore.swift
//  Groo
//
//  Persists the iPhone tab-bar configuration. The value is a JSON *string*
//  rather than Data so that a UI test can seed it through NSArgumentDomain
//  (`-phoneTabBar '{"order":[…],"showsHome":true}'`), the same lever
//  UITestHelpers already uses for `-selectedTab`.
//

import Foundation
import Observation

@Observable
@MainActor
final class TabConfigurationStore {
    static let defaultsKey = "phoneTabBar"

    private let defaults: UserDefaults

    var configuration: TabConfiguration {
        didSet { persist() }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.configuration = Self.load(from: defaults)
    }

    private static func load(from defaults: UserDefaults) -> TabConfiguration {
        guard let json = defaults.string(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode(TabConfiguration.self, from: Data(json.utf8))
        else { return .default }
        return decoded
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(configuration),
              let json = String(data: data, encoding: .utf8)
        else { return }
        defaults.set(json, forKey: Self.defaultsKey)
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
scripts/test.sh --unit 2>&1 | sed -n '/^Failing tests:/,/^\*\* TEST/p' > /tmp/after-task7.txt
diff /tmp/baseline-failures.txt /tmp/after-task7.txt
```

Expected: no diff.

- [ ] **Step 5: Commit**

```bash
git add Groo/Core/TabConfigurationStore.swift GrooTests/Core/TabConfigurationStoreTests.swift
git commit -m "feat: persist iPhone tab bar configuration"
```

---

## Phase C — Routing

### Task 8: `PhoneSelection` and `AppRouter`

**Files:**
- Create: `Groo/Core/AppRouter.swift`
- Test: `GrooTests/Core/AppRouterTests.swift`

**Interfaces:**
- Consumes: `TabConfiguration`, `TabConfigurationStore` from Tasks 6-7.
- Produces:
  - `enum PhoneSelection: Hashable` with cases `.feature(TabID)`, `.more`; `var storageValue: String`; `init?(storageValue: String)`
  - `@Observable @MainActor final class AppRouter`
  - `static let selectionKey = "selectedTab"`
  - `init(store: TabConfigurationStore, defaults: UserDefaults = .standard)`
  - `var phoneSelection: PhoneSelection` — persists on write
  - `var padSelection: TabID` — persists on write
  - `var morePath: [TabID]`
  - `func open(_ tab: TabID)`
  - `func configurationDidChange()`

The router maintains **both** selections unconditionally. iPad's `MainTabView` binds to `padSelection`, iPhone's `PhoneTabView` binds to `phoneSelection`/`morePath`. Neither host branches on idiom, and `HomeView` calls `open(_:)` without knowing which device it is on.

- [ ] **Step 1: Write the failing tests**

Create `GrooTests/Core/AppRouterTests.swift`:

```swift
//
//  AppRouterTests.swift
//  GrooTests
//
//  open(_:) resolves against the live configuration: a feature in the bar is
//  selected directly, one past the cut selects More and pushes. Restore and
//  reconciliation must never strand the user on a tab that is not on screen.
//

import Foundation
import Testing
@testable import Groo

@MainActor
struct AppRouterTests {
    private func makeEnv() throws -> (AppRouter, TabConfigurationStore, UserDefaults, String) {
        let suiteName = "approuter-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let store = TabConfigurationStore(defaults: defaults)
        return (AppRouter(store: store, defaults: defaults), store, defaults, suiteName)
    }

    @Test func openingABarFeatureSelectsItDirectly() throws {
        let (router, _, defaults, suite) = try makeEnv()
        defer { defaults.removePersistentDomain(forName: suite) }

        router.open(.pass)

        #expect(router.phoneSelection == .feature(.pass))
        #expect(router.morePath.isEmpty)
    }

    @Test func openingAFeaturePastTheCutSelectsMoreAndPushes() throws {
        let (router, _, defaults, suite) = try makeEnv()
        defer { defaults.removePersistentDomain(forName: suite) }

        router.open(.stocks)

        #expect(router.phoneSelection == .more)
        #expect(router.morePath == [.stocks])
    }

    @Test func openingAlwaysUpdatesThePadSelectionToo() throws {
        let (router, _, defaults, suite) = try makeEnv()
        defer { defaults.removePersistentDomain(forName: suite) }

        router.open(.stocks)

        #expect(router.padSelection == .stocks)
    }

    @Test func openingABarFeatureClearsAPreviousMorePush() throws {
        let (router, _, defaults, suite) = try makeEnv()
        defer { defaults.removePersistentDomain(forName: suite) }

        router.open(.stocks)
        router.open(.pad)

        #expect(router.phoneSelection == .feature(.pad))
        #expect(router.morePath.isEmpty)
    }

    @Test func restoringADemotedSelectionFallsBackToTheFirstBarTab() throws {
        let suiteName = "approuter-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        // Stocks is past the cut in the default configuration.
        defaults.set("stocks", forKey: AppRouter.selectionKey)

        let router = AppRouter(store: TabConfigurationStore(defaults: defaults), defaults: defaults)

        #expect(router.phoneSelection == .feature(.home))
    }

    @Test func restoringHomeWhenHomeIsDisabledFallsBackToTheFirstBarTab() throws {
        let suiteName = "approuter-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(#"{"order":["azan","pass","pad","stocks","crypto","drive","scratchpad"],"showsHome":false}"#,
                     forKey: TabConfigurationStore.defaultsKey)
        defaults.set("home", forKey: AppRouter.selectionKey)

        let router = AppRouter(store: TabConfigurationStore(defaults: defaults), defaults: defaults)

        #expect(router.phoneSelection == .feature(.azan))
    }

    @Test func restoringMoreIsHonoured() throws {
        let suiteName = "approuter-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("more", forKey: AppRouter.selectionKey)

        let router = AppRouter(store: TabConfigurationStore(defaults: defaults), defaults: defaults)

        #expect(router.phoneSelection == .more)
    }

    @Test func settingsIsNeverARestorableFeatureSelection() throws {
        let suiteName = "approuter-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("settings", forKey: AppRouter.selectionKey)

        let router = AppRouter(store: TabConfigurationStore(defaults: defaults), defaults: defaults)

        #expect(router.phoneSelection == .feature(.home))
    }

    @Test func configurationChangeClearsThePathAndRevalidatesSelection() throws {
        let (router, store, defaults, suite) = try makeEnv()
        defer { defaults.removePersistentDomain(forName: suite) }
        router.open(.pass)

        var config = store.configuration
        config.move(fromOffsets: IndexSet(integer: 1), toOffset: 7)   // pass to the end
        store.configuration = config
        router.configurationDidChange()

        #expect(router.morePath.isEmpty)
        #expect(router.phoneSelection == .feature(.home))
    }

    @Test func selectionIsPersistedOnWrite() throws {
        let (router, _, defaults, suite) = try makeEnv()
        defer { defaults.removePersistentDomain(forName: suite) }

        router.open(.stocks)

        #expect(defaults.string(forKey: AppRouter.selectionKey) == "more")
    }

    @Test func phoneSelectionStorageValueRoundTrips() {
        #expect(PhoneSelection(storageValue: "more") == .more)
        #expect(PhoneSelection(storageValue: "pass") == .feature(.pass))
        #expect(PhoneSelection(storageValue: "settings") == nil)
        #expect(PhoneSelection(storageValue: "nonsense") == nil)
        #expect(PhoneSelection.more.storageValue == "more")
        #expect(PhoneSelection.feature(.azan).storageValue == "azan")
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
scripts/test.sh --unit 2>&1 | grep -i "cannot find 'AppRouter'\|cannot find 'PhoneSelection'"
```

Expected: both symbols unresolved.

- [ ] **Step 3: Implement the router**

Create `Groo/Core/AppRouter.swift`:

```swift
//
//  AppRouter.swift
//  Groo
//
//  Navigation intent, resolved against the live tab configuration. HomeView's
//  cards call open(_:) without knowing which idiom they are on or whether the
//  destination currently sits in the tab bar or inside More.
//
//  Both selections are maintained unconditionally: MainTabView (iPad) binds to
//  padSelection, PhoneTabView (iPhone) binds to phoneSelection/morePath. That
//  keeps every host free of idiom branching.
//

import Foundation
import Observation

/// What the iPhone tab bar currently has selected. Settings is deliberately
/// not representable — on iPhone it is a row inside More, never a tab.
enum PhoneSelection: Hashable {
    case feature(TabID)
    case more

    var storageValue: String {
        switch self {
        case .feature(let tab): tab.rawValue
        case .more: "more"
        }
    }

    init?(storageValue: String) {
        if storageValue == "more" {
            self = .more
        } else if let tab = TabID(rawValue: storageValue), tab != .settings {
            self = .feature(tab)
        } else {
            return nil
        }
    }
}

@Observable
@MainActor
final class AppRouter {
    /// Shares the key the app has always used, so a persisted selection from
    /// before this feature — and UITest's `-selectedTab` override — still work.
    static let selectionKey = "selectedTab"

    private let store: TabConfigurationStore
    private let defaults: UserDefaults

    var phoneSelection: PhoneSelection {
        didSet { defaults.set(phoneSelection.storageValue, forKey: Self.selectionKey) }
    }

    var padSelection: TabID {
        didSet { defaults.set(padSelection.rawValue, forKey: Self.selectionKey) }
    }

    var morePath: [TabID] = []

    init(store: TabConfigurationStore, defaults: UserDefaults = .standard) {
        self.store = store
        self.defaults = defaults

        let stored = defaults.string(forKey: Self.selectionKey)
        let restored = stored.flatMap(PhoneSelection.init(storageValue:))
        self.phoneSelection = Self.resolve(restored, in: store.configuration)
        self.padSelection = stored.flatMap(TabID.init(rawValue:)) ?? .home
    }

    /// Navigate to a feature, wherever it currently lives.
    func open(_ tab: TabID) {
        padSelection = tab

        if store.configuration.barTabs.contains(tab) {
            morePath = []
            phoneSelection = .feature(tab)
        } else {
            phoneSelection = .more
            morePath = [tab]
        }
    }

    /// Called after the user edits the tab bar. The pushed destination may no
    /// longer belong inside More, and the selection may name a tab that is no
    /// longer on screen.
    func configurationDidChange() {
        morePath = []
        phoneSelection = Self.resolve(phoneSelection, in: store.configuration)
    }

    private static func resolve(_ selection: PhoneSelection?, in config: TabConfiguration) -> PhoneSelection {
        switch selection {
        case .more:
            return .more
        case .feature(let tab) where config.barTabs.contains(tab):
            return .feature(tab)
        default:
            // barTabs is never empty — order always holds all seven features —
            // so the fallback is defensive only.
            return config.barTabs.first.map(PhoneSelection.feature) ?? .more
        }
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
scripts/test.sh --unit 2>&1 | sed -n '/^Failing tests:/,/^\*\* TEST/p' > /tmp/after-task8.txt
diff /tmp/baseline-failures.txt /tmp/after-task8.txt
```

Expected: no diff.

- [ ] **Step 5: Commit**

```bash
git add Groo/Core/AppRouter.swift GrooTests/Core/AppRouterTests.swift
git commit -m "feat: AppRouter resolves navigation against live tab configuration"
```

---

### Task 9: Wire `HomeView` and `MainTabView` to the router

**Files:**
- Modify: `Groo/Views/HomeView.swift:16` (remove `@AppStorage`), `:77`, `:129`, `:176`, `:224`, `:238`
- Modify: `Groo/Views/MainTabView.swift:48` (remove `@AppStorage`), `:93` (bind selection)
- Test: `GrooTests/Views/RootViewSnapshotTests.swift` (existing, needs the new environment value)

**Interfaces:**
- Consumes: `AppRouter` from Task 8.
- Produces: `AppRouter` is now read from the SwiftUI environment by `HomeView` and `MainTabView`.

- [ ] **Step 1: Replace HomeView's `@AppStorage` with the router**

In `Groo/Views/HomeView.swift`, delete line 16:

```swift
    @AppStorage("selectedTab") private var selectedTab: TabID = .home
```

and add, alongside the other environment reads:

```swift
    @Environment(AppRouter.self) private var router
```

Then replace all five call sites:

| Line | Before | After |
|---|---|---|
| `:77` | `Button { selectedTab = .stocks }` | `Button { router.open(.stocks) }` |
| `:129` | `Button { selectedTab = .crypto }` | `Button { router.open(.crypto) }` |
| `:176` | `Button { selectedTab = .pad }` | `Button { router.open(.pad) }` |
| `:224` | `Button { selectedTab = .pad }` | `Button { router.open(.pad) }` |
| `:238` | `Button { selectedTab = .azan }` | `Button { router.open(.azan) }` |

- [ ] **Step 2: Bind `MainTabView` to `padSelection`**

In `Groo/Views/MainTabView.swift`, delete line 48 (`@AppStorage("selectedTab") private var selectedTab: TabID = .home`) and add:

```swift
    @Environment(AppRouter.self) private var router
```

Then in `body`, take a bindable reference and bind the `TabView`:

```swift
    var body: some View {
        @Bindable var router = router

        return TabView(selection: $router.padSelection) {
            // … the nine Tab declarations, unchanged
        }
        // … modifiers unchanged
    }
```

- [ ] **Step 3: Update the existing snapshot test and preview**

`GrooTests/Views/RootViewSnapshotTests.swift:167-179` constructs `MainTabView` directly and injects `.environment(AuthService())`. Add the router and its store:

```swift
    @Test func mainTabViewRendersOnly() throws {
        StubURLProtocol.reset()
        let (padService, store) = try PadViewSnapshotTests.lockedPadService()
        let passEnv = try PassServiceIntegrationTests.makeEnv(items: [])
        defer { try? FileManager.default.removeItem(at: passEnv.tempDir) }
        let suiteName = "maintab-snapshot-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let configStore = TabConfigurationStore(defaults: defaults)
        withPinnedDefaults(Self.deadURLDefaults) {
            ViewRender.assertRenders(
                MainTabView(padService: padService,
                            syncService: PadViewSnapshotTests.offlineSync(store: store),
                            passService: passEnv.service, onSignOut: {})
                    .environment(AuthService())
                    .environment(configStore)
                    .environment(AppRouter(store: configStore, defaults: defaults)))
        }
    }
```

Apply the same two `.environment(...)` additions to **every** other test in `RootViewSnapshotTests.swift` that renders `HomeView` or `ContentView` — they will fail to resolve `AppRouter` otherwise. Update `MainTabView`'s and `HomeView`'s `#Preview` blocks the same way.

- [ ] **Step 4: Build and diff**

```bash
xcodebuild -project Groo.xcodeproj -scheme Groo -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | tail -5
scripts/test.sh --unit 2>&1 | sed -n '/^Failing tests:/,/^\*\* TEST/p' > /tmp/after-task9.txt
diff /tmp/baseline-failures.txt /tmp/after-task9.txt
```

Expected: no diff. A crash reading `AppRouter` from the environment means a render site is missing `.environment(...)`.

- [ ] **Step 5: Commit**

```bash
git add Groo/Views/HomeView.swift Groo/Views/MainTabView.swift GrooTests/Views/RootViewSnapshotTests.swift
git commit -m "refactor: route tab navigation through AppRouter"
```

---

## Phase D — iPhone UI

### Task 10: The More screen

**Files:**
- Create: `Groo/Views/MoreView.swift`
- Test: covered by Task 13's snapshot suite

**Interfaces:**
- Consumes: `TabConfiguration`, `FeatureContent`, `TabID`.
- Produces: `struct MoreView: View` with `init(configuration: TabConfiguration, content: FeatureContent, path: Binding<[TabID]>)`.

- [ ] **Step 1: Create the view**

Create `Groo/Views/MoreView.swift`:

```swift
//
//  MoreView.swift
//  Groo
//
//  The iPhone overflow screen: an index of every feature past the tab-bar cut,
//  with Settings pinned last. Its single job is to be a list of destinations —
//  every row pushes through one navigationDestination, which works no matter
//  how many features fall past the cut, because FeatureContent is stack-free.
//

import SwiftUI

struct MoreView: View {
    let configuration: TabConfiguration
    let content: FeatureContent
    @Binding var path: [TabID]

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if !configuration.moreTabs.isEmpty {
                    Section {
                        ForEach(configuration.moreTabs, id: \.self) { tab in
                            NavigationLink(value: tab) { row(for: tab) }
                        }
                    }
                }

                Section {
                    NavigationLink(value: TabID.settings) { row(for: .settings) }
                }
            }
            .navigationTitle("More")
            .navigationDestination(for: TabID.self) { tab in
                content.view(for: tab)
            }
        }
    }

    private func row(for tab: TabID) -> some View {
        Label {
            Text(tab.title)
        } icon: {
            Image(systemName: tab.icon)
                .environment(\.symbolVariants, .none)
                .foregroundStyle(Theme.Brand.primary)
        }
        .accessibilityIdentifier("more.row.\(tab.rawValue)")
    }
}
```

- [ ] **Step 2: Build**

```bash
xcodebuild -project Groo.xcodeproj -scheme Groo -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add Groo/Views/MoreView.swift
git commit -m "feat: app-owned More screen for iPhone"
```

---

### Task 11: `PhoneTabView` and the idiom branch

**Files:**
- Create: `Groo/Views/PhoneTabView.swift`
- Modify: `Groo/ContentView.swift:15-53` (state + branch)
- Test: covered by Task 13's snapshot suite

**Interfaces:**
- Consumes: `TabConfiguration`, `TabConfigurationStore`, `AppRouter`, `FeatureContent`, `MoreView`.
- Produces: `struct PhoneTabView: View` with the same initializer signature as `MainTabView` (`padService`, `syncService`, `passService`, `onSignOut`).

- [ ] **Step 1: Create the iPhone root**

Create `Groo/Views/PhoneTabView.swift`:

```swift
//
//  PhoneTabView.swift
//  Groo
//
//  iPhone sibling of MainTabView. Four configurable feature tabs plus an
//  app-owned More tab, replacing the system overflow (a UIKit navigation
//  controller that silently discards SwiftUI's navigationTitle).
//
//  Deliberately NOT a parameterised version of MainTabView: the two roots
//  share only FeatureContent, so an iPhone change can never alter iPad.
//

import SwiftUI

struct PhoneTabView: View {
    let padService: PadService
    let syncService: SyncService
    let passService: PassService
    let onSignOut: () -> Void

    @Environment(TabConfigurationStore.self) private var configStore
    @Environment(AppRouter.self) private var router

    private var content: FeatureContent {
        FeatureContent(
            padService: padService,
            syncService: syncService,
            passService: passService,
            onSignOut: onSignOut,
            onLock: {
                padService.lock()
                passService.lock()
            }
        )
    }

    var body: some View {
        @Bindable var router = router

        return TabView(selection: $router.phoneSelection) {
            ForEach(configStore.configuration.barTabs, id: \.self) { tab in
                Tab(value: PhoneSelection.feature(tab)) {
                    NavigationStack { content.view(for: tab) }
                } label: {
                    tabLabel(for: tab)
                }
            }

            Tab(value: PhoneSelection.more) {
                MoreView(
                    configuration: configStore.configuration,
                    content: content,
                    path: $router.morePath
                )
            } label: {
                Label {
                    Text("More")
                } icon: {
                    Image(systemName: "ellipsis.circle")
                        .environment(\.symbolVariants, .none)
                }
            }
        }
        .modifier(TabBarMinimizeOnScrollModifier())
        .tint(Theme.Brand.primary)
        .onChange(of: configStore.configuration) {
            router.configurationDidChange()
        }
    }

    private func tabLabel(for tab: TabID) -> some View {
        Label {
            Text(tab.title)
        } icon: {
            Image(systemName: tab.icon)
                .environment(\.symbolVariants, .none)
        }
    }
}
```

`TabBarMinimizeOnScrollModifier` is `fileprivate` to `MainTabView.swift` today. Change its declaration there from `private struct` to `struct` so both roots can use it, and move nothing else.

- [ ] **Step 2: Add the idiom branch to `ContentView`**

In `Groo/ContentView.swift`, add both as optional state alongside the existing service properties (`:15-20`), following the pattern already used for `padService`/`syncService`/`passService` — these types are `@MainActor`, so they are constructed inside `initializeServices()` rather than in a property initializer:

```swift
    @State private var configStore: TabConfigurationStore?
    @State private var router: AppRouter?
```

Build them at the **end** of `initializeServices()`, after the existing early-return branch — put this in both the `UITestMode.isActive` branch (before its `return`) and the production branch:

```swift
        let configuration = TabConfigurationStore()
        configStore = configuration
        router = AppRouter(store: configuration)
```

Then replace **only** the `else { MainTabView(...) }` block at `:43-52` — leave the enclosing `if !isLoggedIn` / `else if let padService, let syncService, let passService` / `if needsGlobalUnlock && !isGloballyUnlocked` chain exactly as it is:

```swift
                } else if let configStore, let router {
                    Group {
                        if UIDevice.current.userInterfaceIdiom == .pad {
                            MainTabView(
                                padService: padService,
                                syncService: syncService,
                                passService: passService,
                                onSignOut: { signOut() }
                            )
                        } else {
                            PhoneTabView(
                                padService: padService,
                                syncService: syncService,
                                passService: passService,
                                onSignOut: { signOut() }
                            )
                        }
                    }
                    .environment(configStore)
                    .environment(router)
                }
```

The `else` becomes `else if let configStore, let router` because both are optional until `initializeServices()` runs. `GlobalLockView` keeps its own `if` arm untouched.

Add `import UIKit` at the top of the file if it is not already imported.

**The branch is evaluated once per launch and never re-evaluated** — that is the entire reason idiom was chosen over size class. Do not convert it to `@Environment(\.horizontalSizeClass)`.

- [ ] **Step 3: Build and run on the iPhone simulator**

```bash
xcodebuild -project Groo.xcodeproj -scheme Groo -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | tail -5
scripts/test.sh --unit 2>&1 | sed -n '/^Failing tests:/,/^\*\* TEST/p' > /tmp/after-task11.txt
diff /tmp/baseline-failures.txt /tmp/after-task11.txt
```

Expected: build succeeds, no diff.

- [ ] **Step 4: Commit**

```bash
git add Groo/Views/PhoneTabView.swift Groo/Views/MainTabView.swift Groo/ContentView.swift
git commit -m "feat: iPhone tab root with app-owned More tab"
```

---

### Task 12: The tab bar editor

**Files:**
- Create: `Groo/Views/PhoneTabBarEditor.swift`
- Create: `Groo/Views/CustomizeTabsEntry.swift`
- Modify: `Groo/Views/SettingsView.swift:59-63` (one destination line)
- Test: covered by Task 13's snapshot suite

**Interfaces:**
- Consumes: `TabConfigurationStore`, `TabConfiguration`.
- Produces: `struct PhoneTabBarEditor: View`, `struct CustomizeTabsEntry: View` (both no-argument initializers, reading the store from the environment).

Three zones: a Home toggle outside the draggable region, the seven draggable features with a cut marker, and Settings frozen at the bottom. There is no add or remove action — every permutation the user can produce is valid by construction, so no tap is ever rejected.

- [ ] **Step 1: Create the editor**

Create `Groo/Views/PhoneTabBarEditor.swift`:

```swift
//
//  PhoneTabBarEditor.swift
//  Groo
//
//  Three zones: Home (toggle only, pinned first), the draggable features, and
//  Settings (frozen last). The cut marker shows where the tab bar ends and
//  More begins — it moves when Home is toggled, because Home occupies a bar
//  slot. No add/remove: every reachable permutation is valid, so no tap can
//  be rejected and there is no invalid intermediate state to explain.
//

import SwiftUI

struct PhoneTabBarEditor: View {
    @Environment(TabConfigurationStore.self) private var store

    /// Draggable rows that land in the tab bar. Home takes a slot when on.
    private var draggableBarSlots: Int {
        max(0, TabConfiguration.barSlots - (store.configuration.showsHome ? 1 : 0))
    }

    var body: some View {
        List {
            Section {
                Toggle(isOn: Binding(
                    get: { store.configuration.showsHome },
                    set: { newValue in
                        var config = store.configuration
                        config.setShowsHome(newValue)
                        store.configuration = config
                    }
                )) {
                    Label {
                        Text(TabID.home.title)
                    } icon: {
                        Image(systemName: TabID.home.icon)
                            .environment(\.symbolVariants, .none)
                    }
                }
                .accessibilityIdentifier("tabeditor.home.toggle")
            } header: {
                Text("Home")
            } footer: {
                Text("Home is always the first tab when enabled.")
            }

            Section {
                ForEach(Array(store.configuration.order.enumerated()), id: \.element) { index, tab in
                    HStack {
                        Label {
                            Text(tab.title)
                        } icon: {
                            Image(systemName: tab.icon)
                                .environment(\.symbolVariants, .none)
                        }
                        Spacer()
                        Text(index < draggableBarSlots ? "Tab Bar" : "More")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityIdentifier("tabeditor.row.\(tab.rawValue)")
                }
                .onMove { source, destination in
                    var config = store.configuration
                    config.move(fromOffsets: source, toOffset: destination)
                    store.configuration = config
                }
            } header: {
                Text("Order")
            } footer: {
                Text("The first \(TabConfiguration.barSlots) entries appear in the tab bar. Everything below moves into More.")
            }

            Section {
                Label {
                    Text(TabID.settings.title)
                } icon: {
                    Image(systemName: TabID.settings.icon)
                        .environment(\.symbolVariants, .none)
                }
                .foregroundStyle(.secondary)
            } footer: {
                Text("Settings is always the last item in More.")
            }
        }
        .environment(\.editMode, .constant(.active))
        .navigationTitle("Customize Tabs")
    }
}
```

- [ ] **Step 2: Create the idiom entry point**

Create `Groo/Views/CustomizeTabsEntry.swift`:

```swift
//
//  CustomizeTabsEntry.swift
//  Groo
//
//  The one place tab customization branches on idiom. iPad keeps the system's
//  own tab customization (tabViewCustomization on MainTabView), so it gets the
//  informational list; iPhone gets the editor. Isolated to this file so no
//  feature view carries an idiom conditional.
//

import SwiftUI
import UIKit

struct CustomizeTabsEntry: View {
    var body: some View {
        if UIDevice.current.userInterfaceIdiom == .pad {
            CustomizeTabsView()
        } else {
            PhoneTabBarEditor()
        }
    }
}
```

- [ ] **Step 3: Point Settings at it**

In `Groo/Views/SettingsView.swift`, change line 60 only:

```swift
                NavigationLink {
                    CustomizeTabsEntry()
                } label: {
                    Label("Customize Tabs", systemImage: "slider.horizontal.3")
                }
```

That is the **only** edit this plan makes to `SettingsView.swift`.

- [ ] **Step 4: Build and diff**

```bash
xcodebuild -project Groo.xcodeproj -scheme Groo -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | tail -5
scripts/test.sh --unit 2>&1 | sed -n '/^Failing tests:/,/^\*\* TEST/p' > /tmp/after-task12.txt
diff /tmp/baseline-failures.txt /tmp/after-task12.txt
```

Expected: no diff.

- [ ] **Step 5: Commit**

```bash
git add Groo/Views/PhoneTabBarEditor.swift Groo/Views/CustomizeTabsEntry.swift Groo/Views/SettingsView.swift
git commit -m "feat: iPhone tab bar editor"
```

---

## Phase E — Test coverage

### Task 13: Snapshot coverage for the iPhone root

**Files:**
- Create: `GrooTests/Views/PhoneTabSnapshotTests.swift`

**Interfaces:**
- Consumes: `PhoneTabView`, `MoreView`, `PhoneTabBarEditor`, `TabConfigurationStore`, `AppRouter`, `FeatureContent`.

These use `assertRenders`, not committed reference images — the tab content pulls live data through `.task` against dead URLs, so pixels are not stable. `assertRenders` still proves the view builds and lays out without trapping.

- [ ] **Step 1: Write the tests**

Create `GrooTests/Views/PhoneTabSnapshotTests.swift`:

```swift
//
//  PhoneTabSnapshotTests.swift
//  GrooTests
//
//  The iPhone sibling renders: default configuration, a Home-disabled
//  configuration, the More screen, and the editor. Render-only (tab content
//  refreshes via .task against dead URLs), matching RootViewSnapshotTests.
//

import Foundation
import Testing
@testable import Groo

@MainActor
struct PhoneTabSnapshotTests {
    private func makeStore(json: String? = nil) throws -> (TabConfigurationStore, UserDefaults, String) {
        let suiteName = "phonetab-snapshot-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        if let json { defaults.set(json, forKey: TabConfigurationStore.defaultsKey) }
        return (TabConfigurationStore(defaults: defaults), defaults, suiteName)
    }

    @Test func phoneTabViewRendersOnly() throws {
        StubURLProtocol.reset()
        let (padService, store) = try PadViewSnapshotTests.lockedPadService()
        let passEnv = try PassServiceIntegrationTests.makeEnv(items: [])
        defer { try? FileManager.default.removeItem(at: passEnv.tempDir) }
        let (configStore, defaults, suite) = try makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }

        withPinnedDefaults(RootViewSnapshotTests.deadURLDefaults) {
            ViewRender.assertRenders(
                PhoneTabView(padService: padService,
                             syncService: PadViewSnapshotTests.offlineSync(store: store),
                             passService: passEnv.service, onSignOut: {})
                    .environment(AuthService())
                    .environment(configStore)
                    .environment(AppRouter(store: configStore, defaults: defaults)))
        }
    }

    @Test func phoneTabViewWithHomeDisabledRendersOnly() throws {
        StubURLProtocol.reset()
        let (padService, store) = try PadViewSnapshotTests.lockedPadService()
        let passEnv = try PassServiceIntegrationTests.makeEnv(items: [])
        defer { try? FileManager.default.removeItem(at: passEnv.tempDir) }
        let (configStore, defaults, suite) = try makeStore(
            json: #"{"order":["azan","pass","pad","stocks","crypto","drive","scratchpad"],"showsHome":false}"#)
        defer { defaults.removePersistentDomain(forName: suite) }

        #expect(configStore.configuration.barTabs == [.azan, .pass, .pad, .stocks])

        withPinnedDefaults(RootViewSnapshotTests.deadURLDefaults) {
            ViewRender.assertRenders(
                PhoneTabView(padService: padService,
                             syncService: PadViewSnapshotTests.offlineSync(store: store),
                             passService: passEnv.service, onSignOut: {})
                    .environment(AuthService())
                    .environment(configStore)
                    .environment(AppRouter(store: configStore, defaults: defaults)))
        }
    }

    @Test func moreViewRendersOnly() throws {
        StubURLProtocol.reset()
        let (padService, store) = try PadViewSnapshotTests.lockedPadService()
        let passEnv = try PassServiceIntegrationTests.makeEnv(items: [])
        defer { try? FileManager.default.removeItem(at: passEnv.tempDir) }
        let (configStore, defaults, suite) = try makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }

        let content = FeatureContent(
            padService: padService,
            syncService: PadViewSnapshotTests.offlineSync(store: store),
            passService: passEnv.service,
            onSignOut: {},
            onLock: {}
        )

        withPinnedDefaults(RootViewSnapshotTests.deadURLDefaults) {
            ViewRender.assertRenders(
                MoreView(configuration: configStore.configuration,
                         content: content,
                         path: .constant([]))
                    .environment(AuthService()))
        }
    }

    @Test func tabBarEditorRendersOnly() throws {
        let (configStore, defaults, suite) = try makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }

        ViewRender.assertRenders(
            NavigationStack { PhoneTabBarEditor() }
                .environment(configStore))
    }
}
```

Both helpers are already reachable from a new suite — `withPinnedDefaults` is a global function (`GrooTests/Support/ViewRenderHarness.swift:179`) and `deadURLDefaults` is a non-private `static let` (`GrooTests/Views/RootViewSnapshotTests.swift:21`). Reuse them; do not duplicate the dictionary.

- [ ] **Step 2: Run and diff**

```bash
scripts/test.sh --unit 2>&1 | sed -n '/^Failing tests:/,/^\*\* TEST/p' > /tmp/after-task13.txt
diff /tmp/baseline-failures.txt /tmp/after-task13.txt
```

Expected: no diff (four new tests pass).

- [ ] **Step 3: Commit**

```bash
git add GrooTests/Views/PhoneTabSnapshotTests.swift GrooTests/Views/RootViewSnapshotTests.swift
git commit -m "test: snapshot coverage for iPhone tab root, More and editor"
```

---

### Task 14: UI test helpers and tab navigation

**Files:**
- Modify: `GrooUITests/UITestHelpers.swift:19-27` (launch), `:43-63` (`openTab`)
- Modify: `GrooUITests/TabNavigationUITests.swift` (whole file)

**Interfaces:**
- Consumes: `TabConfigurationStore.defaultsKey` ("phoneTabBar"), `MoreView`'s `more.row.<rawValue>` identifiers, `PhoneTabBarEditor`'s `tabeditor.*` identifiers.
- Produces: `UITest.launchApp(selectedTab:phoneTabBar:)`, rewritten `UITest.openTab`.

- [ ] **Step 1: Extend the launch helper**

In `GrooUITests/UITestHelpers.swift`, replace `launchApp` with:

```swift
    /// Fresh, hermetic app instance. `selectedTab` and `phoneTabBar` use the
    /// NSArgumentDomain UserDefaults override — the app opens directly on that
    /// tab with that bar configuration, no navigation needed. `phoneTabBar`
    /// takes the JSON TabConfigurationStore persists,
    /// e.g. `{"order":["azan","pass","pad","stocks","crypto","drive","scratchpad"],"showsHome":true}`.
    static func launchApp(selectedTab: String? = nil, phoneTabBar: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--uitest"]
        if let selectedTab {
            app.launchArguments += ["-selectedTab", selectedTab]
        }
        if let phoneTabBar {
            app.launchArguments += ["-phoneTabBar", phoneTabBar]
        }
        app.launch()
        return app
    }
```

- [ ] **Step 2: Rewrite `openTab` for the app-owned More**

Replace `openTab` with:

```swift
    /// Select a tab by title, falling back to the app-owned More screen.
    /// Unlike the old system overflow (a UIKit table), More is a SwiftUI List,
    /// so its rows are buttons carrying `more.row.<rawValue>` identifiers.
    static func openTab(_ app: XCUIApplication, _ title: String, file: StaticString = #filePath, line: UInt = #line) {
        let direct = app.tabBars.buttons[title]
        if direct.exists {
            direct.tap()
            return
        }
        let more = app.tabBars.buttons["More"]
        if more.exists {
            more.tap()
            let entry = app.buttons["more.row.\(identifier(for: title))"].firstMatch
            if entry.waitForExistence(timeout: timeout) {
                entry.tap()
                return
            }
        }
        XCTFail("Tab \(title) not reachable from the tab bar:\n\(app.tabBars.firstMatch.debugDescription)", file: file, line: line)
    }

    /// Map a tab's display title to its TabID raw value.
    /// Mirrors TabID.title in Groo/Views/MainTabView.swift — keep in sync.
    private static func identifier(for title: String) -> String {
        switch title {
        case "Home": "home"
        case "Stocks": "stocks"
        case "Wallet": "crypto"
        case "Azan": "azan"
        case "Pad": "pad"
        case "Pass": "pass"
        case "Drive": "drive"
        case "Scratchpad": "scratchpad"
        case "Settings": "settings"
        default: title.lowercased()
        }
    }
```

- [ ] **Step 3: Rewrite the tab navigation test**

Replace `GrooUITests/TabNavigationUITests.swift` with:

```swift
//
//  TabNavigationUITests.swift
//  GrooUITests
//
//  Every tab renders its known marker without crashing, reached either from
//  the tab bar or the app-owned More screen. First Azan visit may pop the
//  system location alert — dismissed via springboard, sleep-free.
//

import XCTest

final class TabNavigationUITests: XCTestCase {
    func testEveryTabRendersWithoutCrashing() {
        let app = UITest.launchApp(selectedTab: "home")
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: UITest.timeout))

        let visits: [(tab: String, marker: XCUIElement)] = [
            ("Stocks", app.staticTexts["Stock Portfolio"]),          // empty-portfolio onboarding
            ("Wallet", app.staticTexts["Ethereum Wallet"]),          // wallet onboarding
            ("Azan", app.navigationBars.staticTexts["Azan"]),        // principal toolbar title
            ("Pad", app.staticTexts["Pad is Locked"]),
            ("Pass", app.staticTexts["Pass is Locked"]),
            ("Drive", app.staticTexts["Coming Soon"]),
            ("Scratchpad", app.staticTexts["Scratchpad Locked"]),
            // The app owns More now, so SwiftUI's .navigationTitle survives —
            // the old workaround of matching a row label is no longer needed.
            ("Settings", app.navigationBars.staticTexts["Settings"]),
        ]

        for (tab, marker) in visits {
            UITest.openTab(app, tab)
            if tab == "Azan" {
                UITest.dismissSystemAlertIfPresent()
            }
            XCTAssertTrue(marker.waitForExistence(timeout: UITest.timeout), "\(tab) tab did not render its marker")
            XCTAssertEqual(app.state, .runningForeground, "\(tab) tab crashed the app")
        }

        // And back to Home (empty-state stocks card)
        UITest.openTab(app, "Home")
        XCTAssertTrue(app.staticTexts["Add your first stock"].waitForExistence(timeout: UITest.timeout))
        XCTAssertEqual(app.state, .runningForeground)
    }

    func testDefaultConfigurationPutsHomeAzanPassPadInTheBar() {
        let app = UITest.launchApp(selectedTab: "home")
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: UITest.timeout))

        for title in ["Home", "Azan", "Pass", "Pad", "More"] {
            XCTAssertTrue(app.tabBars.buttons[title].exists, "\(title) missing from the tab bar")
        }
        for title in ["Stocks", "Wallet", "Drive", "Scratchpad", "Settings"] {
            XCTAssertFalse(app.tabBars.buttons[title].exists, "\(title) should live in More, not the tab bar")
        }
    }

    func testSeededConfigurationChangesTheBar() {
        let app = UITest.launchApp(
            selectedTab: "more",
            phoneTabBar: #"{"order":["drive","scratchpad","stocks","crypto","azan","pass","pad"],"showsHome":false}"#)
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: UITest.timeout))

        for title in ["Drive", "Scratchpad", "Stocks", "Wallet", "More"] {
            XCTAssertTrue(app.tabBars.buttons[title].exists, "\(title) missing from the seeded tab bar")
        }
        XCTAssertFalse(app.tabBars.buttons["Home"].exists, "Home should be absent when showsHome is false")
        XCTAssertTrue(app.buttons["more.row.pass"].waitForExistence(timeout: UITest.timeout),
                      "Pass should have fallen past the cut into More")
    }

    func testSettingsReachesTheTabBarEditor() {
        let app = UITest.launchApp(selectedTab: "more")
        XCTAssertTrue(app.buttons["more.row.settings"].waitForExistence(timeout: UITest.timeout))
        app.buttons["more.row.settings"].tap()

        let customize = app.buttons["Customize Tabs"]
        XCTAssertTrue(customize.waitForExistence(timeout: UITest.timeout))
        customize.tap()

        XCTAssertTrue(app.switches["tabeditor.home.toggle"].waitForExistence(timeout: UITest.timeout),
                      "the iPhone editor did not open")
        // Match the identifier wherever SwiftUI surfaces it in the hierarchy —
        // never fall back to a bare title like "Azan", which the tab bar also
        // carries and which would let this assertion pass with no editor.
        let orderRow = app.descendants(matching: .any)["tabeditor.row.azan"].firstMatch
        XCTAssertTrue(orderRow.waitForExistence(timeout: UITest.timeout),
                      "the draggable order section did not render")
    }
}
```

- [ ] **Step 4: Run the UI tests**

```bash
scripts/test.sh --all 2>&1 | sed -n '/^Failing tests:/,/^\*\* TEST/p'
```

Expected: `TabNavigationUITests` passes all four cases; the rest of the failure set matches `/tmp/baseline-failures.txt`.

- [ ] **Step 5: Commit**

```bash
git add GrooUITests/UITestHelpers.swift GrooUITests/TabNavigationUITests.swift
git commit -m "test: UI coverage for app-owned More tab and bar configuration"
```

---

### Task 15: Documentation and final verification

**Files:**
- Modify: `ios/CLAUDE.md` (Gotchas section)

- [ ] **Step 1: Record the stack-ownership rule**

Add to the Gotchas section of `ios/CLAUDE.md`:

```markdown
**Feature screens own no root `NavigationStack`.** `FeatureContent.view(for:)`
returns stack-free content; the host supplies the stack — `MainTabView` and
`PhoneTabView` per tab, `MoreView` once for every pushed destination. Adding a
root stack back to a feature screen produces a doubled navigation bar the
moment that feature is dragged into More. `.navigationTitle`, `.toolbar` and
`.navigationDestination` all seek an ancestor stack, so they belong on the
screen, not the host. Two screens deliberately hide the inherited bar because
they never had one — `PadUnlockView` and `ScratchpadView`'s regular branch.

**iPhone vs iPad roots branch on device idiom, once, in `ContentView`.** Never
convert this to `horizontalSizeClass`: size class flips at runtime (rotation,
Slide Over, Stage Manager), and each flip would restructure the `TabView` and
reset tab selection and per-tab state.
```

- [ ] **Step 2: Full verification pass**

```bash
xcodebuild clean -project Groo.xcodeproj -scheme Groo >/dev/null 2>&1
xcodebuild -project Groo.xcodeproj -scheme Groo -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | tail -5
scripts/test.sh --all 2>&1 | sed -n '/^Failing tests:/,/^\*\* TEST/p' > /tmp/final-failures.txt
diff /tmp/baseline-failures.txt /tmp/final-failures.txt
```

Expected: build succeeds. The diff should show **only removals** — `TabNavigationUITests` cases that were in the baseline and now pass — and no additions. Re-run any suspicious date-dependent failure at a different time of day before blaming this work.

- [ ] **Step 3: Verify iPad by hand**

```bash
xcodebuild -project Groo.xcodeproj -scheme Groo -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M4)' build 2>&1 | tail -5
```

Then run the app on an iPad simulator and confirm: nine tabs in the sidebar, system customization still works via long-press, Settings opens with its title, Scratchpad shows the side-by-side layout with no stray navigation bar, and the Pad lock screen has no navigation bar.

- [ ] **Step 4: Commit**

```bash
git add ios/CLAUDE.md
git commit -m "docs: record navigation stack ownership and idiom branch rules"
```

---

## Notes for the implementer

- **Phase A must not change a single pixel.** If a snapshot reference fails in Tasks 1-5, the hoist is wrong. Re-recording the reference hides the bug.
- **`WalletOnboardingView` has three `NavigationStack`s.** Only the one at `:27` — directly inside `body` — is removed. The other two are sheet roots.
- **`barTabs` is never empty.** `TabConfiguration`'s init always refills `order` to all seven reorderable features, so a configuration with Home off still yields four bar tabs. The `?? .more` fallback in `AppRouter.resolve` exists only so the code has no force-unwrap.
- **`phoneSelection` and `padSelection` persist to SEPARATE keys** — `phoneSelectedTab` and `selectedTab` respectively. An earlier revision shared one key on the reasoning that only one is ever bound to a live `TabView`; that was wrong. Both persist on `didSet`, and `open(_:)` writes `padSelection` then `phoneSelection`, so for a More-resident feature the second write persists `"more"`, which `TabID(rawValue:)` cannot parse — iPad's restore then falls back to `.home`, losing tab restoration for five of nine tabs. Keep the keys separate; do not "simplify" them back together.
