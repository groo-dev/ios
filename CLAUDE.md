# CLAUDE.md — Groo iOS

Guidance for Claude Code (claude.ai/code) when working in this repository.

## Structure

SwiftUI app plus five app extensions, sharing code through `Shared/`.

- `Groo/` — main app (SwiftUI, `@Observable`/`@MainActor`, actor-based services)
- `Shared/` — code shared between the app and extensions
- `GrooAutoFill/` — AutoFill credential provider (passwords + passkeys)
- `KeyboardExtension/`, `ShareExtension/`, `WidgetExtension/` — other extensions
- `GrooTests/` — unit tests (Swift Testing), `GrooUITests/` — UI tests

## Commands

```bash
# Build (simulator)
xcodebuild -project Groo.xcodeproj -scheme Groo \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build

# Tests
scripts/test.sh              # --unit (default)
scripts/test.sh --all --coverage
```

## Gotchas

**`Shared/` is not a filesystem-synchronized group.** A new file in `Shared/`
compiles into nothing until it is registered in `project.pbxproj` for every
consuming target. Use `scripts/register_shared_file.rb` (idempotent) rather
than editing the pbxproj by hand. `Groo/`, `GrooAutoFill/`, `GrooTests/` and
the other extension folders *are* synchronized, so new files there are picked
up automatically.

**Register `Shared/` files to `Groo GrooAutoFill` — never to `GrooTests`.**
The test bundle hosts the app and reaches shared code through
`@testable import Groo`. Adding the test target compiles a *second* copy of the
file into a module that cannot see the rest of `Shared/`, so the file fails with
`cannot find type ... in scope` for its own dependencies while the app target
builds fine. Every existing shared file follows this — check one before
inventing a target list:

```bash
ruby -e 'require "xcodeproj"; p_ = Xcodeproj::Project.open("Groo.xcodeproj");
  puts p_.targets.select { |t| t.source_build_phase.files.any? { |b|
    b.file_ref && b.file_ref.path == ARGV[0] } }.map(&:name).join(", ")' SharedPassModels.swift
# => Groo, GrooAutoFill
```

**There are several DerivedData directories for this project, and most are
abandoned.** As of 2026-08-25 there are six `Groo-*` folders; the stale ones
still hold `.appex` binaries from early August. `find ~/Library/Developer/Xcode/DerivedData/Groo-*/... | head -1`
picks whichever sorts first, which is usually **not** the one the last build
wrote to. Reading a stale folder makes a perfectly fresh build look like the
embed-step-didn't-re-run trap below. Resolve the active directory first (sort by
mtime, or take it from the build log's `Build/Products` path), and remember the
scheme builds **Release**, so `Debug-iphonesimulator` is stale by default:

```bash
ls -dt ~/Library/Developer/Xcode/DerivedData/Groo-*/Build/Products/Release-iphonesimulator/Groo.app | head -1
# then confirm the embedded appex really contains your change:
nm -a "$APP/PlugIns/GrooAutoFill.appex/GrooAutoFill" | grep -c YourNewSymbol
```

**Clean-build after changing an extension's `Info.plist` or entitlements.**
The extension target rebuilds, but the copy embedded at
`Groo.app/PlugIns/<Name>.appex` can stay stale — the embed step does not
re-run. You will test the old plist and wrongly conclude a change had no
effect. Run `xcodebuild clean` first, and verify against the *embedded* copy:

```bash
plutil -p "$(find ~/Library/Developer/Xcode/DerivedData/Groo-*/Build/Products \
  -path '*Groo.app/PlugIns/GrooAutoFill.appex/Info.plist' | head -1)"
```

**Xcode Run installs the Release configuration**, not Debug — the scheme's
`LaunchAction` is set to `Release`. This flips `Config`/`SharedConfig` to the
non-`.debug` keychain service (`dev.groo.ios`), app group
(`group.dev.groo.ios`) and keychain access group, and uses production APS.
When reasoning about which keychain item or container a device build touches,
assume Release unless you have checked.

**Extension logs never appear in Xcode's console.** Xcode attaches to the app
process only; extensions run separately. Reading them needs a device log
archive (`sudo log collect --device-udid <udid>`, root required) — so for a
quick diagnosis it is often faster to surface state in the extension's own UI.

**Biometric keychain reads must not run on the main thread.**
`SecItemCopyMatching` on a biometry-gated item blocks until the Face ID prompt
resolves; on the main thread that block also prevents UIKit from presenting
the UI the prompt requires, and the read fails with
`errSecInteractionNotAllowed` (-25308). In extensions, also wait until the
view is actually on screen (`viewDidAppear`) before prompting. See
`SharedKeychain.loadEncryptionKeyOffMainThread`.

**Passkey authenticator data must set BE and BS.** Apple requires the BE
(backup eligible, `0x08`) and BS (backup state, `0x10`) flags from third-party
credential providers — without them the relying party rejects the ceremony with
a generic WebAuthn `NotAllowedError` that names no cause. Registration uses
`0x5d` (UP|UV|BE|BS|AT), assertions `0x1d` (UP|UV|BE|BS). See
`SharedPasskeyCrypto.syncedCredentialFlags`. Note the `pass` browser extension
emits `0x45`/`0x05` and works anyway, because browsers do not enforce this — it
is **not** a valid reference for what Apple accepts.

**AutoFill capability keys live under `NSExtensionAttributes`.**
`ASCredentialProviderExtensionCapabilities` must be nested at `NSExtension >
NSExtensionAttributes`. Declared one level up it is silently ignored: password
AutoFill keeps working (it is the default) while passkeys are never offered.
Pinned by `GrooTests/Features/Pass/AutoFillCapabilitiesTests.swift`.

**Feature screens own no root `NavigationStack`.** `FeatureContent.view(for:)`
returns stack-free content; the host supplies the stack — `MainTabView` and
`PhoneTabView` per tab, `MoreView` once for every pushed destination. Adding a
root stack back to a feature screen produces a doubled navigation bar the
moment that feature is dragged into More. `.navigationTitle`, `.toolbar` and
`.navigationDestination` all seek an ancestor stack, so they belong on the
screen, not the host. Two screens deliberately hide the inherited bar because
they never had one — `PadUnlockView` and `ScratchpadView`'s regular (iPad)
branch. `ScratchpadUnlockView` (the locked state inside `ScratchpadTabView`)
does **not** hide it — it carries a real `.navigationTitle("Scratchpad")` and
relies on the host's stack to render it.

**iPhone vs iPad roots branch on device idiom, once, in `ContentView`.** Never
convert this to `horizontalSizeClass`: size class flips at runtime (rotation,
Slide Over, Stage Manager), and each flip would restructure the `TabView` and
reset tab selection and per-tab state. Be precise about "once" — `body`
re-executes on every render like any SwiftUI view, so the branch is evaluated
repeatedly, not a single time. What's actually true is that
`UIDevice.current.userInterfaceIdiom` is a runtime constant, so every
re-evaluation takes the same branch and SwiftUI never tears down or rebuilds
the chosen tab view as a result.

**`NSArgumentDomain` silently drops any launch-argument value starting with
`{`.** Foundation tries to parse such a value as old-style plist syntax; when
that fails (a JSON payload never matches it) the argument is discarded
outright rather than falling back to a plain string — even
`UserDefaults.object(forKey:)` comes back `nil`. This is why
`UITestMode.seedPhoneTabBarIfProvided()` parses `argv` directly instead of
relying on `-phoneTabBar <json>` reaching `UserDefaults` through the ordinary
launch-argument seam. Plain values like `-selectedTab home` or
`-phoneSelectedTab more` are unaffected — they never start with `{`.

**Debug and Release install under different bundle IDs**
(`dev.groo.ios.debug` vs `dev.groo.ios`), and `UITestMode.isActive` is
`#if DEBUG`-gated, so a Release build silently ignores `--uitest` — it just
runs as an ordinary, unseamed launch. Combined with the already-documented
"Xcode Run installs Release" gotcha above, this makes manual simulator
verification easy to get wrong: you can spend a long time inspecting an app
that isn't the one you just built, or an app that ignores your launch
arguments entirely. Check the installed bundle ID (or just rebuild with
`xcodebuild ... build` and reinstall) before trusting what you see.

**`withPinnedDefaults` mutates `UserDefaults.standard` in place.** It saves
and restores the previous value around the body block, but the mutation is
real and global for the duration of that block, so any test suite calling it
must sit under the `NetworkStubbedSuites(.serialized)` umbrella
(`extension NetworkStubbedSuites { @Suite(.serialized) struct … }`) or it
races sibling suites touching the same defaults. All current callers
(`AzanViewSnapshotTests`, `CryptoViewSnapshotTests`, `StockPortfolioManagerTests`,
`StocksViewSnapshotTests`, `PhoneTabSnapshotTests`, `RootViewSnapshotTests`) do
this — keep new callers under the same umbrella.

**The crypto stack is Trust Wallet Core, pinned through a local wrapper, and
the wrapper is load-bearing.** `Packages/WalletCoreBinary/Package.swift`
declares two `binaryTarget`s by URL and checksum. It exists because the
`Package.swift` *committed to* `trustwallet/wallet-core` is stale: at tag 4.8.4
it still points at the **4.2.9** binaries, under an asset name that release no
longer publishes. Adding the package the ordinary way in Xcode therefore
resolves 4.8.4 and installs 4.2.9, silently and without error. The correct
manifest ships as a release **asset**. To upgrade, take the URLs and checksums
from there, never from the repository tree:

```bash
gh release download <tag> --repo trustwallet/wallet-core --pattern Package.swift
```

**`import WalletCore` alone is not enough to build a signing input.**
`EthereumSigningInput` and its siblings are SwiftProtobuf messages, and under
`MemberImportVisibility` their `.with { }` builders resolve only when the
defining module is imported directly — so `WalletManager.swift` also imports
`WalletCoreSwiftProtobuf`. WalletCore's own tests import just `WalletCore`
because they predate the rule; copying their import list reproduces a
confusing "static method 'with' is not available" error.

**`AnySigner.sign` does not throw.** A failed sign returns a `SigningOutput`
carrying a non-zero `error` (`TW.Common.Proto.SigningError`, where `OK = 0`)
and an empty `encoded`. Without an explicit check, a signing failure surfaces
as a silently empty transaction rather than an error — see the guard at the end
of `WalletManager.signTransaction`.

**BigInt is a direct dependency now, deliberately.** `BigUInt` used to reach
the app transitively through web3swift; nothing declared it. It is in the
project's own package list so that removing another dependency cannot take it
away again. `CryptoSwift` and `secp256k1` arrived the same way and are simply
gone — `Data.toHexString()` and `Data.fromHex` were theirs, and the WalletCore
equivalents (`Data.hexString`, `Data(hexString:)`) replaced the five call
sites.

**`scripts/test.sh` takes `GROO_TEST_DESTINATION`.** A bare device name stops
being a unique destination the moment two runtimes offer the same model, and
xcodebuild then refuses the run and prints every simulator on the machine —
which reads as a catastrophic failure rather than an ambiguous argument. Pin
one with a UDID:

```bash
GROO_TEST_DESTINATION="platform=iOS Simulator,id=<udid>" scripts/test.sh --unit
```

## Test suite baseline

**The 2026-08-08 baseline below no longer describes this toolchain.** On
2026-10-17, the first run after the project became buildable under Xcode 27,
the unit suite failed **34 lines / 27 unique names** — every one of them an
image snapshot, with zero logic-test failures.

**They do not share one cause, and that matters more than the count.** Measured
per-image (pixels changed, and maximum per-channel delta) they fall into three
populations:

| Population | Signature | Examples | Verdict |
|---|---|---|---|
| **Async race** | ~40–73% of pixels, the view captured mid-load | `PassViewSnapshotTests.healthReportStates` (both cases) | **Never re-record.** The snapshot holds a "Analyzing passwords…" spinner where the reference holds the finished report |
| **Layout shift** | whole-view offset of a few px, or an absent large title | `RootPilotSnapshotTests.drivePlaceholder`, `CryptoViewSnapshotTests.walletOnboardingMain`, `RootViewSnapshotTests.settingsViewWithBackupDate` | OS drift against references dated 2026-07-06 |
| **Antialiasing** | maxdelta ≤ 8, often invisible side by side | `PassViewSnapshotTests.formEditModes.*`, `StocksViewSnapshotTests.addTransactionModes` | Noise |

The race is the one worth acting on. `PasswordHealthView.task` calls a fully
**synchronous** `analyzePasswords()`, so nothing is slow — the task has simply
not fired by the time `ViewRender.settledImage` draws, and that helper settles
by counting `Task.yield()`s rather than by waiting for a condition. A fixed
yield count encodes an assumption the test cannot check, and when it stops
holding the test does not error: it quietly asserts against a loading state.
**Pumping the main run loop between yields was tried and does not fix it** —
the diff came back identical to the byte, so the cause lies elsewhere and is
still open.

To triage these, measure rather than squint — two images that look identical
side by side can differ by a 6px offset, and one that looks like a rendering
change can be a spinner. A script that walks `__Snapshots__` against the
simulator's `tmp/<SuiteName>/` artifacts and reports percent-changed plus
maxdelta per image is how the table above was built.

Be careful what this does and does not establish. No before/after comparison
was possible, because **the app did not build at all on Xcode 27** until that
day — nothing had run this suite on this toolchain before. 34 is a first
measurement, not a regression against a comparable baseline. It was, however,
stable across the WalletCore swap and three dependency bumps: the failing
multiset was byte-identical before and after, which is the useful property.

Re-recording these references is deliberate, separate work — it would bake in
whatever the new rendering is, so it wants a human looking at the diffs.

The older baseline is kept below because its two traps still apply.

As of 2026-08-08 the unit suite has 12 unique pre-existing failures (18
failing-test *lines* — see the parameterized-test trap below): view snapshot
tests, plus **date-dependent** cases whose count varies by when you run.

```
AzanViewSnapshotTests.prayerTimeRowVariants()
PadViewSnapshotTests.padListPopulated()
PadViewSnapshotTests.padItemRowVariants()
PassViewSnapshotTests.itemDetailEveryType()   (x7 lines, 1 test name — manual loop)
PassViewSnapshotTests.itemDetailCorrupted()
PassViewSnapshotTests.itemDetailExtraStates()
RootViewSnapshotTests.globalLockView()
RootViewSnapshotTests.settingsView()
RootViewSnapshotTests.settingsViewWithBackupDate()
ScratchpadViewSnapshotTests.scratchpadListStates()
StocksViewSnapshotTests.stockPriceChartVariants()
PrayerTimeServiceTests.afterIshaNextIsTomorrowsFajrAndIshaRunsUntilIt()
```

**The failing-set line count is not the number of failing tests.**
`PassViewSnapshotTests.itemDetailEveryType` is a single test function with a manual
`for` loop over vault item types, calling `assertViewSnapshot` once per type, all
sharing the same test name — it contributes 7 lines under one test name. Comparing
line counts across runs (18 vs. 17 vs. 16) looks like a regression or a fix when
it's actually noise; compare the *set of unique test names*, or the full multiset
of lines against a previous multiset, never a bare count.

The date-dependent ones are the other trap — the baseline is not a fixed set
either:

- `PrayerTimeServiceTests.afterIshaNextIsTomorrowsFajrAndIshaRunsUntilIt`
- `AzanNotificationServiceTests.jumuahReminderScheduledWhenEnabled` — only
  failed on a Friday after Dhuhr; fixed 2026-08-07, and `jumuahReminderTime`
  now rolls past an elapsed Friday.

For the UI suite, expect exactly one pre-existing failure. **Which one has
changed** — re-confirm rather than trusting this line:

- 2026-08-25: `PassCrudUITests.testLoginItemLifecycleCreateEditDetailTrashRestore`
  fails at `PassCrudUITests.swift:41-42` — the leading-swipe `Edit` button is
  never found. Confirmed pre-existing by running it on `main` (`6b467dd`), where
  it fails identically. `PassUnlockUITests.testUnlockThenLockVaultRelocks`
  passed in the same run.
- Earlier (2026-08-08): `PassUnlockUITests.testUnlockThenLockVaultRelocks` was
  the failing one instead.

Both are swipe/timing-sensitive, so the failing member of this pair moves.
Confirm against the merge base before blaming a branch.

So diff the failing *set*, never the count, and re-run a suspicious failure at a
different time of day before blaming your change:

```bash
scripts/test.sh --unit 2>&1 | sed -n '/^Failing tests:/,/^\*\* TEST/p'
```
