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
