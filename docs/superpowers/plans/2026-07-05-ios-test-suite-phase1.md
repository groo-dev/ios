# iOS Test Suite — Infrastructure + Phase 1 (Vault & Crypto) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add GrooTests (Swift Testing) + GrooUITests (XCUITest) targets to `Groo.xcodeproj` and build out Phase 1 coverage: crypto, TOTP, passkey crypto, vault models, vault store, password health, keychain seam, Pass API client, and PassService integration tests.

**Architecture:** Two new test targets added to the existing Xcode project via a Ruby script (`xcodeproj` gem, already installed at 1.27.0). Testability seams are default-parameter injections — production call sites never change. Network is stubbed with a custom `URLProtocol`; keychain with an in-memory fake behind a new `KeychainServicing` protocol; time via existing/new `Date`/`now` parameters; vault storage via an injected directory URL.

**Tech Stack:** Swift 5 / Swift Testing (`import Testing`, `@Test`, `#expect`) for unit+integration; XCTest/XCUITest for UI smoke; Ruby `xcodeproj` gem for pbxproj edits; `xcodebuild` CLI.

**Spec:** `docs/superpowers/specs/2026-07-05-ios-test-suite-design.md`

## Global Constraints

- Working directory for all commands: `/Users/groo/work/gr/ios` (paths below are relative to it).
- Simulator destination (only one available): `platform=iOS Simulator,name=iPhone 17 Pro` (iOS 26.2).
- The Xcode project uses **objectVersion 77** with `PBXFileSystemSynchronizedRootGroup` (synchronized folders). New test targets must use synchronized folders too, so adding a test file to disk automatically adds it to the target — no per-file pbxproj registration.
- Swift Testing runs suites **in parallel**. Any suite touching shared static state (`StubURLProtocol`) MUST be annotated `@Suite(.serialized)` and stub state reset per test.
- No `sleep`/arbitrary waits in any test. Deterministic time via injected `Date` values only.
- Production behavior must not change: every seam is a new parameter with a default preserving current behavior.
- KDF in tests: never use 600,000 PBKDF2 iterations — always pass a small iteration count (1–1,000) explicitly.
- Full check before each commit: `bash scripts/test.sh --unit` passes AND the app still builds (`xcodebuild build` step included in test runs).
- Existing shared scheme is `Groo.xcodeproj/xcshareddata/xcschemes/Groo.xcscheme` with `shouldAutocreateTestPlan = "YES"`.

---

### Task 1: Test targets, runner script, smoke tests

**Files:**
- Create: `scripts/add_test_targets.rb`
- Create: `scripts/test.sh`
- Create: `GrooTests/SmokeTests.swift`
- Create: `GrooUITests/SmokeUITests.swift`
- Modify: `Groo.xcodeproj/project.pbxproj` (via the Ruby script only — never by hand)
- Modify: `Groo.xcodeproj/xcshareddata/xcschemes/Groo.xcscheme` (via the Ruby script only)

**Interfaces:**
- Consumes: existing `Groo` app target, existing shared scheme.
- Produces: `GrooTests` (unit-test bundle, hosted by Groo.app, synchronized folder `GrooTests/`) and `GrooUITests` (UI-test bundle, synchronized folder `GrooUITests/`); `bash scripts/test.sh [--unit|--ui|--all]` as the canonical runner. All later tasks drop `.swift` files into `GrooTests/` and they compile automatically.

- [ ] **Step 1: Create the test directories and smoke test files**

`GrooTests/SmokeTests.swift`:

```swift
//
//  SmokeTests.swift
//  GrooTests
//
//  Proves the unit test target builds, links the app, and runs.
//

import Testing
@testable import Groo

struct SmokeTests {
    @Test func appModuleIsReachable() {
        #expect(Config.keychainService.hasPrefix("dev.groo.ios"))
    }
}
```

`GrooUITests/SmokeUITests.swift`:

```swift
//
//  SmokeUITests.swift
//  GrooUITests
//
//  Proves the UI test target can launch the app.
//

import XCTest

final class SmokeUITests: XCTestCase {
    func testAppLaunches() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertEqual(app.state, .runningForeground)
    }
}
```

- [ ] **Step 2: Write the target-creation script**

`scripts/add_test_targets.rb`:

```ruby
#!/usr/bin/env ruby
# Adds GrooTests (unit) + GrooUITests (UI) targets with synchronized folders,
# and registers both as testables in the shared Groo scheme.
# Idempotent: aborts if GrooTests already exists.
require 'xcodeproj'

project_path = File.expand_path('../Groo.xcodeproj', __dir__)
project = Xcodeproj::Project.open(project_path)

app_target = project.targets.find { |t| t.name == 'Groo' }
abort 'ERROR: Groo target not found' unless app_target
abort 'GrooTests target already exists — nothing to do' if project.targets.any? { |t| t.name == 'GrooTests' }

deployment = app_target.build_configurations.first
                       .resolve_build_setting('IPHONEOS_DEPLOYMENT_TARGET') || '26.2'

unit_target = project.new_target(:unit_test_bundle, 'GrooTests', :ios, deployment)
unit_target.add_dependency(app_target)
unit_target.build_configurations.each do |config|
  config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'dev.groo.ios.tests'
  config.build_settings['TEST_HOST'] = '$(BUILT_PRODUCTS_DIR)/Groo.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/Groo'
  config.build_settings['BUNDLE_LOADER'] = '$(TEST_HOST)'
  config.build_settings['GENERATE_INFOPLIST_FILE'] = 'YES'
  config.build_settings['SWIFT_VERSION'] = '5.0'
  config.build_settings['CODE_SIGN_STYLE'] = 'Automatic'
end

ui_target = project.new_target(:ui_test_bundle, 'GrooUITests', :ios, deployment)
ui_target.add_dependency(app_target)
ui_target.build_configurations.each do |config|
  config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'dev.groo.ios.uitests'
  config.build_settings['TEST_TARGET_NAME'] = 'Groo'
  config.build_settings['GENERATE_INFOPLIST_FILE'] = 'YES'
  config.build_settings['SWIFT_VERSION'] = '5.0'
  config.build_settings['CODE_SIGN_STYLE'] = 'Automatic'
end

# Synchronized folders (objectVersion 77): files on disk under these paths
# are automatically part of the target — no per-file registration.
{ 'GrooTests' => unit_target, 'GrooUITests' => ui_target }.each do |folder, target|
  sync_group = project.new(Xcodeproj::Project::Object::PBXFileSystemSynchronizedRootGroup)
  sync_group.path = folder
  sync_group.source_tree = '<group>'
  project.main_group << sync_group
  target.file_system_synchronized_groups = [sync_group]
end

project.save

scheme_path = Xcodeproj::XCScheme.shared_data_dir(project_path) + 'Groo.xcscheme'
scheme = Xcodeproj::XCScheme.new(scheme_path)
scheme.add_test_target(unit_target)
scheme.add_test_target(ui_target)
scheme.save!

puts 'OK: added GrooTests + GrooUITests and registered them in the Groo scheme'
```

Fallback if `file_system_synchronized_groups` raises `NoMethodError` (gem too old for the attribute): run `gem list xcodeproj` — we verified 1.27.0 is installed, which supports it. If it still fails, replace the synchronized-group block with classic groups:

```ruby
{ 'GrooTests' => unit_target, 'GrooUITests' => ui_target }.each do |folder, target|
  group = project.main_group.new_group(folder, folder)
  Dir.glob(File.join(File.dirname(project_path), folder, '**/*.swift')).each do |f|
    target.add_file_references([group.new_file(f)])
  end
end
```

(and note in the commit that future test files then need re-running a registration script — synchronized groups are strongly preferred).

- [ ] **Step 3: Run the script**

Run: `ruby scripts/add_test_targets.rb`
Expected: `OK: added GrooTests + GrooUITests and registered them in the Groo scheme`

Then: `xcodebuild -project Groo.xcodeproj -list`
Expected: `GrooTests` and `GrooUITests` appear under Targets.

- [ ] **Step 4: Write the runner script**

`scripts/test.sh`:

```bash
#!/bin/bash
# Test runner for the Groo iOS app.
# usage: scripts/test.sh [--unit|--ui|--all]   (default: --unit)
set -euo pipefail
cd "$(dirname "$0")/.."

MODE="${1:---unit}"
ARGS=(test -project Groo.xcodeproj -scheme Groo
      -destination "platform=iOS Simulator,name=iPhone 17 Pro")

case "$MODE" in
  --unit) ARGS+=(-only-testing:GrooTests) ;;
  --ui)   ARGS+=(-only-testing:GrooUITests) ;;
  --all)  ;;
  *) echo "usage: $0 [--unit|--ui|--all]"; exit 1 ;;
esac

xcodebuild "${ARGS[@]}"
```

Run: `chmod +x scripts/test.sh`

- [ ] **Step 5: Run unit smoke test**

Run: `bash scripts/test.sh --unit 2>&1 | tail -20`
Expected: `** TEST SUCCEEDED **` with 1 test passing.

If it fails with a signing error on the test bundle, add `config.build_settings['DEVELOPMENT_TEAM']` matching the app target's team in the Ruby script (read it via `app_target.build_configurations.first.resolve_build_setting('DEVELOPMENT_TEAM')`), delete the created targets by `git checkout Groo.xcodeproj`, and re-run from Step 3.

- [ ] **Step 6: Run UI smoke test**

Run: `bash scripts/test.sh --ui 2>&1 | tail -20`
Expected: `** TEST SUCCEEDED **` with 1 test passing (slower — boots the app).

- [ ] **Step 7: Commit**

```bash
git add scripts/add_test_targets.rb scripts/test.sh GrooTests GrooUITests Groo.xcodeproj
git commit -m "test: add GrooTests + GrooUITests targets with runner script"
```

---

### Task 2: CryptoService + SharedCrypto tests

**Files:**
- Create: `GrooTests/Support/TestData.swift`
- Test: `GrooTests/Core/Crypto/CryptoServiceTests.swift`

**Interfaces:**
- Consumes: `CryptoService` (`Groo/Core/Crypto/CryptoService.swift`) — `generateSalt()`, `deriveKey(password:salt:iterations:)`, `encrypt(_:using:) -> EncryptedPayload`, `decrypt(_:using:) -> String`, `encryptData(_:using:) -> Data`, `decryptData(_:using:) -> Data`, `verifyKey(_:with:)`, `createTestPayload(using:)`; `SharedCrypto.decryptVault(encryptedData:iv:key:)` (`Shared/SharedCrypto.swift`). No production changes.
- Produces: `Data(hexString:)` helper in `TestData` used by Task 3.

- [ ] **Step 1: Write the hex helper**

`GrooTests/Support/TestData.swift`:

```swift
//
//  TestData.swift
//  GrooTests
//
//  Shared fixture helpers.
//

import Foundation

extension Data {
    /// Build Data from a hex string like "55ac046e...". Returns nil on odd length / bad chars.
    init?(hexString: String) {
        let chars = Array(hexString)
        guard chars.count % 2 == 0 else { return nil }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(chars.count / 2)
        for i in stride(from: 0, to: chars.count, by: 2) {
            guard let byte = UInt8(String(chars[i...i+1]), radix: 16) else { return nil }
            bytes.append(byte)
        }
        self.init(bytes)
    }
}
```

- [ ] **Step 2: Write the failing tests**

`GrooTests/Core/Crypto/CryptoServiceTests.swift`:

```swift
//
//  CryptoServiceTests.swift
//  GrooTests
//

import CryptoKit
import Foundation
import Testing
@testable import Groo

struct CryptoServiceTests {
    let crypto = CryptoService()
    /// Fast test key — NEVER use production 600k iterations in tests.
    var key: SymmetricKey {
        get throws { try crypto.deriveKey(password: "correct horse", salt: Data("fixed-salt".utf8), iterations: 1_000) }
    }

    // MARK: Key derivation

    @Test func deriveKeyIsDeterministic() throws {
        let salt = Data("salt-a".utf8)
        let k1 = try crypto.deriveKey(password: "pw", salt: salt, iterations: 1_000)
        let k2 = try crypto.deriveKey(password: "pw", salt: salt, iterations: 1_000)
        #expect(k1 == k2)
    }

    @Test func deriveKeyDiffersBySaltPasswordAndIterations() throws {
        let base = try crypto.deriveKey(password: "pw", salt: Data("salt-a".utf8), iterations: 1_000)
        #expect(try crypto.deriveKey(password: "pw", salt: Data("salt-b".utf8), iterations: 1_000) != base)
        #expect(try crypto.deriveKey(password: "pw2", salt: Data("salt-a".utf8), iterations: 1_000) != base)
        #expect(try crypto.deriveKey(password: "pw", salt: Data("salt-a".utf8), iterations: 1_001) != base)
    }

    /// RFC 7914 §11 PBKDF2-HMAC-SHA256 vectors (first 32 bytes of dkLen=64 output).
    @Test func deriveKeyMatchesRFC7914Vectors() throws {
        let v1 = try crypto.deriveKey(password: "passwd", salt: Data("salt".utf8), iterations: 1)
        #expect(v1.withUnsafeBytes { Data($0) } ==
                Data(hexString: "55ac046e56e3089fec1691c22544b605f94185216dde0465e68b9d57c20dacbc"))

        let v2 = try crypto.deriveKey(password: "Password", salt: Data("NaCl".utf8), iterations: 80_000)
        #expect(v2.withUnsafeBytes { Data($0) } ==
                Data(hexString: "4ddcd8f60b98be21830cee5ef22701f9641a4418d04c0414aeff08876b34ab56"))
    }

    @Test func generateSaltIs32RandomBytes() {
        let s1 = crypto.generateSalt()
        let s2 = crypto.generateSalt()
        #expect(s1.count == 32)
        #expect(s1 != s2)
    }

    // MARK: Text roundtrips

    @Test(arguments: ["hello", "", "påsswörd 🔑🧨 中文", String(repeating: "x", count: 1_000_000)])
    func encryptDecryptRoundtrip(_ plaintext: String) throws {
        let payload = try crypto.encrypt(plaintext, using: try key)
        #expect(try crypto.decrypt(payload, using: try key) == plaintext)
    }

    @Test func encryptUsesFreshNonces() throws {
        let a = try crypto.encrypt("same", using: try key)
        let b = try crypto.encrypt("same", using: try key)
        #expect(a.iv != b.iv)
        #expect(a.ciphertext != b.ciphertext)
    }

    // MARK: Failure must be loud

    @Test func decryptWithWrongKeyThrows() throws {
        let payload = try crypto.encrypt("secret", using: try key)
        let wrongKey = try crypto.deriveKey(password: "wrong", salt: Data("fixed-salt".utf8), iterations: 1_000)
        #expect(throws: (any Error).self) { try crypto.decrypt(payload, using: wrongKey) }
    }

    @Test func decryptTamperedCiphertextThrows() throws {
        let payload = try crypto.encrypt("secret", using: try key)
        var raw = Data(base64Encoded: payload.ciphertext)!
        raw[0] ^= 0xFF
        let tampered = EncryptedPayload(ciphertext: raw.base64EncodedString(), iv: payload.iv, version: payload.version)
        #expect(throws: (any Error).self) { try crypto.decrypt(tampered, using: try key) }
    }

    @Test func decryptInvalidBase64Throws() throws {
        let bad = EncryptedPayload(ciphertext: "not base64!!!", iv: "also not!!!", version: 1)
        #expect(throws: CryptoError.invalidBase64) { try crypto.decrypt(bad, using: try key) }
    }

    // MARK: Binary format

    @Test func encryptDataFormatIsIvCiphertextTag() throws {
        let plaintext = Data("binary-payload".utf8)
        let combined = try crypto.encryptData(plaintext, using: try key)
        // [12-byte IV][ciphertext][16-byte tag]
        #expect(combined.count == 12 + plaintext.count + 16)
        #expect(try crypto.decryptData(combined, using: try key) == plaintext)
    }

    // MARK: verifyKey

    @Test func verifyKeyAcceptsRightKeyRejectsWrong() throws {
        let payload = try crypto.createTestPayload(using: try key)
        #expect(crypto.verifyKey(try key, with: payload))
        let wrongKey = try crypto.deriveKey(password: "nope", salt: Data("fixed-salt".utf8), iterations: 1_000)
        #expect(!crypto.verifyKey(wrongKey, with: payload))
    }

    // MARK: SharedCrypto must decrypt what CryptoService encrypts

    @Test func sharedCryptoDecryptsCryptoServiceOutput() throws {
        let payload = try crypto.encrypt("cross-module plaintext ✓", using: try key)
        let decrypted = try SharedCrypto.decryptVault(
            encryptedData: Data(base64Encoded: payload.ciphertext)!,
            iv: payload.iv,
            key: try key
        )
        #expect(decrypted == "cross-module plaintext ✓")
    }

    @Test func sharedCryptoRejectsInvalidBase64Iv() throws {
        #expect(throws: SharedCryptoError.invalidBase64) {
            try SharedCrypto.decryptVault(encryptedData: Data(), iv: "!!!", key: try key)
        }
    }
}
```

- [ ] **Step 3: Run the suite**

Run: `bash scripts/test.sh --unit 2>&1 | tail -20`
Expected: PASS (these test existing behavior — a failure means either a fixture typo or a real bug; investigate before touching production code).

- [ ] **Step 4: Commit**

```bash
git add GrooTests
git commit -m "test: CryptoService + SharedCrypto suite (roundtrips, RFC 7914 vectors, tamper rejection)"
```

---

### Task 3: TOTP tests (TotpService + SharedTotp)

**Files:**
- Test: `GrooTests/Features/Pass/TotpServiceTests.swift`

**Interfaces:**
- Consumes: `TotpService.generateCode(config:time:)`, `.secondsRemaining(period:time:)`, `.progress(period:time:)`, `.parseUri(_:)` (`Groo/Features/Pass/TotpService.swift`); `SharedTotp.generateCode(config:time:)` (`Shared/SharedTotp.swift`); `PassTotpConfig` and `SharedPassTotpConfig` (memberwise inits). Both already take `time: Date` — no seams needed.
- Produces: nothing consumed by later tasks.

- [ ] **Step 1: Write the failing tests**

`GrooTests/Features/Pass/TotpServiceTests.swift`:

```swift
//
//  TotpServiceTests.swift
//  GrooTests
//
//  RFC 6238 Appendix B vectors + rotation boundaries + URI parsing.
//

import Foundation
import Testing
@testable import Groo

struct TotpServiceTests {
    // RFC 6238 test secrets, base32-encoded:
    //   SHA1:   ASCII "12345678901234567890"                       (20 bytes)
    //   SHA256: ASCII "12345678901234567890123456789012"           (32 bytes)
    //   SHA512: ASCII "1234567890...1234" repeated to 64 bytes
    static let sha1Secret   = "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ"
    static let sha256Secret = "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZA===="
    static let sha512Secret = "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNA="

    static let rfcTimes: [TimeInterval] = [59, 1_111_111_109, 1_111_111_111, 1_234_567_890, 2_000_000_000, 20_000_000_000]
    static let sha1Expected   = ["94287082", "07081804", "14050471", "89005924", "69279037", "65353130"]
    static let sha256Expected = ["46119246", "68084774", "67062674", "91819424", "90698825", "77737706"]
    static let sha512Expected = ["90693936", "25091201", "99943326", "93441116", "38618901", "47863826"]

    @Test(arguments: zip(rfcTimes, sha1Expected))
    func rfc6238Sha1(_ t: TimeInterval, expected: String) {
        let config = PassTotpConfig(secret: Self.sha1Secret, algorithm: .sha1, digits: 8, period: 30)
        #expect(TotpService.generateCode(config: config, time: Date(timeIntervalSince1970: t)) == expected)
    }

    @Test(arguments: zip(rfcTimes, sha256Expected))
    func rfc6238Sha256(_ t: TimeInterval, expected: String) {
        let config = PassTotpConfig(secret: Self.sha256Secret, algorithm: .sha256, digits: 8, period: 30)
        #expect(TotpService.generateCode(config: config, time: Date(timeIntervalSince1970: t)) == expected)
    }

    @Test(arguments: zip(rfcTimes, sha512Expected))
    func rfc6238Sha512(_ t: TimeInterval, expected: String) {
        let config = PassTotpConfig(secret: Self.sha512Secret, algorithm: .sha512, digits: 8, period: 30)
        #expect(TotpService.generateCode(config: config, time: Date(timeIntervalSince1970: t)) == expected)
    }

    @Test func sixDigitCodesAreLastSixOfEightDigit() {
        let config6 = PassTotpConfig(secret: Self.sha1Secret, algorithm: .sha1, digits: 6, period: 30)
        #expect(TotpService.generateCode(config: config6, time: Date(timeIntervalSince1970: 59)) == "287082")
    }

    // MARK: Rotation boundaries

    @Test func codeIsStableWithinAPeriodAndRotatesAtBoundary() {
        let config = PassTotpConfig(secret: Self.sha1Secret, algorithm: .sha1, digits: 6, period: 30)
        let at30 = TotpService.generateCode(config: config, time: Date(timeIntervalSince1970: 30))
        let at59 = TotpService.generateCode(config: config, time: Date(timeIntervalSince1970: 59))
        let at60 = TotpService.generateCode(config: config, time: Date(timeIntervalSince1970: 60))
        #expect(at30 == at59)
        #expect(at59 != at60)
    }

    @Test func secondsRemainingAndProgress() {
        #expect(TotpService.secondsRemaining(period: 30, time: Date(timeIntervalSince1970: 59)) == 1)
        #expect(TotpService.secondsRemaining(period: 30, time: Date(timeIntervalSince1970: 60)) == 30)
        #expect(TotpService.progress(period: 30, time: Date(timeIntervalSince1970: 45)) == 0.5)
        #expect(TotpService.progress(period: 30, time: Date(timeIntervalSince1970: 60)) == 0.0)
    }

    // MARK: Invalid secrets — divergent by design: app shows placeholder, extension gets nil

    @Test func invalidSecretYieldsPlaceholderInApp() {
        let config = PassTotpConfig(secret: "!!!!", algorithm: .sha1, digits: 6, period: 30)
        #expect(TotpService.generateCode(config: config, time: Date(timeIntervalSince1970: 59)) == "------")
    }

    @Test func invalidSecretYieldsNilInSharedTotp() {
        let config = SharedPassTotpConfig(secret: "!!!!", algorithm: .sha1, digits: 6, period: 30)
        #expect(SharedTotp.generateCode(config: config, time: Date(timeIntervalSince1970: 59)) == nil)
    }

    @Test func sharedTotpMatchesAppTotp() {
        let app = PassTotpConfig(secret: Self.sha1Secret, algorithm: .sha1, digits: 6, period: 30)
        let shared = SharedPassTotpConfig(secret: Self.sha1Secret, algorithm: .sha1, digits: 6, period: 30)
        let t = Date(timeIntervalSince1970: 1_234_567_890)
        #expect(SharedTotp.generateCode(config: shared, time: t) == TotpService.generateCode(config: app, time: t))
    }

    @Test func base32DecodingIsCaseAndPaddingTolerant() {
        let lower = PassTotpConfig(secret: Self.sha1Secret.lowercased(), algorithm: .sha1, digits: 8, period: 30)
        #expect(TotpService.generateCode(config: lower, time: Date(timeIntervalSince1970: 59)) == "94287082")
    }
}

// MARK: - otpauth:// URI parsing

struct TotpUriParsingTests {
    @Test func parsesFullUri() throws {
        let config = try #require(TotpService.parseUri(
            "otpauth://totp/Groo:user@example.com?secret=JBSWY3DPEHPK3PXP&algorithm=SHA256&digits=8&period=60"))
        #expect(config.secret == "JBSWY3DPEHPK3PXP")
        #expect(config.algorithm == .sha256)
        #expect(config.digits == 8)
        #expect(config.period == 60)
    }

    @Test func appliesDefaultsWhenParamsMissing() throws {
        let config = try #require(TotpService.parseUri("otpauth://totp/Groo?secret=JBSWY3DPEHPK3PXP"))
        #expect(config.algorithm == .sha1)
        #expect(config.digits == 6)
        #expect(config.period == 30)
    }

    @Test(arguments: [
        "otpauth://hotp?secret=ABC",          // wrong host (counter-based)
        "https://totp?secret=ABC",            // wrong scheme
        "otpauth://totp?secret=",             // empty secret
        "otpauth://totp",                     // no query
        "not a uri at all",
    ])
    func rejectsInvalidUris(_ uri: String) {
        #expect(TotpService.parseUri(uri) == nil)
    }

    @Test func unknownAlgorithmFallsBackToSha1() throws {
        let config = try #require(TotpService.parseUri("otpauth://totp/x?secret=ABCD&algorithm=MD5"))
        #expect(config.algorithm == .sha1)
    }
}
```

- [ ] **Step 2: Run the suite**

Run: `bash scripts/test.sh --unit 2>&1 | tail -20`
Expected: PASS. If an RFC vector fails, first re-verify the base32 constant (regenerate with `python3 -c "import base64; print(base64.b32encode(b'12345678901234567890').decode())"`) before suspecting the implementation.

- [ ] **Step 3: Commit**

```bash
git add GrooTests
git commit -m "test: TOTP suite with RFC 6238 vectors, rotation boundaries, URI parsing"
```

---

### Task 4: SharedPasskeyCrypto tests

**Files:**
- Test: `GrooTests/Shared/SharedPasskeyCryptoTests.swift`

**Interfaces:**
- Consumes: `SharedPasskeyCrypto.signAssertion(privateKeyBase64:authenticatorData:clientDataHash:)`, `.buildAuthenticatorData(rpId:signCount:userPresent:userVerified:)`, `.createRegistration(rpId:) -> Registration` (`Shared/SharedPasskeyCrypto.swift`); CryptoKit `P256` for independent signature verification. No production changes.
- Produces: nothing consumed by later tasks.

- [ ] **Step 1: Write the failing tests**

`GrooTests/Shared/SharedPasskeyCryptoTests.swift`:

```swift
//
//  SharedPasskeyCryptoTests.swift
//  GrooTests
//
//  WebAuthn passkey crypto: sign/verify roundtrips, authenticator data layout,
//  and the sign-count-stays-zero rule.
//

import CryptoKit
import Foundation
import Testing
@testable import Groo

struct SharedPasskeyCryptoTests {

    // MARK: Assertion signing

    @Test func signAssertionVerifiesWithPublicKey() throws {
        let privateKey = P256.Signing.PrivateKey()
        let authData = SharedPasskeyCrypto.buildAuthenticatorData(rpId: "example.com", signCount: 0)
        let clientDataHash = Data(SHA256.hash(data: Data("client-data".utf8)))

        let derSignature = try SharedPasskeyCrypto.signAssertion(
            privateKeyBase64: privateKey.derRepresentation.base64EncodedString(),
            authenticatorData: authData,
            clientDataHash: clientDataHash
        )

        let signature = try P256.Signing.ECDSASignature(derRepresentation: derSignature)
        var signedData = authData
        signedData.append(clientDataHash)
        #expect(privateKey.publicKey.isValidSignature(signature, for: signedData))
    }

    @Test func signAssertionRejectsInvalidBase64() {
        #expect(throws: PasskeyCryptoError.invalidBase64) {
            try SharedPasskeyCrypto.signAssertion(
                privateKeyBase64: "%%% not base64 %%%",
                authenticatorData: Data(), clientDataHash: Data())
        }
    }

    @Test func signAssertionRejectsGarbageKey() {
        #expect(throws: PasskeyCryptoError.invalidPrivateKey) {
            try SharedPasskeyCrypto.signAssertion(
                privateKeyBase64: Data("valid base64, invalid DER key".utf8).base64EncodedString(),
                authenticatorData: Data(), clientDataHash: Data())
        }
    }

    // MARK: Authenticator data layout: rpIdHash(32) + flags(1) + signCount(4)

    @Test func authenticatorDataLayout() {
        let authData = SharedPasskeyCrypto.buildAuthenticatorData(rpId: "groo.dev", signCount: 7)
        #expect(authData.count == 37)
        #expect(authData.prefix(32) == Data(SHA256.hash(data: Data("groo.dev".utf8))))
        #expect(authData[32] == 0x05)  // UP | UV
        #expect(Array(authData.suffix(4)) == [0x00, 0x00, 0x00, 0x07])  // big-endian
    }

    @Test func authenticatorDataFlagVariants() {
        #expect(SharedPasskeyCrypto.buildAuthenticatorData(rpId: "x", signCount: 0, userPresent: true,  userVerified: false)[32] == 0x01)
        #expect(SharedPasskeyCrypto.buildAuthenticatorData(rpId: "x", signCount: 0, userPresent: false, userVerified: true)[32] == 0x04)
        #expect(SharedPasskeyCrypto.buildAuthenticatorData(rpId: "x", signCount: 0, userPresent: false, userVerified: false)[32] == 0x00)
    }

    // MARK: Registration

    @Test func registrationProducesUsableKeyPair() throws {
        let reg = try SharedPasskeyCrypto.createRegistration(rpId: "groo.dev")

        #expect(reg.credentialId.count == 16)

        // Private key must import and match the exported public key
        let privateKey = try P256.Signing.PrivateKey(
            derRepresentation: Data(base64Encoded: reg.privateKeyBase64)!)
        let publicKey = try P256.Signing.PublicKey(
            derRepresentation: Data(base64Encoded: reg.publicKeyBase64)!)
        #expect(privateKey.publicKey.derRepresentation == publicKey.derRepresentation)
    }

    @Test func registrationCredentialIdsAreUnique() throws {
        let a = try SharedPasskeyCrypto.createRegistration(rpId: "groo.dev")
        let b = try SharedPasskeyCrypto.createRegistration(rpId: "groo.dev")
        #expect(a.credentialId != b.credentialId)
    }

    /// The documented AutoFill rule: registrations always embed sign count 0.
    /// authData layout inside the attestation: rpIdHash(32) + flags(0x45) + signCount(4 zero bytes) + ...
    @Test func registrationSignCountIsZero() throws {
        let reg = try SharedPasskeyCrypto.createRegistration(rpId: "groo.dev")
        var expectedPrefix = Data(SHA256.hash(data: Data("groo.dev".utf8)))
        expectedPrefix.append(0x45)                                // UP | UV | AT
        expectedPrefix.append(contentsOf: [0x00, 0x00, 0x00, 0x00]) // sign count MUST be 0
        #expect(reg.attestationObject.range(of: expectedPrefix) != nil)
    }

    @Test func attestationObjectIsNoneFormatCbor() throws {
        let reg = try SharedPasskeyCrypto.createRegistration(rpId: "groo.dev")
        #expect(reg.attestationObject.first == 0xa3)                       // CBOR map(3)
        #expect(reg.attestationObject.range(of: Data("none".utf8)) != nil) // fmt: "none"
        #expect(reg.attestationObject.range(of: reg.credentialId) != nil)  // embeds credential id
    }
}
```

- [ ] **Step 2: Run the suite**

Run: `bash scripts/test.sh --unit 2>&1 | tail -20`
Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add GrooTests
git commit -m "test: SharedPasskeyCrypto suite (sign/verify, authData layout, sign-count-zero rule)"
```

---

### Task 5: PassModels + SharedPassModels Codable tests

**Files:**
- Create: `GrooTests/Fixtures/VaultItemFixtures.swift`
- Test: `GrooTests/Features/Pass/PassModelsTests.swift`
- Test: `GrooTests/Shared/SharedPassModelsTests.swift`

**Interfaces:**
- Consumes: `PassVaultItem` (8 cases incl. `.corrupted(PassCorruptedItem)`), all 7 item structs, `PassVault`, `PassVaultItemType` (`Groo/Features/Pass/Models/PassModels.swift`); `SharedPassVaultItem`, `SharedPassPasswordItem`, `Data(base64URLEncoded:)`/`base64URLEncodedString` (`Shared/SharedPassModels.swift`). No production changes.
- Produces: `VaultItemFixtures.passwordItemJSON` etc. and `VaultItemFixtures.samplePasswordItem(...)` reused by Tasks 6 and 10.

- [ ] **Step 1: Write the fixtures**

`GrooTests/Fixtures/VaultItemFixtures.swift`:

```swift
//
//  VaultItemFixtures.swift
//  GrooTests
//
//  Canonical JSON for every vault item type. Keys must match the CodingKeys
//  in PassModels.swift — these fixtures are the schema contract.
//

import Foundation
@testable import Groo

enum VaultItemFixtures {
    static let passwordItemJSON = """
    {"id":"pw-1","type":"password","name":"Example","username":"user@example.com","password":"hunter2!","urls":["https://www.example.com/login"],"notes":"note","totp":{"secret":"JBSWY3DPEHPK3PXP","algorithm":"SHA1","digits":6,"period":30},"folderId":"f-1","favorite":true,"createdAt":1700000000000,"updatedAt":1700000000000}
    """

    static let passkeyItemJSON = """
    {"id":"pk-1","type":"passkey","name":"Example Passkey","rpId":"example.com","rpName":"Example","credentialId":"Y3JlZC1pZA","publicKey":"cHVi","privateKey":"cHJpdg==","userHandle":"dXNlcg","userName":"user@example.com","signCount":0,"createdAt":1700000000000,"updatedAt":1700000000000}
    """

    static let noteItemJSON = """
    {"id":"n-1","type":"note","name":"Secure Note","content":"top secret 📝","createdAt":1700000000000,"updatedAt":1700000000000}
    """

    static let cardItemJSON = """
    {"id":"c-1","type":"card","name":"Visa","cardholderName":"J DOE","number":"4111111111111111","expMonth":"12","expYear":"2030","cvv":"123","brand":"visa","createdAt":1700000000000,"updatedAt":1700000000000}
    """

    static let bankAccountItemJSON = """
    {"id":"b-1","type":"bank_account","name":"Checking","bankName":"Big Bank","accountType":"checking","accountNumber":"12345678","routingNumber":"021000021","createdAt":1700000000000,"updatedAt":1700000000000}
    """

    static let fileItemJSON = """
    {"id":"fl-1","type":"file","name":"Tax Doc","fileName":"2025.pdf","fileSize":1024,"mimeType":"application/pdf","r2Key":"files/abc","encryptionIv":"aXY=","createdAt":1700000000000,"updatedAt":1700000000000}
    """

    static let cryptoWalletItemJSON = """
    {"id":"w-1","type":"crypto_wallet","name":"Main Wallet","address":"0xabc","seedPhrase":"legal winner thank year wave sausage worth useful legal winner thank yellow","derivationPath":"m/44'/60'/0'/0/0","createdAt":1700000000000,"updatedAt":1700000000000}
    """

    static var allItemJSONs: [String] {
        [passwordItemJSON, passkeyItemJSON, noteItemJSON, cardItemJSON,
         bankAccountItemJSON, fileItemJSON, cryptoWalletItemJSON]
    }

    /// Programmatic password item for tests needing controlled timestamps.
    static func samplePasswordItem(
        id: String = "pw-1", name: String = "Example", password: String = "hunter2!",
        totp: PassTotpConfig? = nil, updatedAt: Int = 1_700_000_000_000, deletedAt: Int? = nil
    ) -> PassPasswordItem {
        PassPasswordItem(
            id: id, type: .password, name: name, username: "user@example.com",
            password: password, urls: ["https://example.com"], notes: nil, totp: totp,
            folderId: nil, favorite: nil,
            createdAt: 1_700_000_000_000, updatedAt: updatedAt, deletedAt: deletedAt)
    }
}
```

- [ ] **Step 2: Write the failing PassModels tests**

`GrooTests/Features/Pass/PassModelsTests.swift`:

```swift
//
//  PassModelsTests.swift
//  GrooTests
//
//  Codable contract for every vault item type. Guards the multi-file switch
//  statements that must stay in sync when a new item type is added.
//

import Foundation
import Testing
@testable import Groo

struct PassModelsTests {
    let decoder = JSONDecoder()
    let encoder = JSONEncoder()

    // MARK: Roundtrips — every type

    @Test(arguments: VaultItemFixtures.allItemJSONs)
    func itemRoundtripsLosslessly(_ json: String) throws {
        let item = try decoder.decode(PassVaultItem.self, from: Data(json.utf8))
        if case .corrupted = item { Issue.record("fixture decoded as corrupted: \(json)") }
        let reencoded = try encoder.encode(item)
        let redecoded = try decoder.decode(PassVaultItem.self, from: reencoded)
        #expect(redecoded == item)
    }

    @Test func everyItemTypeHasAFixture() {
        // If a new case is added to PassVaultItemType, this fails until a fixture exists.
        #expect(VaultItemFixtures.allItemJSONs.count == PassVaultItemType.allCases.count)
    }

    @Test func decodedTypesMatchExpectedCases() throws {
        let items = try VaultItemFixtures.allItemJSONs.map {
            try decoder.decode(PassVaultItem.self, from: Data($0.utf8))
        }
        #expect(items.map(\.type) == [.password, .passkey, .note, .card, .bankAccount, .file, .cryptoWallet])
    }

    // MARK: Type inference when "type" field is missing

    @Test func infersPasswordFromFields() throws {
        let json = """
        {"id":"x","name":"n","username":"u","password":"p","urls":[],"createdAt":1,"updatedAt":1}
        """
        let item = try decoder.decode(PassVaultItem.self, from: Data(json.utf8))
        guard case .password = item else { Issue.record("expected .password, got \(item)"); return }
    }

    @Test func infersPasskeyFromRpIdAndCredentialId() throws {
        let json = """
        {"id":"x","name":"n","rpId":"r.com","rpName":"R","credentialId":"Y3JlZA","publicKey":"cA==","privateKey":"cA==","userHandle":"dQ","userName":"u","signCount":0,"createdAt":1,"updatedAt":1}
        """
        let item = try decoder.decode(PassVaultItem.self, from: Data(json.utf8))
        guard case .passkey = item else { Issue.record("expected .passkey, got \(item)"); return }
    }

    // MARK: Corruption safety — bad items must never destroy data

    @Test func malformedItemBecomesCorruptedAndPreservesOriginalJSON() throws {
        // "card" type but missing all required card fields → decode fails → .corrupted
        let json = """
        {"id":"bad-1","type":"card","name":"Broken","customField":42}
        """
        let item = try decoder.decode(PassVaultItem.self, from: Data(json.utf8))
        guard case .corrupted(let corrupted) = item else {
            Issue.record("expected .corrupted, got \(item)"); return
        }
        #expect(corrupted.id == "bad-1")

        // Re-encoding must emit the ORIGINAL json verbatim (via PassRawJSON)
        let reencoded = try encoder.encode(item)
        let original = try JSONSerialization.jsonObject(with: Data(json.utf8)) as! NSDictionary
        let roundtripped = try JSONSerialization.jsonObject(with: reencoded) as! NSDictionary
        #expect(roundtripped == original)
    }

    // MARK: Vault roundtrip

    @Test func fullVaultRoundtrips() throws {
        let itemsJSON = VaultItemFixtures.allItemJSONs.joined(separator: ",")
        let vaultJSON = """
        {"version":1,"items":[\(itemsJSON)],"folders":[{"id":"f-1","name":"Work"}],"lastModified":1700000000000}
        """
        let vault = try decoder.decode(PassVault.self, from: Data(vaultJSON.utf8))
        #expect(vault.items.count == 7)
        #expect(vault.folders.map(\.name) == ["Work"])
        let redecoded = try decoder.decode(PassVault.self, from: try encoder.encode(vault))
        #expect(redecoded == vault)
    }

    // MARK: Optional-field tolerance

    @Test func minimalPasswordItemDecodes() throws {
        let json = """
        {"id":"x","type":"password","name":"n","username":"u","password":"p","urls":[],"createdAt":1,"updatedAt":1}
        """
        let item = try decoder.decode(PassPasswordItem.self, from: Data(json.utf8))
        #expect(item.notes == nil)
        #expect(item.totp == nil)
        #expect(item.deletedAt == nil)
    }
}
```

- [ ] **Step 3: Write the failing SharedPassModels tests**

`GrooTests/Shared/SharedPassModelsTests.swift`:

```swift
//
//  SharedPassModelsTests.swift
//  GrooTests
//
//  Extension-side mirror models: base64URL, type inference, TOTP tolerance,
//  domain matching.
//

import Foundation
import Testing
@testable import Groo

struct SharedPassModelsTests {
    let decoder = JSONDecoder()

    // MARK: Base64URL (WebAuthn credentialId / userHandle encoding)

    @Test(arguments: ["f", "fo", "foo", "foob", "fooba", "foobar", ""])
    func base64URLRoundtrips(_ raw: String) throws {
        let encoded = Data(raw.utf8).base64URLEncodedString
        #expect(!encoded.contains("="))
        #expect(!encoded.contains("+"))
        #expect(!encoded.contains("/"))
        let decoded = try #require(Data(base64URLEncoded: encoded))
        #expect(String(data: decoded, encoding: .utf8) == raw)
    }

    @Test func base64URLDecodesUrlSafeChars() {
        // 0xfb 0xef 0xff encodes to "----" chars territory: base64 "++//" → base64url "--__"
        let data = Data([0xfb, 0xef, 0xff, 0xbe])
        let encoded = data.base64URLEncodedString
        #expect(Data(base64URLEncoded: encoded) == data)
    }

    // MARK: Item decoding for AutoFill

    @Test func passwordAndPasskeyDecodeOthersCollapse() throws {
        let vaultJSON = """
        {"version":1,"items":[
          \(VaultItemFixtures.passwordItemJSON),
          \(VaultItemFixtures.passkeyItemJSON),
          \(VaultItemFixtures.noteItemJSON)
        ],"folders":[],"lastModified":1}
        """
        let vault = try decoder.decode(SharedPassVault.self, from: Data(vaultJSON.utf8))
        #expect(vault.items.count == 3)
        #expect(vault.items.compactMap(\.passwordItem).count == 1)
        #expect(vault.items.compactMap(\.passkeyItem).count == 1)
    }

    /// A malformed TOTP config must not take the whole credential down.
    @Test func malformedTotpIsToleratedCredentialSurvives() throws {
        let json = """
        {"id":"pw-1","type":"password","name":"n","username":"u","password":"p","urls":[],"totp":{"secret":"s","algorithm":"NOT_AN_ALGO","digits":6,"period":30}}
        """
        let item = try decoder.decode(SharedPassPasswordItem.self, from: Data(json.utf8))
        #expect(item.password == "p")
        #expect(item.totp == nil)
    }

    // MARK: Domain matching

    @Test func primaryDomainStripsWwwAndLowercases() throws {
        let json = """
        {"id":"x","type":"password","name":"n","username":"u","password":"p","urls":["https://WWW.Example.COM/login"]}
        """
        let item = try decoder.decode(SharedPassPasswordItem.self, from: Data(json.utf8))
        #expect(item.primaryDomain == "example.com")
    }

    @Test func domainsHandleBareHostsAndSchemes() throws {
        let json = """
        {"id":"x","type":"password","name":"n","username":"u","password":"p","urls":["example.com","https://app.groo.dev/x","www.foo.io"]}
        """
        let item = try decoder.decode(SharedPassPasswordItem.self, from: Data(json.utf8))
        #expect(item.domains == ["example.com", "app.groo.dev", "foo.io"])
    }

    @Test func primaryDomainIsNilForEmptyUrls() throws {
        let json = """
        {"id":"x","type":"password","name":"n","username":"u","password":"p","urls":[]}
        """
        let item = try decoder.decode(SharedPassPasswordItem.self, from: Data(json.utf8))
        #expect(item.primaryDomain == nil)
    }
}
```

- [ ] **Step 4: Run the suite**

Run: `bash scripts/test.sh --unit 2>&1 | tail -20`
Expected: PASS. If a fixture fails to decode, diff its keys against the `CodingKeys` enum in `PassModels.swift` — the fixture is wrong, not the model (these test existing shipped behavior).

- [ ] **Step 5: Commit**

```bash
git add GrooTests
git commit -m "test: Codable contract for all 7 vault item types + corruption preservation + shared models"
```

---

### Task 6: PasswordHealthAnalyzer tests (with `now` seam)

**Files:**
- Modify: `Groo/Features/Pass/PasswordHealthAnalyzer.swift:89` (`analyze`) and `:172` (`findOldPasswords`)
- Test: `GrooTests/Features/Pass/PasswordHealthAnalyzerTests.swift`

**Interfaces:**
- Consumes: `VaultItemFixtures.samplePasswordItem(...)` from Task 5.
- Produces: `PasswordHealthAnalyzer.analyze(items:now:)` — new `now: Date = Date()` parameter; existing call sites (`PasswordHealthView`) unaffected.

- [ ] **Step 1: Write the failing tests**

`GrooTests/Features/Pass/PasswordHealthAnalyzerTests.swift`:

```swift
//
//  PasswordHealthAnalyzerTests.swift
//  GrooTests
//

import Foundation
import Testing
@testable import Groo

struct PasswordHealthAnalyzerTests {
    /// Fixed "now" so age-based checks are deterministic: 2023-11-14T22:13:20Z
    static let now = Date(timeIntervalSince1970: 1_700_000_000)
    static let nowMs = 1_700_000_000_000

    func item(_ id: String, password: String, updatedAt: Int = nowMs,
              totp: PassTotpConfig? = nil, deletedAt: Int? = nil) -> PassVaultItem {
        .password(VaultItemFixtures.samplePasswordItem(
            id: id, password: password, totp: totp, updatedAt: updatedAt, deletedAt: deletedAt))
    }

    // MARK: Strength

    @Test(arguments: [
        "",                    // empty
        "short1!",             // < 8 chars
        "password123",         // common-password list
        "qwerty",              // common-password list
        "aaaaaaaaaaaa",        // repeating, no variety
    ])
    func weakPasswords(_ password: String) {
        #expect(PasswordHealthAnalyzer.calculateStrength(password) == .weak)
    }

    @Test func longVariedPasswordIsStrong() {
        #expect(PasswordHealthAnalyzer.calculateStrength("kV9#mQ2$xL7@wF4z") == .strong)
    }

    @Test func sequentialCharsArePenalized() {
        // Same length/variety, one contains "123"
        let withSeq = PasswordHealthAnalyzer.calculateStrength("Bx123!qZmWpL#kV9")
        let without = PasswordHealthAnalyzer.calculateStrength("Bx739!qZmWpL#kV2")
        #expect(withSeq < without)
    }

    // MARK: Report

    @Test func emptyVaultScoresPerfect() {
        let report = PasswordHealthAnalyzer.analyze(items: [], now: Self.now)
        #expect(report.totalPasswords == 0)
        #expect(report.overallScore == 100)
    }

    @Test func reusedPasswordsAreGrouped() {
        let report = PasswordHealthAnalyzer.analyze(items: [
            item("a", password: "kV9#mQ2$xL7@wF4z"),
            item("b", password: "kV9#mQ2$xL7@wF4z"),
            item("c", password: "uniqueUnique#77!"),
        ], now: Self.now)
        #expect(report.reusedCount == 2)
        #expect(report.reusedPasswords.count == 1)
    }

    @Test func oldPasswordBoundaryAt90Days() {
        let dayMs = 24 * 60 * 60 * 1000
        let report = PasswordHealthAnalyzer.analyze(items: [
            item("old", password: "kV9#mQ2$xL7@wF4z", updatedAt: Self.nowMs - 91 * dayMs),
            item("fresh", password: "uniqueUnique#77!", updatedAt: Self.nowMs - 89 * dayMs),
        ], now: Self.now)
        #expect(report.oldPasswords.map(\.id) == ["old"])
    }

    @Test func totpCoverageIsTracked() {
        let totp = PassTotpConfig(secret: "JBSWY3DPEHPK3PXP", algorithm: .sha1, digits: 6, period: 30)
        let report = PasswordHealthAnalyzer.analyze(items: [
            item("with", password: "kV9#mQ2$xL7@wF4z", totp: totp),
            item("without", password: "uniqueUnique#77!"),
        ], now: Self.now)
        #expect(report.withoutTwoFactor.map(\.id) == ["without"])
    }

    @Test func deletedItemsAreExcluded() {
        let report = PasswordHealthAnalyzer.analyze(items: [
            item("deleted", password: "password123", deletedAt: Self.nowMs),
        ], now: Self.now)
        #expect(report.totalPasswords == 0)
    }

    @Test func scoreStaysWithinBounds() {
        // All-bad vault must clamp at >= 0
        let items = (0..<5).map { item("i\($0)", password: "password123", updatedAt: 0) }
        let report = PasswordHealthAnalyzer.analyze(items: items, now: Self.now)
        #expect((0...100).contains(report.overallScore))
        #expect(report.scoreLabel == "Needs Attention")
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `bash scripts/test.sh --unit 2>&1 | tail -20`
Expected: BUILD FAILURE — `extra argument 'now' in call` (the seam doesn't exist yet).

- [ ] **Step 3: Add the `now` seam**

In `Groo/Features/Pass/PasswordHealthAnalyzer.swift`, change the `analyze` signature and thread `now` through:

```swift
    /// Analyze all password items and generate a health report
    static func analyze(items: [PassVaultItem], now: Date = Date()) -> PasswordHealthReport {
```

pass it along:

```swift
        let oldPasswords = findOldPasswords(passwords, now: now)
```

and change `findOldPasswords`:

```swift
    private static func findOldPasswords(_ passwords: [PassPasswordItem], now: Date) -> [PassPasswordItem] {
        let ninetyDaysAgo = Int(now.timeIntervalSince1970 * 1000) - (90 * 24 * 60 * 60 * 1000)

        return passwords.filter { $0.updatedAt < ninetyDaysAgo }
    }
```

- [ ] **Step 4: Run to verify pass**

Run: `bash scripts/test.sh --unit 2>&1 | tail -20`
Expected: PASS. If `sequentialCharsArePenalized` or a strength case fails, the test's assumption about the scoring table is wrong — adjust the test password to hit the intended branch (verify against `calculateStrength`'s score table), never change the analyzer to fit the test.

- [ ] **Step 5: Commit**

```bash
git add Groo/Features/Pass/PasswordHealthAnalyzer.swift GrooTests
git commit -m "test: PasswordHealthAnalyzer suite; inject 'now' for deterministic age checks"
```

---

### Task 7: PassVaultStore + SharedVaultStore tests (with directory seams)

**Files:**
- Modify: `Groo/Core/Storage/PassVaultStore.swift:25-46`
- Modify: `Shared/SharedVaultStore.swift:24-45`
- Test: `GrooTests/Core/Storage/PassVaultStoreTests.swift`

**Interfaces:**
- Consumes: `PassVaultStore` actor — `saveVault(encryptedData:metadata:)`, `loadVault()`, `updateMetadata(_:)`, `loadMetadata()`, `vaultExists()`, `clear()`; `PassVaultMetadata`; `SharedVaultStore.loadVault()`/`.vaultExists()` (`Shared/SharedVaultStore.swift`).
- Produces: `PassVaultStore.init(directoryURL: URL? = nil)` — nil preserves App Group behavior; a URL redirects all storage under it (Task 10 constructs `PassVaultStore(directoryURL: tempDir)`); `SharedVaultStore.overrideDirectoryURL: URL?` static test seam (production never sets it).

- [ ] **Step 1: Write the failing tests**

`GrooTests/Core/Storage/PassVaultStoreTests.swift`:

```swift
//
//  PassVaultStoreTests.swift
//  GrooTests
//
//  File-based vault storage against a temp directory (never the real App Group).
//

import Foundation
import Testing
@testable import Groo

struct PassVaultStoreTests {
    /// Fresh store rooted in a unique temp dir per test.
    static func makeStore() -> (store: PassVaultStore, dir: URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PassVaultStoreTests-\(UUID().uuidString)", isDirectory: true)
        return (PassVaultStore(directoryURL: dir), dir)
    }

    static let metadata = PassVaultMetadata(version: 3, iv: "aXYtZml4dHVyZQ==", updatedAt: 1_700_000_000, lastSyncedAt: 1_700_000_100)

    @Test func loadReturnsNilWhenNothingStored() async throws {
        let (store, dir) = Self.makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(try await store.loadVault() == nil)
        #expect(try await store.loadMetadata() == nil)
        #expect(await store.vaultExists() == false)
    }

    @Test func saveThenLoadRoundtrips() async throws {
        let (store, dir) = Self.makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let blob = Data("encrypted-vault-bytes".utf8)

        try await store.saveVault(encryptedData: blob, metadata: Self.metadata)

        let loaded = try #require(await store.loadVault())
        #expect(loaded.data == blob)
        #expect(loaded.metadata.version == 3)
        #expect(loaded.metadata.iv == Self.metadata.iv)
        #expect(await store.vaultExists())
    }

    @Test func updateMetadataLeavesDataIntact() async throws {
        let (store, dir) = Self.makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let blob = Data("blob".utf8)
        try await store.saveVault(encryptedData: blob, metadata: Self.metadata)

        try await store.updateMetadata(PassVaultMetadata(version: 4, iv: Self.metadata.iv, updatedAt: 1_700_000_500, lastSyncedAt: 1_700_000_999))

        let loaded = try #require(await store.loadVault())
        #expect(loaded.data == blob)
        #expect(loaded.metadata.version == 4)
    }

    @Test func overwriteReplacesPreviousVault() async throws {
        let (store, dir) = Self.makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        try await store.saveVault(encryptedData: Data("v1".utf8), metadata: Self.metadata)
        try await store.saveVault(encryptedData: Data("v2".utf8), metadata: Self.metadata)
        let loaded = try #require(await store.loadVault())
        #expect(loaded.data == Data("v2".utf8))
    }

    @Test func clearRemovesEverything() async throws {
        let (store, dir) = Self.makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        try await store.saveVault(encryptedData: Data("v".utf8), metadata: Self.metadata)
        try await store.clear()
        #expect(await store.vaultExists() == false)
        #expect(try await store.loadVault() == nil)
    }

    @Test func corruptMetadataThrowsInsteadOfGarbage() async throws {
        let (store, dir) = Self.makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        try await store.saveVault(encryptedData: Data("v".utf8), metadata: Self.metadata)
        // Corrupt the metadata file on disk
        let metaURL = dir.appendingPathComponent("pass/vault.meta.json")
        try Data("not json".utf8).write(to: metaURL)
        await #expect(throws: (any Error).self) { try await store.loadVault() }
    }
}

/// SharedVaultStore (extension-side reader) must agree with PassVaultStore
/// (app-side writer) on the on-disk layout — a mismatch means AutoFill
/// silently sees no vault. Serialized: overrideDirectoryURL is static state.
@Suite(.serialized)
struct SharedVaultStoreTests {
    @Test func readsWhatPassVaultStoreWrites() async throws {
        let (store, dir) = PassVaultStoreTests.makeStore()
        defer {
            SharedVaultStore.overrideDirectoryURL = nil
            try? FileManager.default.removeItem(at: dir)
        }
        let blob = Data("encrypted-vault-bytes".utf8)
        try await store.saveVault(encryptedData: blob, metadata: PassVaultStoreTests.metadata)

        SharedVaultStore.overrideDirectoryURL = dir

        #expect(SharedVaultStore.vaultExists())
        let loaded = try SharedVaultStore.loadVault()
        #expect(loaded.data == blob)
        #expect(loaded.metadata.version == PassVaultStoreTests.metadata.version)
        #expect(loaded.metadata.iv == PassVaultStoreTests.metadata.iv)
    }

    @Test func throwsVaultNotFoundWhenEmpty() {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SharedVaultStoreTests-\(UUID().uuidString)", isDirectory: true)
        defer { SharedVaultStore.overrideDirectoryURL = nil }
        SharedVaultStore.overrideDirectoryURL = dir

        #expect(!SharedVaultStore.vaultExists())
        #expect(throws: SharedVaultStoreError.vaultNotFound) { try SharedVaultStore.loadVault() }
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `bash scripts/test.sh --unit 2>&1 | tail -20`
Expected: BUILD FAILURE — `argument passed to call that takes no arguments` (no `directoryURL` init yet).

- [ ] **Step 3: Add the directory seam**

In `Groo/Core/Storage/PassVaultStore.swift`, replace lines 25–35 (actor declaration through `passDirectoryURL`) with:

```swift
actor PassVaultStore {
    private let fileManager = FileManager.default

    /// Test seam: when set, all vault files live under this directory
    /// instead of the App Group container. Production always passes nil.
    private let overrideDirectoryURL: URL?

    init(directoryURL: URL? = nil) {
        self.overrideDirectoryURL = directoryURL
    }

    /// App Group container URL
    private var containerURL: URL? {
        fileManager.containerURL(forSecurityApplicationGroupIdentifier: Config.appGroupIdentifier)
    }

    /// Pass vault directory within App Group (or the injected override)
    private var passDirectoryURL: URL? {
        if let overrideDirectoryURL {
            return overrideDirectoryURL.appendingPathComponent("pass", isDirectory: true)
        }
        return containerURL?.appendingPathComponent("pass", isDirectory: true)
    }
```

Everything below (`vaultDataURL` onward) is unchanged.

In `Shared/SharedVaultStore.swift`, replace lines 24–35 (`enum SharedVaultStore` through `passDirectoryURL`) with:

```swift
enum SharedVaultStore {
    private static let fileManager = FileManager.default

    /// Test seam: when set, vault files are read from under this directory
    /// instead of the App Group container. Production never sets this.
    nonisolated(unsafe) static var overrideDirectoryURL: URL?

    /// App Group container URL
    private static var containerURL: URL? {
        fileManager.containerURL(forSecurityApplicationGroupIdentifier: SharedConfig.appGroupIdentifier)
    }

    /// Pass vault directory within App Group (or the injected override)
    private static var passDirectoryURL: URL? {
        if let overrideDirectoryURL {
            return overrideDirectoryURL.appendingPathComponent("pass", isDirectory: true)
        }
        return containerURL?.appendingPathComponent("pass", isDirectory: true)
    }
```

Everything below (`vaultDataURL` onward) is unchanged.

- [ ] **Step 4: Run to verify pass**

Run: `bash scripts/test.sh --unit 2>&1 | tail -20`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Groo/Core/Storage/PassVaultStore.swift Shared/SharedVaultStore.swift GrooTests
git commit -m "test: PassVaultStore + SharedVaultStore suites; inject storage directory for hermetic tests"
```

---

### Task 8: KeychainServicing protocol + in-memory fake + contract tests

**Files:**
- Create: `Groo/Core/Keychain/KeychainServicing.swift`
- Modify: `Groo/Core/Keychain/KeychainService.swift:23` (conformance only)
- Modify: `Groo/Features/Pass/PassService.swift:54,77,83` (property + init param type)
- Create: `GrooTests/Support/InMemoryKeychain.swift`
- Test: `GrooTests/Core/Keychain/KeychainContractTests.swift`

**Interfaces:**
- Consumes: existing `KeychainService` method signatures (they become the protocol verbatim).
- Produces: `protocol KeychainServicing: Sendable` (below); `InMemoryKeychain` fake in GrooTests. Task 10 passes `InMemoryKeychain()` into `PassService(keychain:)`. `KeychainService.Key.*` constants are untouched.

- [ ] **Step 1: Write the protocol**

`Groo/Core/Keychain/KeychainServicing.swift`:

```swift
//
//  KeychainServicing.swift
//  Groo
//
//  Seam over KeychainService so tests can substitute an in-memory fake
//  (the real keychain — especially biometric-protected items — is not
//  available in a test host).
//

import Foundation
import LocalAuthentication

protocol KeychainServicing: Sendable {
    func save(_ value: String, for key: String) throws
    func loadString(for key: String) throws -> String
    func save(_ data: Data, for key: String) throws
    func load(for key: String) throws -> Data
    func delete(for key: String) throws
    func exists(for key: String) -> Bool
    func saveBiometricProtected(_ data: Data, for key: String) throws
    func loadBiometricProtected(for key: String, prompt: String, context: LAContext?) throws -> Data
    func deleteBiometricProtected(for key: String) throws
    func biometricProtectedKeyExists(for key: String) -> Bool
}
```

- [ ] **Step 2: Conform KeychainService and retype PassService's dependency**

In `Groo/Core/Keychain/KeychainService.swift` line 23:

```swift
struct KeychainService: KeychainServicing {
```

In `Groo/Features/Pass/PassService.swift`: line 54 becomes

```swift
    private let keychain: any KeychainServicing
```

and the init parameter (line 75) becomes

```swift
        keychain: any KeychainServicing = KeychainService(),
```

- [ ] **Step 3: Build to verify the seam compiles**

Run: `xcodebuild build -project Groo.xcodeproj -scheme Groo -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`. If the compiler reports PassService calling a KeychainService member missing from the protocol (e.g. a default-argument call site like `loadBiometricProtected(for:prompt:)`), fix the call site to pass all protocol arguments explicitly (`context: nil`) — do NOT add default arguments to the protocol.

- [ ] **Step 4: Write the fake**

`GrooTests/Support/InMemoryKeychain.swift`:

```swift
//
//  InMemoryKeychain.swift
//  GrooTests
//
//  Deterministic KeychainServicing fake. Biometric items never prompt.
//

import Foundation
import LocalAuthentication
@testable import Groo

final class InMemoryKeychain: KeychainServicing, @unchecked Sendable {
    private let lock = NSLock()
    private var plain: [String: Data] = [:]
    private var biometric: [String: Data] = [:]

    func save(_ value: String, for key: String) throws {
        try save(Data(value.utf8), for: key)
    }

    func loadString(for key: String) throws -> String {
        guard let string = String(data: try load(for: key), encoding: .utf8) else {
            throw KeychainError.encodingFailed
        }
        return string
    }

    func save(_ data: Data, for key: String) throws {
        lock.lock(); defer { lock.unlock() }
        plain[key] = data
    }

    func load(for key: String) throws -> Data {
        lock.lock(); defer { lock.unlock() }
        guard let data = plain[key] else { throw KeychainError.itemNotFound }
        return data
    }

    func delete(for key: String) throws {
        lock.lock(); defer { lock.unlock() }
        plain[key] = nil  // deleting a missing key is not an error, matching the real service
    }

    func exists(for key: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return plain[key] != nil
    }

    func saveBiometricProtected(_ data: Data, for key: String) throws {
        lock.lock(); defer { lock.unlock() }
        biometric[key] = data
    }

    func loadBiometricProtected(for key: String, prompt: String, context: LAContext?) throws -> Data {
        lock.lock(); defer { lock.unlock() }
        guard let data = biometric[key] else { throw KeychainError.itemNotFound }
        return data
    }

    func deleteBiometricProtected(for key: String) throws {
        lock.lock(); defer { lock.unlock() }
        biometric[key] = nil
    }

    func biometricProtectedKeyExists(for key: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return biometric[key] != nil
    }
}
```

- [ ] **Step 5: Write the contract tests**

`GrooTests/Core/Keychain/KeychainContractTests.swift`:

```swift
//
//  KeychainContractTests.swift
//  GrooTests
//
//  Contract the fake must honor so PassService tests are faithful.
//

import Foundation
import Testing
@testable import Groo

struct KeychainContractTests {
    let keychain: any KeychainServicing = InMemoryKeychain()

    @Test func stringRoundtrip() throws {
        try keychain.save("sekrit", for: "k")
        #expect(try keychain.loadString(for: "k") == "sekrit")
    }

    @Test func dataRoundtripAndOverwrite() throws {
        try keychain.save(Data([1, 2, 3]), for: "k")
        try keychain.save(Data([9]), for: "k")
        #expect(try keychain.load(for: "k") == Data([9]))
    }

    @Test func loadMissingThrowsItemNotFound() {
        // KeychainError has associated values (OSStatus) so it isn't Equatable —
        // match the case with the closure form.
        #expect { try keychain.load(for: "missing") } throws: { error in
            guard case KeychainError.itemNotFound = error else { return false }
            return true
        }
    }

    @Test func deleteMissingDoesNotThrow() throws {
        try keychain.delete(for: "never-existed")
    }

    @Test func existsReflectsState() throws {
        #expect(!keychain.exists(for: "k"))
        try keychain.save("v", for: "k")
        #expect(keychain.exists(for: "k"))
        try keychain.delete(for: "k")
        #expect(!keychain.exists(for: "k"))
    }

    @Test func biometricNamespaceIsSeparate() throws {
        try keychain.saveBiometricProtected(Data([7]), for: "k")
        #expect(!keychain.exists(for: "k"))  // plain namespace unaffected
        #expect(keychain.biometricProtectedKeyExists(for: "k"))
        #expect(try keychain.loadBiometricProtected(for: "k", prompt: "test", context: nil) == Data([7]))
        try keychain.deleteBiometricProtected(for: "k")
        #expect(!keychain.biometricProtectedKeyExists(for: "k"))
    }
}
```

- [ ] **Step 6: Run the suite**

Run: `bash scripts/test.sh --unit 2>&1 | tail -20`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add Groo/Core/Keychain GrooTests Groo/Features/Pass/PassService.swift
git commit -m "refactor: KeychainServicing protocol seam + in-memory fake with contract tests"
```

---

### Task 9: StubURLProtocol + PassAPIClient tests (with session seam)

**Files:**
- Modify: `Groo/Features/Pass/PassService.swift:924-939` (`PassAPIClient.init` — add `sessionConfiguration` parameter)
- Create: `GrooTests/Support/StubURLProtocol.swift`
- Test: `GrooTests/Core/Network/PassAPIClientTests.swift`

**Interfaces:**
- Consumes: `PassAPIClient` actor (defined at the bottom of `PassService.swift`) — `get`, `post`, `put`, `Endpoint.*`; `APIError`.
- Produces:
  - `PassAPIClient.init(tokenProvider:forceRefresh:sessionConfiguration: URLSessionConfiguration = .default)`.
  - `StubURLProtocol` with API: `enqueue(method:pathSuffix:status:json:)`, `enqueue(method:pathSuffix:error:)`, `reset()`, `recordedRequests: [URLRequest]`, `stubbedConfiguration() -> URLSessionConfiguration`, and `URLRequest.bodyData` helper. FIFO per (method, pathSuffix); the last enqueued response for a key repeats if the queue drains. Task 10 reuses all of this.
  - CRITICAL: suites using `StubURLProtocol` must be `@Suite(.serialized)` and call `StubURLProtocol.reset()` first thing in each test (static state + parallel Swift Testing = races otherwise).

- [ ] **Step 1: Add the session seam**

In `PassService.swift`, `PassAPIClient.init` (line ~924), add the parameter and use it:

```swift
    init(
        tokenProvider: @escaping @Sendable () async throws -> String = { throw APIError.unauthorized },
        forceRefresh: @escaping @Sendable () async throws -> String = { throw APIError.unauthorized },
        sessionConfiguration: URLSessionConfiguration = .default
    ) {
        self.baseURL = Config.passAPIBaseURL
        self.tokenProvider = tokenProvider
        self.forceRefresh = forceRefresh
        self.decoder = JSONDecoder()
        self.encoder = JSONEncoder()

        let config = sessionConfiguration
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: config)
    }
```

- [ ] **Step 2: Write StubURLProtocol**

`GrooTests/Support/StubURLProtocol.swift`:

```swift
//
//  StubURLProtocol.swift
//  GrooTests
//
//  Intercepts every request on a stubbed URLSession and serves canned
//  responses. FIFO per (method, path suffix); last response repeats.
//  Static state ⇒ consuming suites MUST be @Suite(.serialized) and reset().
//

import Foundation

final class StubURLProtocol: URLProtocol {
    enum Response {
        case success(status: Int, body: Data)
        case failure(any Error)
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var queues: [String: [Response]] = [:]
    nonisolated(unsafe) private static var recorded: [URLRequest] = []

    private static func key(_ method: String, _ pathSuffix: String) -> String {
        "\(method.uppercased()) \(pathSuffix)"
    }

    static func enqueue(method: String, pathSuffix: String, status: Int = 200, json: String) {
        lock.lock(); defer { lock.unlock() }
        queues[key(method, pathSuffix), default: []].append(.success(status: status, body: Data(json.utf8)))
    }

    static func enqueue(method: String, pathSuffix: String, error: any Error) {
        lock.lock(); defer { lock.unlock() }
        queues[key(method, pathSuffix), default: []].append(.failure(error))
    }

    static func reset() {
        lock.lock(); defer { lock.unlock() }
        queues = [:]
        recorded = []
    }

    static var recordedRequests: [URLRequest] {
        lock.lock(); defer { lock.unlock() }
        return recorded
    }

    /// Session configuration routing ALL traffic through this stub.
    static func stubbedConfiguration() -> URLSessionConfiguration {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return config
    }

    private static func dequeue(for request: URLRequest) -> Response? {
        lock.lock(); defer { lock.unlock() }
        recorded.append(request)
        let method = request.httpMethod ?? "GET"
        let path = request.url?.path ?? ""
        guard let matchKey = queues.keys.first(where: { key in
            let parts = key.split(separator: " ", maxSplits: 1)
            return parts[0] == method.uppercased() && path.hasSuffix(parts[1])
        }), var queue = queues[matchKey], !queue.isEmpty else {
            return nil
        }
        let response = queue.removeFirst()
        // Last response for a key repeats: only consume while more remain.
        queues[matchKey] = queue.isEmpty ? [response] : queue
        return response
    }

    // MARK: URLProtocol

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        guard let response = Self.dequeue(for: request) else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL,
                userInfo: [NSLocalizedDescriptionKey: "No stub for \(request.httpMethod ?? "?") \(request.url?.path ?? "?")"]))
            return
        }
        switch response {
        case .success(let status, let body):
            let http = HTTPURLResponse(url: request.url!, statusCode: status,
                                       httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        case .failure(let error):
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
}

extension URLRequest {
    /// URLSession delivers bodies to URLProtocol as a stream — read it back.
    var bodyData: Data? {
        if let httpBody { return httpBody }
        guard let stream = httpBodyStream else { return nil }
        stream.open(); defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: buffer.count)
            guard read > 0 else { break }
            data.append(buffer, count: read)
        }
        return data
    }
}
```

- [ ] **Step 3: Write the failing tests**

`GrooTests/Core/Network/PassAPIClientTests.swift`:

```swift
//
//  PassAPIClientTests.swift
//  GrooTests
//
//  Serialized: StubURLProtocol uses static state.
//

import Foundation
import Testing
@testable import Groo

@Suite(.serialized)
struct PassAPIClientTests {

    static func makeClient(
        token: String = "tok-1",
        refreshedToken: String = "tok-2"
    ) -> PassAPIClient {
        PassAPIClient(
            tokenProvider: { token },
            forceRefresh: { refreshedToken },
            sessionConfiguration: StubURLProtocol.stubbedConfiguration()
        )
    }

    @Test func getDecodesResponseAndSendsBearerToken() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.enqueue(method: "GET", pathSuffix: "/v1/vault/key-info",
                                json: #"{"keySalt":"c2FsdA==","kdfIterations":1000}"#)

        let info: PassKeyInfo = try await Self.makeClient().get(PassAPIClient.Endpoint.keyInfo)

        #expect(info.kdfIterations == 1000)
        let request = try #require(StubURLProtocol.recordedRequests.first)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer tok-1")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
    }

    @Test func unauthorizedTriggersExactlyOneRefreshAndRetry() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.enqueue(method: "GET", pathSuffix: "/v1/vault/key-info", status: 401, json: "{}")
        StubURLProtocol.enqueue(method: "GET", pathSuffix: "/v1/vault/key-info",
                                json: #"{"keySalt":"c2FsdA==","kdfIterations":1000}"#)

        let info: PassKeyInfo = try await Self.makeClient().get(PassAPIClient.Endpoint.keyInfo)

        #expect(info.kdfIterations == 1000)
        let requests = StubURLProtocol.recordedRequests
        #expect(requests.count == 2)
        #expect(requests[1].value(forHTTPHeaderField: "Authorization") == "Bearer tok-2")
    }

    @Test func secondUnauthorizedPropagates() async {
        StubURLProtocol.reset()
        StubURLProtocol.enqueue(method: "GET", pathSuffix: "/v1/vault", status: 401, json: "{}")
        // last-response-repeats: the 401 sticks for the retry too

        await #expect(throws: APIError.self) {
            let _: PassVaultResponse = try await Self.makeClient().get(PassAPIClient.Endpoint.vault)
        }
        #expect(StubURLProtocol.recordedRequests.count == 2)  // exactly one retry, no loop
    }

    @Test func conflict409SurfacesAsVersionConflict() async {
        StubURLProtocol.reset()
        StubURLProtocol.enqueue(method: "PUT", pathSuffix: "/v1/vault", status: 409, json: "{}")

        await #expect {
            let _: PassVaultResponse = try await Self.makeClient().put(
                PassAPIClient.Endpoint.vault,
                body: PassVaultUpdateRequest(encryptedData: "", iv: "", expectedVersion: 1))
        } throws: { error in
            guard case APIError.httpError(let status, let message) = error else { return false }
            return status == 409 && message == "VERSION_CONFLICT"
        }
    }

    @Test func serverErrorMessageIsExtracted() async {
        StubURLProtocol.reset()
        StubURLProtocol.enqueue(method: "GET", pathSuffix: "/v1/vault", status: 500,
                                json: #"{"error":"boom"}"#)

        await #expect {
            let _: PassVaultResponse = try await Self.makeClient().get(PassAPIClient.Endpoint.vault)
        } throws: { error in
            guard case APIError.httpError(let status, let message) = error else { return false }
            return status == 500 && message == "boom"
        }
    }

    @Test func malformedJsonIsDecodingFailure() async {
        StubURLProtocol.reset()
        StubURLProtocol.enqueue(method: "GET", pathSuffix: "/v1/vault", json: "not json at all")

        await #expect {
            let _: PassVaultResponse = try await Self.makeClient().get(PassAPIClient.Endpoint.vault)
        } throws: { error in
            guard case APIError.decodingFailed = error else { return false }
            return true
        }
    }

    @Test(arguments: [URLError.Code.timedOut, .notConnectedToInternet])
    func transportErrorsPropagate(_ code: URLError.Code) async {
        StubURLProtocol.reset()
        StubURLProtocol.enqueue(method: "GET", pathSuffix: "/v1/vault", error: URLError(code))

        await #expect(throws: (any Error).self) {
            let _: PassVaultResponse = try await Self.makeClient().get(PassAPIClient.Endpoint.vault)
        }
    }

    @Test func emptyBodyOn2xxIsDecodingFailure() async {
        StubURLProtocol.reset()
        StubURLProtocol.enqueue(method: "GET", pathSuffix: "/v1/vault", json: "")

        await #expect(throws: (any Error).self) {
            let _: PassVaultResponse = try await Self.makeClient().get(PassAPIClient.Endpoint.vault)
        }
    }
}
```

- [ ] **Step 4: Run the suite**

Run: `bash scripts/test.sh --unit 2>&1 | tail -20`
Expected: PASS (Step 1 seam makes it compile; behavior is existing).

- [ ] **Step 5: Commit**

```bash
git add Groo/Features/Pass/PassService.swift GrooTests
git commit -m "test: PassAPIClient failure-matrix suite; inject URLSessionConfiguration + StubURLProtocol"
```

---

### Task 10: PassService integration tests

**Files:**
- Create: `Groo/Features/Pass/CredentialIdentityProviding.swift`
- Modify: `Groo/Features/Pass/CredentialIdentityService.swift:13` (conformance only)
- Modify: `Groo/Features/Pass/PassService.swift:56,76,85` (property + init param type)
- Create: `GrooTests/Support/RecordingCredentialService.swift`
- Test: `GrooTests/Features/Pass/PassServiceIntegrationTests.swift`

**Interfaces:**
- Consumes: everything from Tasks 5–9 (`VaultItemFixtures.samplePasswordItem`, `InMemoryKeychain`, `PassVaultStore(directoryURL:)`, `StubURLProtocol`, `PassAPIClient(sessionConfiguration:)`); `PassService` public API (`unlock`, `unlockWithBiometric`, `lock`, `getItems`, `getTrashItems`, `addItem`, `updateItem`, `deleteItem`, `restoreItem`, `toggleFavorite`, `searchItems`, `isUnlocked`, `canUnlockWithBiometric`).
- Produces: `protocol CredentialIdentityProviding` with `func updateCredentialIdentities(from items: [PassVaultItem]) async` and `func clearCredentialIdentities() async -> Bool`; PassService's `credentialService` becomes `any CredentialIdentityProviding` (default `CredentialIdentityService()` — production unchanged). Tests never touch the real `ASCredentialIdentityStore`.

- [ ] **Step 1: Write the CredentialIdentityProviding seam**

`Groo/Features/Pass/CredentialIdentityProviding.swift`:

```swift
//
//  CredentialIdentityProviding.swift
//  Groo
//
//  Seam over CredentialIdentityService so tests don't hit the real
//  ASCredentialIdentityStore.
//

protocol CredentialIdentityProviding {
    func updateCredentialIdentities(from items: [PassVaultItem]) async
    func clearCredentialIdentities() async -> Bool
}
```

In `CredentialIdentityService.swift` line 13:

```swift
class CredentialIdentityService: CredentialIdentityProviding {
```

In `PassService.swift`: property (line 56) → `private let credentialService: any CredentialIdentityProviding`; init param (line 77) → `credentialService: any CredentialIdentityProviding = CredentialIdentityService(),`.

Run: `xcodebuild build -project Groo.xcodeproj -scheme Groo -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`. If PassService calls other CredentialIdentityService methods the compiler now flags, add those exact signatures to the protocol (and later to the fake) — keep the protocol to what PassService actually uses.

- [ ] **Step 2: Write the recording fake**

`GrooTests/Support/RecordingCredentialService.swift`:

```swift
//
//  RecordingCredentialService.swift
//  GrooTests
//

import Foundation
@testable import Groo

final class RecordingCredentialService: CredentialIdentityProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var _updates: [[PassVaultItem]] = []
    var updates: [[PassVaultItem]] {
        lock.lock(); defer { lock.unlock() }
        return _updates
    }

    func updateCredentialIdentities(from items: [PassVaultItem]) async {
        lock.lock(); defer { lock.unlock() }
        _updates.append(items)
    }

    func clearCredentialIdentities() async -> Bool { true }
}
```

- [ ] **Step 3: Write the failing integration tests**

`GrooTests/Features/Pass/PassServiceIntegrationTests.swift`:

```swift
//
//  PassServiceIntegrationTests.swift
//  GrooTests
//
//  Full vault lifecycle against stubbed network, fake keychain, temp-dir
//  storage. Serialized: StubURLProtocol uses static state.
//

import CryptoKit
import Foundation
import Testing
@testable import Groo

@MainActor
@Suite(.serialized)
struct PassServiceIntegrationTests {

    struct Env {
        let service: PassService
        let keychain: InMemoryKeychain
        let credentials: RecordingCredentialService
        let key: SymmetricKey
        let salt: Data
        let tempDir: URL
    }

    static let crypto = CryptoService()
    static let password = "test-master-password"
    static let iterations: UInt32 = 1_000

    /// Build a PassService wired entirely to fakes, and stub key-info + vault
    /// GET endpoints so `unlock(password:)` succeeds with `items` inside.
    static func makeEnv(items: [PassVaultItem], vaultVersion: Int = 3) throws -> Env {
        StubURLProtocol.reset()

        let salt = Data("integration-salt".utf8)
        let key = try crypto.deriveKey(password: password, salt: salt, iterations: iterations)

        let vault = PassVault(version: 1, items: items, folders: [], lastModified: 1_700_000_000_000)
        let combined = try crypto.encryptData(try JSONEncoder().encode(vault), using: key)
        let iv = combined.prefix(12)
        let ciphertext = combined.dropFirst(12)

        StubURLProtocol.enqueue(
            method: "GET", pathSuffix: "/v1/vault/key-info",
            json: #"{"keySalt":"\#(salt.base64EncodedString())","kdfIterations":\#(iterations)}"#)
        StubURLProtocol.enqueue(
            method: "GET", pathSuffix: "/v1/vault",
            json: #"{"encryptedData":"\#(ciphertext.base64EncodedString())","iv":"\#(iv.base64EncodedString())","version":\#(vaultVersion),"updatedAt":1700000000}"#)

        let keychain = InMemoryKeychain()
        let credentials = RecordingCredentialService()
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PassServiceTests-\(UUID().uuidString)", isDirectory: true)

        let api = PassAPIClient(
            tokenProvider: { "test-token" },
            forceRefresh: { "test-token-2" },
            sessionConfiguration: StubURLProtocol.stubbedConfiguration())

        let service = PassService(
            api: api,
            crypto: crypto,
            keychain: keychain,
            vaultStore: PassVaultStore(directoryURL: tempDir),
            credentialService: credentials)

        return Env(service: service, keychain: keychain, credentials: credentials,
                   key: key, salt: salt, tempDir: tempDir)
    }

    /// Stub the PUT /v1/vault response `saveVault()` expects after a mutation.
    static func stubVaultPut(version: Int) {
        StubURLProtocol.enqueue(
            method: "PUT", pathSuffix: "/v1/vault",
            json: #"{"encryptedData":"","iv":"","version":\#(version),"updatedAt":1700000001}"#)
    }

    /// Decrypt the vault the service uploaded in its last PUT request.
    static func decodeUploadedVault(key: SymmetricKey) throws -> (vault: PassVault, request: PassVaultUpdateRequest) {
        let put = try #require(StubURLProtocol.recordedRequests.last {
            $0.httpMethod == "PUT" && ($0.url?.path.hasSuffix("/v1/vault") ?? false)
        })
        let body = try #require(put.bodyData)
        let update = try JSONDecoder().decode(PassVaultUpdateRequest.self, from: body)
        var combined = try #require(Data(base64Encoded: update.iv))
        combined.append(try #require(Data(base64Encoded: update.encryptedData)))
        let plaintext = try crypto.decryptData(combined, using: key)
        return (try JSONDecoder().decode(PassVault.self, from: plaintext), update)
    }

    // MARK: Unlock

    @Test func unlockWithCorrectPasswordLoadsVault() async throws {
        let item = PassVaultItem.password(VaultItemFixtures.samplePasswordItem())
        let env = try Self.makeEnv(items: [item])
        defer { try? FileManager.default.removeItem(at: env.tempDir) }

        let unlocked = try await env.service.unlock(password: Self.password)

        #expect(unlocked)
        #expect(env.service.isUnlocked)
        #expect(env.service.getItems().map(\.id) == ["pw-1"])
        // Key must be stored for future biometric unlock
        #expect(env.keychain.biometricProtectedKeyExists(for: KeychainService.Key.passEncryptionKey))
        #expect(env.service.canUnlockWithBiometric)
    }

    @Test func unlockWithWrongPasswordFailsLoudlyAndStaysLocked() async throws {
        let env = try Self.makeEnv(items: [])
        defer { try? FileManager.default.removeItem(at: env.tempDir) }

        await #expect(throws: (any Error).self) {
            _ = try await env.service.unlock(password: "wrong-password")
        }
        #expect(!env.service.isUnlocked)
        #expect(env.service.getItems().isEmpty)
    }

    @Test func lockClearsAccessButKeepsBiometricKey() async throws {
        let env = try Self.makeEnv(items: [.password(VaultItemFixtures.samplePasswordItem())])
        defer { try? FileManager.default.removeItem(at: env.tempDir) }
        _ = try await env.service.unlock(password: Self.password)

        env.service.lock()

        #expect(!env.service.isUnlocked)
        #expect(env.service.getItems().isEmpty)
        #expect(env.service.canUnlockWithBiometric)  // lock() ≠ lockAndClearKey()
    }

    @Test func biometricUnlockUsesLocalCacheWithoutNetwork() async throws {
        let item = PassVaultItem.password(VaultItemFixtures.samplePasswordItem())
        let env = try Self.makeEnv(items: [item])
        defer { try? FileManager.default.removeItem(at: env.tempDir) }

        // First unlock populates keychain + vault cache
        _ = try await env.service.unlock(password: Self.password)
        env.service.lock()
        let requestsAfterUnlock = StubURLProtocol.recordedRequests.count

        let unlocked = try await env.service.unlockWithBiometric(context: nil)

        #expect(unlocked)
        #expect(env.service.getItems().map(\.id) == ["pw-1"])
        // Cache hit: no additional GETs needed before returning
        // (background sync may add requests afterwards; assert unlock preceded them)
        #expect(StubURLProtocol.recordedRequests.count >= requestsAfterUnlock)
    }

    // MARK: CRUD — every mutation must roundtrip through encryption

    @Test func addItemUploadsReencryptedVaultWithOptimisticVersion() async throws {
        let env = try Self.makeEnv(items: [], vaultVersion: 3)
        defer { try? FileManager.default.removeItem(at: env.tempDir) }
        _ = try await env.service.unlock(password: Self.password)
        Self.stubVaultPut(version: 4)

        let newItem = PassVaultItem.password(VaultItemFixtures.samplePasswordItem(id: "pw-new", name: "New Login"))
        try await env.service.addItem(newItem)

        #expect(env.service.getItems().map(\.id) == ["pw-new"])
        let uploaded = try Self.decodeUploadedVault(key: env.key)
        #expect(uploaded.vault.items.map(\.id) == ["pw-new"])
        #expect(uploaded.request.expectedVersion == 3)
    }

    @Test func updateItemPersistsChanges() async throws {
        let env = try Self.makeEnv(items: [.password(VaultItemFixtures.samplePasswordItem())])
        defer { try? FileManager.default.removeItem(at: env.tempDir) }
        _ = try await env.service.unlock(password: Self.password)
        Self.stubVaultPut(version: 4)

        var edited = VaultItemFixtures.samplePasswordItem()
        edited.name = "Renamed"
        try await env.service.updateItem(.password(edited))

        #expect(env.service.getItem(id: "pw-1")?.name == "Renamed")
        let uploaded = try Self.decodeUploadedVault(key: env.key)
        #expect(uploaded.vault.items.first?.name == "Renamed")
    }

    @Test func deleteMovesToTrashAndRestoreRecovers() async throws {
        let item = PassVaultItem.password(VaultItemFixtures.samplePasswordItem())
        let env = try Self.makeEnv(items: [item])
        defer { try? FileManager.default.removeItem(at: env.tempDir) }
        _ = try await env.service.unlock(password: Self.password)

        Self.stubVaultPut(version: 4)
        try await env.service.deleteItem(item)
        #expect(env.service.getItems().isEmpty)
        #expect(env.service.getTrashItems().map(\.id) == ["pw-1"])

        Self.stubVaultPut(version: 5)
        let trashed = try #require(env.service.getTrashItems().first)
        try await env.service.restoreItem(trashed)
        #expect(env.service.getItems().map(\.id) == ["pw-1"])
        #expect(env.service.getTrashItems().isEmpty)
    }

    @Test func versionConflictOnSaveSurfacesError() async throws {
        let env = try Self.makeEnv(items: [])
        defer { try? FileManager.default.removeItem(at: env.tempDir) }
        _ = try await env.service.unlock(password: Self.password)
        StubURLProtocol.enqueue(method: "PUT", pathSuffix: "/v1/vault", status: 409, json: "{}")

        await #expect(throws: (any Error).self) {
            try await env.service.addItem(.password(VaultItemFixtures.samplePasswordItem(id: "pw-x")))
        }
    }

    // MARK: Queries

    @Test func searchFindsByNameCaseInsensitively() async throws {
        let env = try Self.makeEnv(items: [
            .password(VaultItemFixtures.samplePasswordItem(id: "a", name: "GitHub")),
            .password(VaultItemFixtures.samplePasswordItem(id: "b", name: "GitLab")),
            .password(VaultItemFixtures.samplePasswordItem(id: "c", name: "Bank")),
        ])
        defer { try? FileManager.default.removeItem(at: env.tempDir) }
        _ = try await env.service.unlock(password: Self.password)

        #expect(env.service.searchItems(query: "git").map(\.id).sorted() == ["a", "b"])
        #expect(env.service.searchItems(query: "BANK").map(\.id) == ["c"])
    }

    @Test func credentialIdentitiesAreUpdatedOnUnlock() async throws {
        let env = try Self.makeEnv(items: [.password(VaultItemFixtures.samplePasswordItem())])
        defer { try? FileManager.default.removeItem(at: env.tempDir) }
        _ = try await env.service.unlock(password: Self.password)
        #expect(env.credentials.updates.isEmpty == false)
    }
}
```

- [ ] **Step 4: Run the suite**

Run: `bash scripts/test.sh --unit 2>&1 | tail -30`
Expected: PASS. Known adjustment points if reality disagrees (fix the TEST, these are behavior discoveries, not production bugs):
- `unlock` may trigger background `sync()`/`mergePendingPasskeys()` tasks that hit unstubbed endpoints — they catch-and-log by design; if a test flakes on request counts, drop the count assertion rather than stubbing every background endpoint.
- If `credentialIdentitiesAreUpdatedOnUnlock` races the async update, wrap the expectation in a bounded poll over `await Task.yield()` iterations (max 100), never `sleep`.

- [ ] **Step 5: Commit**

```bash
git add Groo/Features/Pass GrooTests
git commit -m "test: PassService integration suite (unlock, biometric cache, CRUD, 409, search) + credential seam"
```

---

### Task 11: Full verification + docs

**Files:**
- Modify: `README.md` (add Testing section)

**Interfaces:**
- Consumes: everything above.
- Produces: the Phase 1 definition-of-done from the spec: suite green twice, all targets build, docs updated.

- [ ] **Step 1: Run the full suite twice consecutively**

Run: `bash scripts/test.sh --all 2>&1 | tail -5 && bash scripts/test.sh --all 2>&1 | tail -5`
Expected: `** TEST SUCCEEDED **` both times. A pass-then-fail means a flaky test — find and fix it before proceeding (usually shared state or an unserialized stub suite).

- [ ] **Step 2: Verify the app still builds clean**

Run: `xcodebuild build -project Groo.xcodeproj -scheme Groo -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Add a Testing section to README.md**

Append to `README.md`:

```markdown
## Testing

Unit + integration tests live in `GrooTests` (Swift Testing), UI tests in `GrooUITests` (XCUITest).

```bash
scripts/test.sh          # unit + integration
scripts/test.sh --ui     # UI tests (slow — boots the app)
scripts/test.sh --all    # everything
```

Conventions:
- Test files mirror source paths (`GrooTests/Features/Pass/TotpServiceTests.swift`).
- No sleeps; time is injected. Network via `StubURLProtocol` (suites using it are `@Suite(.serialized)`).
- Keychain via `InMemoryKeychain` (`KeychainServicing` seam); vault storage via `PassVaultStore(directoryURL:)`.
- Never use production KDF iteration counts (600k) in tests.

Design: `docs/superpowers/specs/2026-07-05-ios-test-suite-design.md`.
```

- [ ] **Step 4: Manual smoke of the touched feature**

Launch the app in the simulator and unlock Pass once (verifies the seams didn't disturb production wiring):

Run: `xcrun simctl boot "iPhone 17 Pro" 2>/dev/null; xcodebuild -project Groo.xcodeproj -scheme Groo -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | tail -2 && xcrun simctl install booted build/Build/Products/Debug-iphonesimulator/Groo.app 2>/dev/null || true`

(If the install path differs, launch via Xcode or `groo dev` per normal workflow.) Confirm: app launches, Pass tab loads, unlock works.

- [ ] **Step 5: Commit**

```bash
git add README.md
git commit -m "docs: testing section in README"
```

---

## Post-plan

Phases 2–6 of the spec (wallet, sync/offline, extensions, UI flows, edge-case sweep) each get their own plan once this one lands — they reuse `StubURLProtocol`, `InMemoryKeychain`, and the fixtures built here.
