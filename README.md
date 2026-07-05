# Groo iOS

Secure note-taking and password management app for iOS.

## Features

### Pad
Quick encrypted notes with file attachments. Offline-first sync ensures notes are always accessible.

### Pass
Password vault supporting:
- Passwords
- Passkeys
- Cards
- Bank accounts
- Secure notes
- TOTP codes

### Drive
File storage (placeholder for future implementation).

## Extensions

| Extension | Purpose |
|-----------|---------|
| GrooAutoFill | iOS AutoFill credential provider for passwords and passkeys |
| KeyboardExtension | Custom keyboard showing recent Pad items |
| ShareExtension | Share text/URLs/files to Groo from other apps |
| WidgetExtension | Home screen widgets displaying recent Pad items |

## Project Structure

```
ios/
├── Groo/                    # Main app
│   ├── Core/                # Shared services
│   │   ├── Auth/            # PAT authentication
│   │   ├── Crypto/          # AES-256-GCM encryption
│   │   ├── Keychain/        # Biometric-protected storage
│   │   ├── Network/         # API client
│   │   ├── Notifications/   # Push notifications
│   │   ├── Storage/         # SwiftData persistence
│   │   └── Sync/            # Offline-first sync
│   ├── Features/            # Feature modules
│   │   ├── Pad/             # Quick notes
│   │   ├── Pass/            # Password vault
│   │   └── Drive/           # File storage (placeholder)
│   └── Views/               # Shared UI components
├── GrooAutoFill/            # AutoFill extension
├── KeyboardExtension/       # Keyboard extension
├── ShareExtension/          # Share extension
├── WidgetExtension/         # Widget extension
└── Shared/                  # Code shared with extensions
```

## Security

- **Key Derivation**: PBKDF2-HMAC-SHA256 (600,000 iterations)
- **Encryption**: AES-256-GCM
- **Biometric Protection**: Face ID / Touch ID
- **Zero-Knowledge Architecture**: Server never sees plaintext data
- **Biometric Pre-Authentication**: Seamless tab switching without re-prompting

## Build Requirements

- Xcode 16+
- iOS 17.0+
- Apple Developer account (for signing)

## Build Instructions

```bash
# Open in Xcode
open Groo.xcodeproj

# Select signing team in project settings
# Build and run on device (extensions require device)
```

## Configuration

Environment configuration is managed via `Config.swift`:
- **Dev**: Development API endpoints
- **Release**: Production API endpoints

API endpoints:
- Pad API
- Pass API
- Accounts API

## Testing

Unit + integration tests live in `GrooTests` (Swift Testing), UI tests in `GrooUITests` (XCUITest).

```bash
scripts/test.sh              # unit + integration
scripts/test.sh --ui         # UI tests (slow — boots the app)
scripts/test.sh --all        # everything
scripts/test.sh --coverage   # any mode + coverage report (bundle in build/coverage/)
```

Conventions:
- Test files mirror source paths (`GrooTests/Features/Pass/TotpServiceTests.swift`).
- No sleeps; time is injected. Network via `StubURLProtocol` (suites using it are nested under the `NetworkStubbedSuites` `@Suite(.serialized)` umbrella in `GrooTests/Support/NetworkStubbedSuites.swift`, so they serialize relative to each other, not just internally).
- Keychain via `InMemoryKeychain` (`KeychainServicing` seam); vault storage via `PassVaultStore(directoryURL:)`.
- Never use production KDF iteration counts (600k) in tests.
- Wallet tests use real BIP39 derivation vectors (constants in `WalletManagerTests`) — a vector failure is a derivation regression, never a fixture to update.
- SwiftData suites use in-memory containers via `InMemoryLocalStore.make()` — never `LocalStore.shared`.
- WebSocket tests script a `FakeWebSocketConnection` (`GrooTests/Support/WebSocketFakes.swift`); reconnect/ping timers are recorded and fired manually, never waited on.
- `Shared/` is a classic (non-synchronized) Xcode group: register new Shared files with `ruby scripts/register_shared_file.rb <File.swift> <Target>...` — never by hand-editing the pbxproj.
- Extension pure logic lives in `Shared/` (`SharedCredentialMatcher`, `SharedPadCrypto`) and is tested from GrooTests through the app target; extension-target `.swift` files are not compiled into tests.

Design: `docs/superpowers/specs/2026-07-05-ios-test-suite-design.md`.
