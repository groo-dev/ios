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

## Test suite baseline

As of 2026-08-07 the unit suite has 16 pre-existing failures — view snapshot
tests plus one date-dependent `PrayerTimeServiceTests` case. Diff the failing
set against a stashed baseline before blaming your own change:

```bash
scripts/test.sh --unit 2>&1 | sed -n '/^Failing tests:/,/^\*\* TEST/p'
```
