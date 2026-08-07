# iPhone "More" Tab — Design

**Date:** 2026-08-08
**Status:** Approved, ready for planning
**Scope:** `ios/` — main app only, no extensions

## Summary

Replace the system-generated "More" overflow on iPhone with an app-owned More
tab, and give the user control over which features occupy the tab bar.

iPad is untouched: it keeps today's `MainTabView` verbatim — nine `Tab`s,
`.tabViewStyle(.sidebarAdaptable)`, `.tabViewCustomization`, and whatever
SwiftUI decides to do with that.

## Motivation

`MainTabView` declares nine tabs. On iPhone, iOS silently collapses tabs five
through nine into a system More tab implemented as a UIKit navigation
controller. That wrapper drops SwiftUI's `.navigationTitle`, which is already
documented as a workaround in `GrooUITests/TabNavigationUITests.swift:26-30` —
the Settings assertion has to match a row label because the navigation bar
keeps the identifier "More".

Owning the More screen recovers the navigation title, gives real SwiftUI
navigation, and lets the overflow be ordered deliberately rather than by
declaration order.

## Non-goals

- Any iPad-specific work. iPad renders through the existing code path.
- Changes to what any feature screen *does*. Screens change structurally
  (see Stack hoisting) but not behaviorally.
- Extension targets. `Shared/` is not touched, so no `project.pbxproj`
  registration is required.

## Decisions

### Branch on device idiom, not size class

`UIDevice.current.userInterfaceIdiom == .pad` selects the iPad sibling;
everything else gets the iPhone sibling.

Idiom is fixed for the process lifetime. Size class is not — it flips on
rotation, Slide Over and Stage Manager, and each flip would restructure the
`TabView`, resetting selection, per-tab scroll position and any `@State` held
in tab content. Idiom removes that entire class of bug: the branch is evaluated
once at launch and never re-evaluated.

The cost is that an iPad in a compact window does not get the enhanced More
screen. It gets `.sidebarAdaptable`'s own collapse to a tab bar with the system
More overflow — that is, exactly what ships today. Not a regression.

### Two siblings, one content factory

The branch happens once, at the top. The iPad path is the literal current
`MainTabView`. The iPhone path is a separate view. Neither contains an
`isPad` conditional in its body.

Both consume one shared `featureContent(for: TabID)` factory that maps a
`TabID` to its screen. That factory is the single place where the mapping
lives; the siblings differ only in how they arrange the results.

### Tab bar composition

The eight feature tabs — everything in `TabID` except `settings` — form a
single ordered list. The first four entries become the tab bar; slot five is
More; everything after the cut falls into More's list.

- **Home** is pinned first within that list and is toggleable. Off means gone
  entirely — not in the bar, not in More. It is never reorderable.
- The remaining seven (Stocks, Wallet, Azan, Pad, Pass, Drive, Scratchpad) are
  freely reorderable.
- **Settings** is not part of the ordered list at all. It is always the final
  row of More's list, always present, never reorderable, never disabled, and
  can never reach the tab bar.

Defaults: Home on, order `[home, azan, pass, pad, stocks, crypto, drive,
scratchpad]`. That yields a Home/Azan/Pass/Pad tab bar, with Stocks, Wallet,
Drive, Scratchpad and Settings in More.

With Home enabled More holds five rows; with Home disabled, four.

## Architecture

### Stack hoisting

Every feature screen currently owns one root `NavigationStack` at the top of
its `body`:

| Screen | Root stack |
|---|---|
| Home | `HomeView` |
| Stocks | `StockPortfolioView:21` / `StockOnboardingView:17` — one per branch |
| Wallet | `PortfolioView:51` / `WalletOnboardingView:27` — one per branch |
| Azan | `AzanView:31` |
| Pad | `PadView:40` |
| Pass | `PassView:23` |
| Scratchpad | `ScratchpadTabView:47` |
| Drive | `DrivePlaceholderView` |
| Settings | `SettingsView` |

**All of these root stacks move up to the host.** Screens become
unconditionally stack-free, keeping their `.navigationTitle`, `.toolbar` and
`.navigationDestination` in place — those modifiers seek an ancestor stack and
are inert without one, so a stack-free screen is self-describing and renders
correctly in either host with no knowledge of its context.

```swift
// PadView today                    // PadView after
NavigationStack {                   List { … }
    List { … }                          .navigationTitle("Pad")
        .navigationTitle("Pad")         .sheet(…) { … }
        .sheet(…) { … }
}
```

Hosts supply the stack:

```swift
// iPad tab, and iPhone primary tab
Tab(value: tab) { NavigationStack { featureContent(for: tab) } }

// iPhone More — one stack, every destination in one line
NavigationStack {
    List { rows }
        .navigationDestination(for: TabID.self) { featureContent(for: $0) }
}
```

**Sheet-local `NavigationStack`s are untouched** (`PassView:85`,
`AzanView:91,102`, `StockPortfolioView:159,177`, `PortfolioView:214,231,240`,
`WalletOnboardingView:127,226`). Those are sheet roots and remain.

Hoisting is behavior-neutral on iPad: the stack ends up at the same position in
the view tree. For Stocks and Wallet it is a strict improvement — today the
stack sits *inside* the `if hasHoldings` / `if hasWallets` switch, so adding a
first holding tears down and rebuilds the whole navigation stack. One stack
outside the conditional fixes that.

All eight features need this, not only the five that start out in More, because
any feature can be dragged across the cut line.

**Rejected alternative:** an `isInsideMore` flag on each screen deciding whether
to wrap itself. It couples every feature to navigation topology, has to be
plumbed through every initializer, `#Preview` and snapshot test, and — decisively
— flips at runtime when a tab is reordered. `if flag { NavigationStack {
Content() } } else { Content() }` are two branches of a `_ConditionalContent`
with different view identity, so flipping it destroys `Content`'s `@State`. A
screen would silently reset because the user dragged a row in a settings page.

### Selection type

`TabID` stays exactly the nine features it is today. No `.more` case is added —
that would force iPad's `featureContent(for:)` to carry a dead branch.

iPhone selection gets its own type:

```swift
enum PhoneSelection: Hashable { case feature(TabID), more }
```

Persistence stays on the existing `selectedTab` `@AppStorage` key, encoding
`.feature(x)` as `x.rawValue` and `.more` as `"more"`. One key, backward
compatible with anything already persisted, and `UITest.launchApp(selectedTab:
"more")` works without a new launch argument.

### Routing

`@AppStorage("selectedTab")` is already acting as a router: `HomeView` writes it
at `:77` (Stocks), `:129` (Wallet), `:176` and `:224` (Pad), `:238` (Azan).

That becomes an `AppRouter` with `open(_ tab: TabID)`, resolved against the
*live* configuration rather than a hardcoded set:

- iPad — set selection to the tab.
- iPhone, tab is in the bar — set selection to `.feature(tab)`.
- iPhone, tab is past the cut — set selection to `.more` and push `tab` onto
  More's path.

`HomeView` calls `router.open(.stocks)` and stays ignorant of idiom and
configuration.

**Reconciliation.** When the configuration changes, More's navigation path is
cleared. At launch, a persisted selection that is no longer valid — a demoted
feature, or Home when Home is disabled — resolves to the first tab in the bar.

### More screen

A `List` of destinations and nothing else. Its single job is to be an index of
screens; it is not a hybrid index-plus-settings-form. Rows are the features
past the cut, in order, with Settings pinned last. Each row pushes via the
single `navigationDestination` above.

Settings therefore remains its own pushed screen, identical on both idioms.
This costs one extra tap to reach Prayer Settings (More → Settings → Prayer)
and buys one code path and a clean boundary.

### Tab bar editor

A pushed page — not a sheet — reached from More → Customize Tabs. Three zones:

1. **Home** — a toggle row at the top, outside the draggable region.
2. **Order** — the seven reorderable features, dragged freely. A labelled
   separator marks the cut so the user can see which rows are in the tab bar
   and which fall into More. Home occupies a bar slot when enabled, so the
   separator sits after the third draggable row with Home on, and after the
   fourth with Home off — it moves when the toggle flips.
3. **Settings** — a frozen row at the bottom, non-draggable.

There is no promote/demote action and no add/remove: every permutation the user
can produce is valid by construction, so there is no rejected tap, no alert, and
no invalid intermediate state.

Two sibling views again: `PhoneTabBarEditor` for iPhone, and the existing
`CustomizeTabsView` unchanged for iPad, where the system still owns
customization. Neither branches internally.

Reordering a feature across the cut changes the `TabView`'s structure, so that
screen's state resets. This is acceptable — it follows a deliberate user action
in an editor, and the alternative (preserving state across a structural change)
is not achievable without the rejected conditional-wrapper approach.

### Storage and invariants

`@AppStorage("phoneTabBar")` holds a JSON-encoded ordered array of `TabID`
plus the Home flag.

The store validates on read and never hands out an invalid configuration:

- Every non-pinned feature appears exactly once.
- Unknown or removed identifiers are dropped.
- Missing features are appended in default order.
- Home is first or absent; Settings is last.
- Corrupt or undecodable data falls back to the default configuration.

Because the store guarantees this, no consumer needs to defend against a
malformed configuration.

## Testing

**Unit**

- Store invariants: default, garbage decode, duplicates, unknown identifiers,
  missing entries, Home-off ordering, Settings pinning.
- Router mapping: in-bar feature selects directly; past-cut feature selects
  More and pushes; configuration change clears the path; launch restore of an
  invalid or demoted selection falls back to the first tab.
- `PhoneSelection` encode/decode round-trip against the `selectedTab` key,
  including legacy values already on disk.

**UI**

- New `-phoneTabBar` NSArgumentDomain override alongside the existing
  `-selectedTab` one (`UITestHelpers.swift:19-27`), so a test can seed any
  configuration and assert the resulting bar.
- `UITest.openTab` rewritten. Its current comment describes the system More as
  a UIKit table matched via `app.tables.cells.staticTexts`
  (`UITestHelpers.swift:50-52`); the replacement is a SwiftUI `List`, so row
  matching changes.
- `TabNavigationUITests` updated for the new structure, and its Settings
  assertion returns to `app.navigationBars["Settings"]` — the UIKit wrapper
  that swallowed the title is gone.
- Editor coverage: toggle Home off and assert the bar recomposes; drag a
  feature across the cut and assert it moves between bar and More.

**Snapshot**

`RootViewSnapshotTests:174` constructs `MainTabView` directly; that becomes the
iPad sibling. Add a phone-sibling case, and a More-screen case.

## Risks

- **Eight screens change shape at once.** The edit is mechanical and identical
  in each, but it touches every feature. Existing snapshot and UI tests are the
  safety net; the pre-existing failure set must be diffed, not counted (see
  `ios/CLAUDE.md`, "Test suite baseline").
- **iPad regression risk is the thing to watch.** Hoisting is behavior-neutral
  in theory; the iPad snapshot cases are what prove it.
- **`Drive` is still `DrivePlaceholderView`.** A user can drag "Coming Soon"
  into the tab bar. That is their choice and needs no special handling.
