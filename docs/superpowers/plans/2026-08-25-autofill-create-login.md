# Creating a login from the AutoFill sheet — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a user create a new login from inside the AutoFill credential
sheet — typed or generated — save it durably, and fill the field with it
without leaving the sign-up flow.

**Architecture:** The extension authors the item, writes it to a new encrypted
App Group queue (`pass/pending_passwords.enc`), best-effort pushes it as one
new per-item record, then completes the AutoFill request. The main app drains
the queue into the vault on its next run. This is the same shape passkey
registration already uses; the new code mirrors `PasskeyPublisher` and
`SharedPendingItemsStore` deliberately rather than inventing a second pattern.

**Tech Stack:** Swift 6 / SwiftUI, AuthenticationServices credential provider
extension, CryptoKit (AES-GCM), Swift Testing (`@Test`/`#expect`), xcodebuild.

**Spec:** `docs/superpowers/specs/2026-08-24-autofill-create-login-design.md`

## Global Constraints

- **Every new `Shared/` file must be registered**: `ruby
  scripts/register_shared_file.rb <File.swift> Groo GrooAutoFill GrooTests`.
  `Shared/` is not a filesystem-synchronized group — an unregistered file
  compiles into nothing and its tests silently do not exist. Files under
  `GrooAutoFill/` and `GrooTests/` are picked up automatically.
- **No credential material in logs.** `password`, `username`, and the record
  payload must never appear in a log line at any level. Log the item `id` only.
- **The extension never force-refreshes tokens.** Every `PassAPIClient` built
  in extension code passes `forceRefresh: { throw APIError.unauthorized }`. A
  late refresh from an extension revokes the refresh-token family and signs the
  user out on every device.
- **Optional fields are omitted, never sent as null** in a record payload
  (`notes`, `totp`, `folderId`, `favorite`, `deletedAt`).
- **`createdAt` and `updatedAt` are required** by every other client and are
  not modelled on `SharedPassPasswordItem`. They travel in the queue envelope.
- **Test suite baseline:** `scripts/test.sh --unit` must pass at the end of
  every task. Single-suite runs use
  `xcodebuild test -project Groo.xcodeproj -scheme Groo -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:GrooTests/<SuiteName>`.
- **Commit after every task**, on branch `feat/autofill-create-login`.

## File Structure

| File | Responsibility |
|---|---|
| `Shared/SharedPasswordGenerator.swift` (new) | Pure password generation, shared by app and extension |
| `Shared/SharedNewLoginDraft.swift` (new) | The new-login form's pure logic: defaults, URL normalization, validation, item construction |
| `Shared/SharedPendingPasswordsStore.swift` (new) | The `pending_passwords.enc` queue |
| `Shared/SharedPendingQueue.swift` (new) | Generic encrypted-queue mechanics used by both pending stores |
| `Shared/PasswordPublisher.swift` (new) | Builds the record payload and pushes it; never throws |
| `Shared/SharedPassModels.swift` (modify) | Memberwise init on `SharedPassPasswordItem`; `SharedPendingPasswordItem` envelope |
| `Shared/SharedCredentialMatcher.swift` (modify) | `mergingPendingPasswords(vault:pending:)` |
| `Shared/SharedConfig.swift` (modify) | `passwordPushDeadlineSeconds` |
| `Shared/SharedPendingItemsStore.swift` (modify) | Delegates to `SharedPendingQueue`; public API unchanged |
| `GrooAutoFill/NewLoginView.swift` (new) | The form |
| `GrooAutoFill/AutoFillService.swift` (modify) | `createPassword`, pending-password merge on read |
| `GrooAutoFill/AutoFillCredentialListView.swift` (modify) | `+` toolbar item and empty-state action |
| `GrooAutoFill/CredentialProviderViewController.swift` (modify) | `allowsCreatingPassword` per entry point; completes with the new credential |
| `Groo/Features/Pass/PendingPasskeyStoring.swift` (modify) | Adds `PendingPasswordStoring` |
| `Groo/Features/Pass/PassService.swift` (modify) | `mergePendingItems()`, `pendingSyncCount` |
| `Groo/Features/Pass/Views/PasswordGeneratorView.swift` (modify) | Calls the shared generator |
| `Groo/Features/Pass/Views/PassItemListView.swift` (modify) | Waiting-to-sync banner |

---

### Task 1: Shared password generator

The generator today is a `private func generatePassword()` inside a SwiftUI
view (`Groo/Features/Pass/Views/PasswordGeneratorView.swift:238`). The
extension is a different target and cannot see it, and being private inside a
`View` it has never been tested. Extract it unchanged in behaviour.

**Files:**
- Create: `Shared/SharedPasswordGenerator.swift`
- Modify: `Groo/Features/Pass/Views/PasswordGeneratorView.swift:238-299`
- Test: `GrooTests/Shared/SharedPasswordGeneratorTests.swift`

**Interfaces:**
- Consumes: nothing
- Produces: `SharedPasswordGeneratorOptions` (`length: Int = 20`,
  `includeUppercase/includeLowercase/includeNumbers/includeSymbols: Bool = true`)
  and `SharedPasswordGenerator.generate(_ options:) -> String`

- [ ] **Step 1: Write the failing test**

Create `GrooTests/Shared/SharedPasswordGeneratorTests.swift`:

```swift
//
//  SharedPasswordGeneratorTests.swift
//  GrooTests
//

import Foundation
import Testing
@testable import Groo

struct SharedPasswordGeneratorTests {
    private static let symbols = "!@#$%^&*()_+-=[]{}|;:,.<>?"

    @Test func generatesRequestedLength() {
        var options = SharedPasswordGeneratorOptions()
        options.length = 32
        #expect(SharedPasswordGenerator.generate(options).count == 32)
    }

    @Test func includesAtLeastOneOfEveryEnabledClass() {
        // Run repeatedly: a guarantee that holds only sometimes is not one.
        for _ in 0..<200 {
            var options = SharedPasswordGeneratorOptions()
            options.length = 8
            let password = SharedPasswordGenerator.generate(options)
            #expect(password.contains(where: \.isUppercase))
            #expect(password.contains(where: \.isLowercase))
            #expect(password.contains(where: \.isNumber))
            #expect(password.contains(where: { Self.symbols.contains($0) }))
        }
    }

    @Test func omitsDisabledClasses() {
        var options = SharedPasswordGeneratorOptions()
        options.length = 40
        options.includeSymbols = false
        options.includeNumbers = false

        let password = SharedPasswordGenerator.generate(options)

        #expect(!password.contains(where: { Self.symbols.contains($0) }))
        #expect(!password.contains(where: \.isNumber))
        #expect(password.allSatisfy { $0.isLetter })
    }

    @Test func emptyCharsetYieldsEmptyPassword() {
        var options = SharedPasswordGeneratorOptions()
        options.includeUppercase = false
        options.includeLowercase = false
        options.includeNumbers = false
        options.includeSymbols = false

        #expect(SharedPasswordGenerator.generate(options).isEmpty)
    }

    @Test func successiveCallsDiffer() {
        let options = SharedPasswordGeneratorOptions()
        let first = SharedPasswordGenerator.generate(options)
        let second = SharedPasswordGenerator.generate(options)
        #expect(first != second)
    }

    /// A length shorter than the number of enabled classes cannot satisfy every
    /// guarantee. It must still return exactly `length` characters rather than
    /// overrun the buffer.
    @Test func lengthShorterThanClassCountStaysInBounds() {
        var options = SharedPasswordGeneratorOptions()
        options.length = 2
        #expect(SharedPasswordGenerator.generate(options).count == 2)
    }
}
```

- [ ] **Step 2: Run the test and watch it fail**

Run: `xcodebuild test -project Groo.xcodeproj -scheme Groo -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:GrooTests/SharedPasswordGeneratorTests`
Expected: build failure — `cannot find 'SharedPasswordGenerator' in scope`.

- [ ] **Step 3: Write the generator**

Create `Shared/SharedPasswordGenerator.swift`:

```swift
//
//  SharedPasswordGenerator.swift
//  Groo
//
//  Password generation, extracted from PasswordGeneratorView so the AutoFill
//  extension can generate too — a different target cannot see an app-target
//  view, and a `private func` inside a `View` cannot be tested at all.
//

import Foundation

struct SharedPasswordGeneratorOptions {
    var length: Int = 20
    var includeUppercase = true
    var includeLowercase = true
    var includeNumbers = true
    var includeSymbols = true

    static let uppercase = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    static let lowercase = "abcdefghijklmnopqrstuvwxyz"
    static let numbers = "0123456789"
    static let symbols = "!@#$%^&*()_+-=[]{}|;:,.<>?"

    /// The character classes the caller enabled, each as its own alphabet, so
    /// the generator can guarantee one character from each.
    var enabledClasses: [String] {
        var classes: [String] = []
        if includeUppercase { classes.append(Self.uppercase) }
        if includeLowercase { classes.append(Self.lowercase) }
        if includeNumbers { classes.append(Self.numbers) }
        if includeSymbols { classes.append(Self.symbols) }
        return classes
    }
}

enum SharedPasswordGenerator {
    /// Generate a password containing at least one character from every enabled
    /// class, when the requested length allows it.
    ///
    /// `randomElement()` draws from `SystemRandomNumberGenerator`, which is
    /// cryptographically secure on Apple platforms. Do not swap it for a seeded
    /// generator to make tests deterministic — assert properties instead.
    static func generate(_ options: SharedPasswordGeneratorOptions) -> String {
        let classes = options.enabledClasses
        guard !classes.isEmpty, options.length > 0 else { return "" }

        let alphabet = Array(classes.joined())

        // One guaranteed character per class first, then fill. Truncating to
        // `length` keeps a short request in bounds rather than overrunning it.
        var characters: [Character] = classes
            .prefix(options.length)
            .compactMap { Array($0).randomElement() }

        while characters.count < options.length {
            if let next = alphabet.randomElement() { characters.append(next) }
        }

        return String(characters.shuffled())
    }
}
```

- [ ] **Step 4: Register the file with every consuming target**

Run: `ruby scripts/register_shared_file.rb SharedPasswordGenerator.swift Groo GrooAutoFill GrooTests`
Expected: the script prints what it added and exits 0. It is idempotent.

- [ ] **Step 5: Run the test and watch it pass**

Run: `xcodebuild test -project Groo.xcodeproj -scheme Groo -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:GrooTests/SharedPasswordGeneratorTests`
Expected: PASS, 6 tests.

- [ ] **Step 6: Rewire `PasswordGeneratorView` to the shared generator**

In `Groo/Features/Pass/Views/PasswordGeneratorView.swift`, delete the whole
`private func generatePassword()` body (from `// MARK: - Password Generation`
through the closing brace of the function, currently `:236-299`) and replace
it with:

```swift
    // MARK: - Password Generation

    private func generatePassword() {
        var options = SharedPasswordGeneratorOptions()
        options.length = Int(length)
        options.includeUppercase = includeUppercase
        options.includeLowercase = includeLowercase
        options.includeNumbers = includeNumbers
        options.includeSymbols = includeSymbols
        password = SharedPasswordGenerator.generate(options)
    }
```

Leave every other part of the view — the slider bounds, the toggles, the
`.onAppear` and `.onChange` calls — untouched.

- [ ] **Step 7: Run the full unit suite**

Run: `scripts/test.sh --unit`
Expected: PASS. The existing `PassViewSnapshotTests` cover the generator
screen; if a snapshot for `passgen` fails, the view's layout was changed by
mistake — revert the layout, not the snapshot.

- [ ] **Step 8: Commit**

```bash
git add Shared/SharedPasswordGenerator.swift GrooTests/Shared/SharedPasswordGeneratorTests.swift Groo/Features/Pass/Views/PasswordGeneratorView.swift Groo.xcodeproj/project.pbxproj
git commit -m "refactor(pass): extract password generation into Shared

A private func inside a SwiftUI view is invisible to the AutoFill
extension and untestable. Same algorithm, now with property tests."
```

---

### Task 2: The item envelope and the draft model

`SharedPassPasswordItem` declares `init(from decoder:)` in its body
(`Shared/SharedPassModels.swift:190`) and no other initializer, so Swift
synthesizes no memberwise init — today the type can only be produced by
decoding. `SharedPassPasskeyItem` already carries an explicit init
(`:250`) for exactly this reason. It also models no `createdAt`/`updatedAt`,
which every other client requires, so the queue stores an envelope carrying
both timestamps.

**Files:**
- Modify: `Shared/SharedPassModels.swift` (add init after `:207`, add envelope at end of file)
- Create: `Shared/SharedNewLoginDraft.swift`
- Test: `GrooTests/Shared/SharedNewLoginDraftTests.swift`

**Interfaces:**
- Consumes: `SharedPassPasswordItem`, `SharedPasswordGenerator` (Task 1)
- Produces:
  - `SharedPassPasswordItem.init(id:type:name:username:password:urls:totp:deletedAt:)`
  - `struct SharedPendingPasswordItem: Codable { let item: SharedPassPasswordItem; let createdAt: Int; let updatedAt: Int }`
  - `struct SharedNewLoginDraft` with `name`, `username`, `password`, `site`,
    `static defaultName(forHost:) -> String`,
    `static normalizedURL(_:) -> String?`, `var isSaveable: Bool`,
    `func pendingItem(id:now:) -> SharedPendingPasswordItem`

- [ ] **Step 1: Write the failing test**

Create `GrooTests/Shared/SharedNewLoginDraftTests.swift`:

```swift
//
//  SharedNewLoginDraftTests.swift
//  GrooTests
//

import Foundation
import Testing
@testable import Groo

struct SharedNewLoginDraftTests {

    // MARK: - Default name

    @Test func defaultNameStripsLeadingWww() {
        #expect(SharedNewLoginDraft.defaultName(forHost: "www.github.com") == "github.com")
    }

    @Test func defaultNameKeepsASubdomainThatIsNotWww() {
        // accounts.google.com is a different service from google.com; trimming
        // it would file the item under the wrong name.
        #expect(SharedNewLoginDraft.defaultName(forHost: "accounts.google.com") == "accounts.google.com")
    }

    @Test func defaultNameFallsBackWhenThereIsNoHost() {
        #expect(SharedNewLoginDraft.defaultName(forHost: nil) == "New Login")
        #expect(SharedNewLoginDraft.defaultName(forHost: "") == "New Login")
    }

    // MARK: - URL normalization

    @Test func bareDomainGetsHttpsScheme() {
        #expect(SharedNewLoginDraft.normalizedURL("github.com") == "https://github.com")
    }

    @Test func existingSchemeIsPreserved() {
        #expect(SharedNewLoginDraft.normalizedURL("http://example.test") == "http://example.test")
        #expect(SharedNewLoginDraft.normalizedURL("https://example.test/login") == "https://example.test/login")
    }

    @Test func whitespaceIsTrimmedAndEmptyYieldsNil() {
        #expect(SharedNewLoginDraft.normalizedURL("  github.com  ") == "https://github.com")
        #expect(SharedNewLoginDraft.normalizedURL("   ") == nil)
    }

    // MARK: - Validation

    @Test func aDraftWithoutAPasswordCannotBeSaved() {
        var draft = SharedNewLoginDraft(name: "github.com", username: "me", password: "", site: "github.com")
        #expect(!draft.isSaveable)
        draft.password = "hunter2"
        #expect(draft.isSaveable)
    }

    @Test func anEmptyUsernameIsAllowed() {
        // Plenty of sign-ups collect the identifier on a later screen.
        let draft = SharedNewLoginDraft(name: "github.com", username: "", password: "hunter2", site: "github.com")
        #expect(draft.isSaveable)
    }

    // MARK: - Item construction

    @Test func buildsAPasswordItemCarryingTheNormalizedURL() {
        let draft = SharedNewLoginDraft(name: "github.com", username: "me", password: "hunter2", site: "github.com")

        let pending = draft.pendingItem(id: "item-1", now: 1_700_000_000_123)

        #expect(pending.item.id == "item-1")
        #expect(pending.item.type == .password)
        #expect(pending.item.name == "github.com")
        #expect(pending.item.username == "me")
        #expect(pending.item.password == "hunter2")
        #expect(pending.item.urls == ["https://github.com"])
        #expect(pending.item.totp == nil)
        #expect(pending.item.deletedAt == nil)
        #expect(pending.createdAt == 1_700_000_000_123)
        #expect(pending.updatedAt == 1_700_000_000_123)
    }

    @Test func aBlankNameFallsBackToTheSite() {
        let draft = SharedNewLoginDraft(name: "   ", username: "me", password: "hunter2", site: "github.com")
        #expect(draft.pendingItem(id: "item-1", now: 1).item.name == "github.com")
    }

    @Test func aDraftWithNoSiteHasNoURLs() {
        let draft = SharedNewLoginDraft(name: "Manual", username: "me", password: "hunter2", site: "")
        #expect(draft.pendingItem(id: "item-1", now: 1).item.urls.isEmpty)
    }

    @Test func theEnvelopeRoundTripsThroughJSON() throws {
        let pending = SharedNewLoginDraft(name: "github.com", username: "me", password: "hunter2", site: "github.com")
            .pendingItem(id: "item-1", now: 1_700_000_000_123)

        let data = try JSONEncoder().encode(pending)
        let decoded = try JSONDecoder().decode(SharedPendingPasswordItem.self, from: data)

        #expect(decoded.item.password == "hunter2")
        #expect(decoded.createdAt == 1_700_000_000_123)
    }
}
```

- [ ] **Step 2: Run the test and watch it fail**

Run: `xcodebuild test -project Groo.xcodeproj -scheme Groo -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:GrooTests/SharedNewLoginDraftTests`
Expected: build failure — `cannot find 'SharedNewLoginDraft' in scope`.

- [ ] **Step 3: Add the memberwise init and the envelope**

In `Shared/SharedPassModels.swift`, immediately after the closing brace of
`SharedPassPasswordItem.init(from decoder:)` (currently line 207) and still
inside the struct, add:

```swift
    /// Memberwise init, absent by synthesis because `init(from:)` is declared
    /// in the body. Needed because the AutoFill extension now AUTHORS this
    /// item — `SharedPassPasskeyItem` carries one for the same reason.
    init(
        id: String,
        type: SharedPassVaultItemType = .password,
        name: String,
        username: String,
        password: String,
        urls: [String],
        totp: SharedPassTotpConfig? = nil,
        deletedAt: Int? = nil
    ) {
        self.id = id
        self.type = type
        self.name = name
        self.username = username
        self.password = password
        self.urls = urls
        self.totp = totp
        self.deletedAt = deletedAt
    }
```

Then, at the end of the same file, add the envelope:

```swift
// MARK: - Pending Password Envelope

/// A password item queued by the AutoFill extension, with the timestamps
/// `SharedPassPasswordItem` does not model.
///
/// The timestamps must survive the queue, not be re-stamped when the app
/// drains it: the app rebuilds the record payload from this envelope, and it
/// must come out byte-identical to what the extension already pushed —
/// otherwise the drain rewrites a record that was already correct.
struct SharedPendingPasswordItem: Codable {
    let item: SharedPassPasswordItem
    let createdAt: Int
    let updatedAt: Int
}
```

- [ ] **Step 4: Write the draft model**

Create `Shared/SharedNewLoginDraft.swift`:

```swift
//
//  SharedNewLoginDraft.swift
//  Groo
//
//  The new-login form's pure logic. Lives in Shared/ rather than in
//  GrooAutoFill so GrooTests can reach it: the test bundle hosts the app, so
//  nothing declared in the extension target is testable.
//

import Foundation

struct SharedNewLoginDraft {
    var name: String
    var username: String
    var password: String
    /// The site as typed or prefilled — a bare host, or a full URL.
    var site: String

    init(name: String = "", username: String = "", password: String = "", site: String = "") {
        self.name = name
        self.username = username
        self.password = password
        self.site = site
    }

    /// Default item name for the host of the request being filled.
    ///
    /// Only a leading `www.` is stripped. Deeper subdomains are kept:
    /// `accounts.google.com` is a different service from `google.com`, and
    /// collapsing it files the item under a name the user did not mean.
    static func defaultName(forHost host: String?) -> String {
        guard let host, !host.trimmingCharacters(in: .whitespaces).isEmpty else {
            return "New Login"
        }
        let trimmed = host.trimmingCharacters(in: .whitespaces)
        return trimmed.hasPrefix("www.") ? String(trimmed.dropFirst(4)) : trimmed
    }

    /// Force a scheme so the stored URL parses. Saved URLs may be bare domains;
    /// `URL(string:)` yields no host for those, which is what
    /// `AutoFillService.updateQuickTypeIdentities` already works around.
    static func normalizedURL(_ site: String) -> String? {
        let trimmed = site.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return trimmed.contains("://") ? trimmed : "https://\(trimmed)"
    }

    /// A password is the one thing that cannot be filled in later — a username
    /// often is, on the screen after the one being filled.
    var isSaveable: Bool {
        !password.isEmpty
    }

    func pendingItem(id: String, now: Int) -> SharedPendingPasswordItem {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedName = trimmedName.isEmpty
            ? Self.defaultName(forHost: site.trimmingCharacters(in: .whitespaces).isEmpty ? nil : site)
            : trimmedName

        return SharedPendingPasswordItem(
            item: SharedPassPasswordItem(
                id: id,
                name: resolvedName,
                username: username.trimmingCharacters(in: .whitespacesAndNewlines),
                password: password,
                urls: Self.normalizedURL(site).map { [$0] } ?? []
            ),
            createdAt: now,
            updatedAt: now
        )
    }
}
```

- [ ] **Step 5: Register and run the test**

```bash
ruby scripts/register_shared_file.rb SharedNewLoginDraft.swift Groo GrooAutoFill GrooTests
xcodebuild test -project Groo.xcodeproj -scheme Groo -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:GrooTests/SharedNewLoginDraftTests
```
Expected: PASS, 12 tests.

- [ ] **Step 6: Commit**

```bash
git add Shared/SharedNewLoginDraft.swift Shared/SharedPassModels.swift GrooTests/Shared/SharedNewLoginDraftTests.swift Groo.xcodeproj/project.pbxproj
git commit -m "feat(pass): model a new-login draft and its pending envelope

SharedPassPasswordItem had no memberwise init (init(from:) in the body
suppresses synthesis) and models no timestamps. Both are needed now that
the extension authors the item."
```

---

### Task 3: The pending-passwords queue

`pending_passkeys.enc` holds unsynced passkey **private keys** — material that
exists nowhere else until the app drains it. This task must not change that
file's format, path, or behaviour. It factors the mechanics into a generic
helper and adds a second file beside it.

**Files:**
- Create: `Shared/SharedPendingQueue.swift`
- Create: `Shared/SharedPendingPasswordsStore.swift`
- Modify: `Shared/SharedPendingItemsStore.swift:33-98` (delegate to the helper)
- Test: `GrooTests/Shared/SharedPendingPasswordsStoreTests.swift`

**Interfaces:**
- Consumes: `SharedPendingPasswordItem` (Task 2)
- Produces:
  - `SharedPendingQueue.load(_:key:fileURL:) throws -> [T]`,
    `.append(_:key:fileURL:) throws`, `.clear(fileURL:)`
  - `SharedPendingPasswordsStore.defaultFileURL`, `.load(key:fileURL:)`,
    `.append(_:key:fileURL:)`, `.clear(fileURL:)` — same shapes as
    `SharedPendingItemsStore`, over `[SharedPendingPasswordItem]`
  - Errors stay `SharedPendingItemsStoreError.containerNotAvailable` /
    `.unreadable(Error)` — one error type for both queues

- [ ] **Step 1: Write the failing test**

Create `GrooTests/Shared/SharedPendingPasswordsStoreTests.swift`:

```swift
//
//  SharedPendingPasswordsStoreTests.swift
//  GrooTests
//
//  Pending-password queue semantics against a temp-directory file. The real
//  App Group file is never touched (explicit fileURL on every call).
//

import CryptoKit
import Foundation
import Testing
@testable import Groo

struct SharedPendingPasswordsStoreTests {
    static func tempDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("pending-passwords-tests-\(UUID().uuidString)", isDirectory: true)
    }

    static func cleanup(_ directory: URL) {
        try? FileManager.default.removeItem(at: directory)
    }

    static func makePending(id: String = "item-1", password: String = "hunter2") -> SharedPendingPasswordItem {
        SharedNewLoginDraft(name: "github.com", username: "me", password: password, site: "github.com")
            .pendingItem(id: id, now: 1_700_000_000_123)
    }

    @Test func missingQueueFileLoadsEmpty() throws {
        let dir = Self.tempDirectory()
        defer { Self.cleanup(dir) }
        let url = dir.appendingPathComponent("pending_passwords.enc")

        #expect(try SharedPendingPasswordsStore.load(key: SymmetricKey(size: .bits256), fileURL: url).isEmpty)
    }

    @Test func appendThenLoadRoundtripsEveryField() throws {
        let dir = Self.tempDirectory()
        defer { Self.cleanup(dir) }
        let url = dir.appendingPathComponent("pending_passwords.enc")
        let key = SymmetricKey(size: .bits256)

        try SharedPendingPasswordsStore.append(Self.makePending(), key: key, fileURL: url)
        let loaded = try SharedPendingPasswordsStore.load(key: key, fileURL: url)

        try #require(loaded.count == 1)
        #expect(loaded[0].item.id == "item-1")
        #expect(loaded[0].item.password == "hunter2")
        #expect(loaded[0].item.urls == ["https://github.com"])
        #expect(loaded[0].createdAt == 1_700_000_000_123)
    }

    @Test func appendAccumulatesInOrder() throws {
        let dir = Self.tempDirectory()
        defer { Self.cleanup(dir) }
        let url = dir.appendingPathComponent("pending_passwords.enc")
        let key = SymmetricKey(size: .bits256)

        try SharedPendingPasswordsStore.append(Self.makePending(id: "item-1"), key: key, fileURL: url)
        try SharedPendingPasswordsStore.append(Self.makePending(id: "item-2"), key: key, fileURL: url)

        #expect(try SharedPendingPasswordsStore.load(key: key, fileURL: url).map(\.item.id) == ["item-1", "item-2"])
    }

    @Test func theFileOnDiskDoesNotContainThePasswordInClear() throws {
        let dir = Self.tempDirectory()
        defer { Self.cleanup(dir) }
        let url = dir.appendingPathComponent("pending_passwords.enc")

        try SharedPendingPasswordsStore.append(
            Self.makePending(password: "correct-horse-battery-staple"),
            key: SymmetricKey(size: .bits256),
            fileURL: url
        )

        let raw = try Data(contentsOf: url)
        #expect(raw.range(of: Data("correct-horse-battery-staple".utf8)) == nil)
    }

    @Test func wrongKeyThrowsUnreadableNeverEmpty() throws {
        let dir = Self.tempDirectory()
        defer { Self.cleanup(dir) }
        let url = dir.appendingPathComponent("pending_passwords.enc")
        try SharedPendingPasswordsStore.append(Self.makePending(), key: SymmetricKey(size: .bits256), fileURL: url)

        #expect {
            _ = try SharedPendingPasswordsStore.load(key: SymmetricKey(size: .bits256), fileURL: url)
        } throws: { error in
            guard case SharedPendingItemsStoreError.unreadable = error else { return false }
            return true
        }
    }

    @Test func anUnreadableQueueIsMovedAsideNotOverwritten() throws {
        let dir = Self.tempDirectory()
        defer { Self.cleanup(dir) }
        let url = dir.appendingPathComponent("pending_passwords.enc")
        try SharedPendingPasswordsStore.append(Self.makePending(), key: SymmetricKey(size: .bits256), fileURL: url)
        let originalBytes = try Data(contentsOf: url)

        // A different key: the existing file cannot be read, but it must not be
        // destroyed — it may hold the only copy of a password.
        try SharedPendingPasswordsStore.append(Self.makePending(id: "item-2"), key: SymmetricKey(size: .bits256), fileURL: url)

        let backup = url.appendingPathExtension("corrupt")
        #expect(FileManager.default.fileExists(atPath: backup.path))
        #expect(try Data(contentsOf: backup) == originalBytes)
    }

    @Test func clearRemovesTheQueue() throws {
        let dir = Self.tempDirectory()
        defer { Self.cleanup(dir) }
        let url = dir.appendingPathComponent("pending_passwords.enc")
        let key = SymmetricKey(size: .bits256)
        try SharedPendingPasswordsStore.append(Self.makePending(), key: key, fileURL: url)

        SharedPendingPasswordsStore.clear(fileURL: url)

        #expect(try SharedPendingPasswordsStore.load(key: key, fileURL: url).isEmpty)
    }

    /// The guard that matters: the passkey queue holds private keys that exist
    /// nowhere else. Nothing the password queue does may touch it.
    @Test func passwordQueueOperationsLeaveThePasskeyQueueByteIdentical() throws {
        let dir = Self.tempDirectory()
        defer { Self.cleanup(dir) }
        let key = SymmetricKey(size: .bits256)
        let passkeyURL = dir.appendingPathComponent("pending_passkeys.enc")
        let passwordURL = dir.appendingPathComponent("pending_passwords.enc")

        try SharedPendingItemsStore.append(
            SharedPendingItemsStoreTests.makePasskey(), key: key, fileURL: passkeyURL
        )
        let before = try Data(contentsOf: passkeyURL)

        try SharedPendingPasswordsStore.append(Self.makePending(), key: key, fileURL: passwordURL)
        SharedPendingPasswordsStore.clear(fileURL: passwordURL)

        #expect(try Data(contentsOf: passkeyURL) == before)
        #expect(try SharedPendingItemsStore.load(key: key, fileURL: passkeyURL).count == 1)
    }

    /// The two queues must not share a default path, or one would silently
    /// destroy the other in production.
    @Test func theTwoQueuesUseDifferentDefaultFiles() {
        #expect(SharedPendingPasswordsStore.defaultFileURL != SharedPendingItemsStore.defaultFileURL)
        #expect(SharedPendingPasswordsStore.defaultFileURL?.lastPathComponent == "pending_passwords.enc")
    }
}
```

- [ ] **Step 2: Run the test and watch it fail**

Run: `xcodebuild test -project Groo.xcodeproj -scheme Groo -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:GrooTests/SharedPendingPasswordsStoreTests`
Expected: build failure — `cannot find 'SharedPendingPasswordsStore' in scope`.

- [ ] **Step 3: Write the generic queue**

Create `Shared/SharedPendingQueue.swift`:

```swift
//
//  SharedPendingQueue.swift
//  Groo
//
//  Encrypted append-only queue in the App Group container, shared by the
//  pending-passkey and pending-password stores.
//
//  Extracted rather than copied so the "never overwrite an unreadable queue"
//  rule has exactly one implementation. That rule protects material — passkey
//  private keys, and now passwords — that exists nowhere else until the main
//  app drains it.
//

import CryptoKit
import Foundation
import os

enum SharedPendingQueue {
    /// Load the queue. Returns [] only when no file exists.
    /// Throws `.unreadable` when the file exists but cannot be decrypted or
    /// decoded — callers must NOT treat that as an empty queue.
    static func load<T: Decodable>(
        _ type: T.Type,
        key: SymmetricKey,
        fileURL: URL?
    ) throws -> [T] {
        guard let url = fileURL else {
            throw SharedPendingItemsStoreError.containerNotAvailable
        }
        guard FileManager.default.fileExists(atPath: url.path) else {
            return []
        }

        do {
            let combined = try Data(contentsOf: url)
            let sealedBox = try AES.GCM.SealedBox(combined: combined)
            let decrypted = try AES.GCM.open(sealedBox, using: key)
            return try JSONDecoder().decode([T].self, from: decrypted)
        } catch {
            Log.autofill.error(
                "Pending queue \(url.lastPathComponent, privacy: .public) exists but is unreadable: \(String(describing: error), privacy: .public)"
            )
            throw SharedPendingItemsStoreError.unreadable(error)
        }
    }

    static func append<T: Codable>(
        _ item: T,
        key: SymmetricKey,
        fileURL: URL?
    ) throws {
        guard let url = fileURL else {
            throw SharedPendingItemsStoreError.containerNotAvailable
        }

        var items: [T]
        do {
            items = try load(T.self, key: key, fileURL: url)
        } catch SharedPendingItemsStoreError.unreadable {
            // Never overwrite an unreadable queue — it may hold the only copy
            // of a credential. Move it aside so it stays recoverable on disk.
            let backup = url.appendingPathExtension("corrupt")
            try? FileManager.default.removeItem(at: backup)
            try FileManager.default.moveItem(at: url, to: backup)
            Log.autofill.fault(
                "Moved unreadable pending queue aside to \(backup.lastPathComponent, privacy: .public)"
            )
            items = []
        }
        items.append(item)

        let data = try JSONEncoder().encode(items)
        let sealed = try AES.GCM.seal(data, using: key)
        guard let combined = sealed.combined else {
            throw SharedCryptoError.decryptionFailed
        }

        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try combined.write(to: url, options: .atomic)
    }

    static func clear(fileURL: URL?) {
        guard let url = fileURL, FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            Log.autofill.error(
                "Failed to clear pending queue \(url.lastPathComponent, privacy: .public): \(String(describing: error), privacy: .public)"
            )
        }
    }
}
```

- [ ] **Step 4: Write the passwords store**

Create `Shared/SharedPendingPasswordsStore.swift`:

```swift
//
//  SharedPendingPasswordsStore.swift
//  Groo
//
//  Queue for logins created in the AutoFill extension, encrypted with the
//  vault key until the main app merges them into the vault and syncs.
//
//  A separate file from `pending_passkeys.enc` on purpose: that file holds
//  unsynced passkey private keys, and no format change to it is worth the risk
//  of losing them.
//

import CryptoKit
import Foundation

enum SharedPendingPasswordsStore {
    /// Production queue location inside the App Group container. Tests pass an
    /// explicit temp-directory URL instead of touching this file.
    static var defaultFileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: SharedConfig.appGroupIdentifier)?
            .appendingPathComponent("pass", isDirectory: true)
            .appendingPathComponent("pending_passwords.enc")
    }

    static func load(
        key: SymmetricKey,
        fileURL: URL? = SharedPendingPasswordsStore.defaultFileURL
    ) throws -> [SharedPendingPasswordItem] {
        try SharedPendingQueue.load(SharedPendingPasswordItem.self, key: key, fileURL: fileURL)
    }

    static func append(
        _ item: SharedPendingPasswordItem,
        key: SymmetricKey,
        fileURL: URL? = SharedPendingPasswordsStore.defaultFileURL
    ) throws {
        try SharedPendingQueue.append(item, key: key, fileURL: fileURL)
    }

    static func clear(fileURL: URL? = SharedPendingPasswordsStore.defaultFileURL) {
        SharedPendingQueue.clear(fileURL: fileURL)
    }
}
```

- [ ] **Step 5: Delegate the passkey store to the same helper**

In `Shared/SharedPendingItemsStore.swift`, replace the bodies of `load`,
`append` and `clear` (currently `:33-98`) with delegations, leaving the
`defaultFileURL`, the signatures, the doc comments and
`SharedPendingItemsStoreError` exactly as they are:

```swift
    static func load(
        key: SymmetricKey,
        fileURL: URL? = SharedPendingItemsStore.defaultFileURL
    ) throws -> [SharedPassPasskeyItem] {
        try SharedPendingQueue.load(SharedPassPasskeyItem.self, key: key, fileURL: fileURL)
    }

    static func append(
        _ item: SharedPassPasskeyItem,
        key: SymmetricKey,
        fileURL: URL? = SharedPendingItemsStore.defaultFileURL
    ) throws {
        try SharedPendingQueue.append(item, key: key, fileURL: fileURL)
    }

    static func clear(fileURL: URL? = SharedPendingItemsStore.defaultFileURL) {
        SharedPendingQueue.clear(fileURL: fileURL)
    }
```

- [ ] **Step 6: Make `SharedPendingItemsStoreTests.makePasskey` reachable**

The new suite calls `SharedPendingItemsStoreTests.makePasskey()`. It is already
`static` (`GrooTests/Shared/SharedPendingItemsStoreTests.swift:27`) and both
suites are internal to the same test target, so no change should be needed. If
the build reports it as inaccessible, add `internal` explicitly rather than
duplicating the fixture.

- [ ] **Step 7: Register both files and run both suites**

```bash
ruby scripts/register_shared_file.rb SharedPendingQueue.swift Groo GrooAutoFill GrooTests
ruby scripts/register_shared_file.rb SharedPendingPasswordsStore.swift Groo GrooAutoFill GrooTests
xcodebuild test -project Groo.xcodeproj -scheme Groo -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:GrooTests/SharedPendingPasswordsStoreTests \
  -only-testing:GrooTests/SharedPendingItemsStoreTests
```
Expected: PASS. **The existing `SharedPendingItemsStoreTests` must pass
unchanged** — that suite is the regression guard on the refactor. If any of its
tests need editing to pass, the refactor changed behaviour: revert and redo it.

- [ ] **Step 8: Commit**

```bash
git add Shared/SharedPendingQueue.swift Shared/SharedPendingPasswordsStore.swift Shared/SharedPendingItemsStore.swift GrooTests/Shared/SharedPendingPasswordsStoreTests.swift Groo.xcodeproj/project.pbxproj
git commit -m "feat(pass): add an encrypted pending queue for new logins

A second file beside pending_passkeys.enc rather than a widened one:
that file holds unsynced private keys and no migration on it is worth
the risk. Mechanics factored out so the never-overwrite rule has one
implementation."
```

---

### Task 4: The password publisher

Mirrors `Shared/PasskeyPublisher.swift`. The record id is brand new, so there
is no version to guess, no 409 path and no retry.

**Files:**
- Create: `Shared/PasswordPublisher.swift`
- Modify: `Shared/SharedConfig.swift` (add `passwordPushDeadlineSeconds` after `:52`)
- Test: `GrooTests/Shared/PasswordPublisherTests.swift`

**Interfaces:**
- Consumes: `SharedPendingPasswordItem` (Task 2), `SharedRecordCrypto.encryptRecord`,
  `SharedRecordWriteRequest`, `SharedRecordWriteResponse`, `PassAPIClient`
- Produces:
  - `protocol PasswordRecordPushing: Sendable { func createRecord(_:) async throws -> SharedRecordWriteResponse; func formatVersion() async throws -> Int }`
  - `enum PasswordPublishOutcome: Equatable { case published; case queued(reason: String) }`
  - `struct PasswordPublisher { let pusher; let vaultKey; func payload(for:) throws -> Data; func publish(_:) async -> PasswordPublishOutcome }`
  - `struct APIPasswordPusher: PasswordRecordPushing { let api: PassAPIClient }`
  - `SharedConfig.passwordPushDeadlineSeconds -> Double`

- [ ] **Step 1: Write the failing test**

Create `GrooTests/Shared/PasswordPublisherTests.swift`:

```swift
//
//  PasswordPublisherTests.swift
//  GrooTests
//

import CryptoKit
import Foundation
import Testing
@testable import Groo

struct PasswordPublisherTests {

    final class SpyPusher: PasswordRecordPushing, @unchecked Sendable {
        var format = 2
        var formatError: (any Error)?
        var createError: (any Error)?
        var created: [SharedRecordWriteRequest] = []

        func formatVersion() async throws -> Int {
            if let formatError { throw formatError }
            return format
        }

        func createRecord(_ request: SharedRecordWriteRequest) async throws -> SharedRecordWriteResponse {
            if let createError { throw createError }
            created.append(request)
            return SharedRecordWriteResponse(id: request.id, seq: 42, version: 1)
        }
    }

    struct Boom: Error {}

    static func pending(id: String = "item-1") -> SharedPendingPasswordItem {
        SharedNewLoginDraft(name: "github.com", username: "me", password: "hunter2", site: "github.com")
            .pendingItem(id: id, now: 1_700_000_000_123)
    }

    private func makePublisher(pusher: SpyPusher = SpyPusher()) -> (PasswordPublisher, SpyPusher, SymmetricKey) {
        let key = SymmetricKey(size: .bits256)
        return (PasswordPublisher(pusher: pusher, vaultKey: key), pusher, key)
    }

    // The guard that caught the equivalent passkey bug: the payload must decode
    // as the app's REAL model, not the lossy Shared one it came from.
    @Test("payload decodes as PassPasswordItem, the shape every client expects")
    func payloadMatchesTheAppModel() throws {
        let (publisher, _, _) = makePublisher()

        let data = try publisher.payload(for: Self.pending())
        let decoded = try JSONDecoder().decode(PassPasswordItem.self, from: data)

        #expect(decoded.id == "item-1")
        #expect(decoded.type == .password)
        #expect(decoded.name == "github.com")
        #expect(decoded.username == "me")
        #expect(decoded.password == "hunter2")
        #expect(decoded.urls == ["https://github.com"])
        #expect(decoded.createdAt == 1_700_000_000_123)
        #expect(decoded.updatedAt == 1_700_000_000_123)
    }

    @Test("payload timestamps come from the envelope, not from the clock")
    func payloadUsesTheEnvelopeTimestamps() throws {
        let (publisher, _, _) = makePublisher()

        let object = try JSONSerialization.jsonObject(
            with: try publisher.payload(for: Self.pending())
        ) as? [String: Any]

        // Re-stamping here would make the app's drained copy differ from the
        // pushed record and rewrite a record that was already correct.
        #expect(object?["createdAt"] as? Int == 1_700_000_000_123)
        #expect(object?["updatedAt"] as? Int == 1_700_000_000_123)
    }

    @Test("payload omits absent optionals rather than sending null")
    func payloadOmitsAbsentOptionals() throws {
        let (publisher, _, _) = makePublisher()

        let object = try JSONSerialization.jsonObject(
            with: try publisher.payload(for: Self.pending())
        ) as? [String: Any]

        #expect(object?.keys.sorted() == [
            "createdAt", "id", "name", "password", "type", "updatedAt", "urls", "username",
        ])
    }

    @Test("the pushed record decrypts to something PassPasswordItem can decode")
    func pushedRecordIsDecodableEndToEnd() async throws {
        let (publisher, pusher, key) = makePublisher()

        _ = await publisher.publish(Self.pending())

        let sent = try #require(pusher.created.first)
        let decoded = try SharedRecordCrypto.decryptRecord(
            encryptedData: sent.encryptedData, iv: sent.iv,
            wrappedRecordKey: sent.wrappedRecordKey, wrapIv: sent.wrapIv,
            vaultKey: key
        )
        #expect(decoded.kind == .item)
        let item = try JSONDecoder().decode(PassPasswordItem.self, from: decoded.data)
        #expect(item.password == "hunter2")
    }

    @Test("a format-1 vault leaves the login queued and pushes nothing")
    func formatOneIsNotPushed() async throws {
        let pusher = SpyPusher()
        pusher.format = 1
        let (publisher, _, _) = makePublisher(pusher: pusher)

        let outcome = await publisher.publish(Self.pending())

        #expect(outcome == .queued(reason: "format 1"))
        #expect(pusher.created.isEmpty)
    }

    @Test("a failing push leaves the login queued and never throws")
    func pushFailureIsQueuedNotThrown() async throws {
        let pusher = SpyPusher()
        pusher.createError = Boom()
        let (publisher, _, _) = makePublisher(pusher: pusher)

        let outcome = await publisher.publish(Self.pending())

        guard case .queued = outcome else {
            Issue.record("expected .queued, got \(outcome)")
            return
        }
    }

    @Test("a failing format probe leaves the login queued and never throws")
    func formatProbeFailureIsQueued() async throws {
        let pusher = SpyPusher()
        pusher.formatError = Boom()
        let (publisher, _, _) = makePublisher(pusher: pusher)

        let outcome = await publisher.publish(Self.pending())

        guard case .queued = outcome else {
            Issue.record("expected .queued, got \(outcome)")
            return
        }
        #expect(pusher.created.isEmpty)
    }

    @Test("a successful push reports published")
    func successReportsPublished() async throws {
        let (publisher, pusher, _) = makePublisher()

        #expect(await publisher.publish(Self.pending()) == .published)
        #expect(pusher.created.count == 1)
    }
}
```

- [ ] **Step 2: Run the test and watch it fail**

Run: `xcodebuild test -project Groo.xcodeproj -scheme Groo -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:GrooTests/PasswordPublisherTests`
Expected: build failure — `cannot find 'PasswordPublisher' in scope`.

- [ ] **Step 3: Add the deadline to `SharedConfig`**

In `Shared/SharedConfig.swift`, directly after the closing brace of
`passkeyPushDeadlineSeconds` (currently `:52`), add:

```swift
    /// Total budget for the AutoFill new-login push.
    ///
    /// `completeRequest` tears the extension process down, so the push has to
    /// finish before the field is filled — this is how long the user waits at
    /// worst. Same default and override mechanism as the passkey deadline.
    static var passwordPushDeadlineSeconds: Double {
        let defaults = UserDefaults(suiteName: appGroupIdentifier) ?? .standard
        let override = defaults.double(forKey: "passwordPushDeadlineSeconds")
        return override > 0 ? override : 5
    }
```

- [ ] **Step 4: Write the publisher**

Create `Shared/PasswordPublisher.swift`:

```swift
//
//  PasswordPublisher.swift
//  Groo
//
//  Pushes a login created in the AutoFill sheet to the server as one new
//  per-item record.
//
//  Lives in Shared/ rather than GrooAutoFill/ because GrooTests cannot compile
//  extension-target sources. Mirrors PasskeyPublisher deliberately.
//

import CryptoKit
import Foundation
import os

/// Seam so the publisher is testable without a network or an App Group.
protocol PasswordRecordPushing: Sendable {
    func createRecord(_ request: SharedRecordWriteRequest) async throws -> SharedRecordWriteResponse
    func formatVersion() async throws -> Int
}

enum PasswordPublishOutcome: Equatable {
    /// Pushed to the server. Still queued until the app merges it.
    case published
    /// Left queued for the app to drain. Never an error the user sees.
    case queued(reason: String)
}

/// Publishes one login as a single record.
///
/// The record id is brand new, so no conflict is possible: no version to guess,
/// no 409 path, no retry, and no base vault to fetch first.
struct PasswordPublisher {
    let pusher: any PasswordRecordPushing
    let vaultKey: SymmetricKey

    /// Build the record payload.
    ///
    /// Built by hand rather than encoded from `SharedPassPasswordItem`: that
    /// model carries no `createdAt`/`updatedAt`, both of which
    /// `PassPasswordItem.init(from:)` decodes non-optionally and the web
    /// `BaseItem` declares. Encoding the model directly produces a record every
    /// real client fails to decode. Timestamps come from the envelope so the
    /// app's later drain reproduces this payload byte for byte.
    func payload(for pending: SharedPendingPasswordItem) throws -> Data {
        let item = pending.item
        var object: [String: Any] = [
            "id": item.id,
            // The stored discriminator other clients switch on.
            "type": "password",
            "name": item.name,
            "username": item.username,
            "password": item.password,
            "urls": item.urls,
            "createdAt": pending.createdAt,
            "updatedAt": pending.updatedAt,
        ]
        // Optional fields are omitted rather than sent null, matching how the
        // web app encodes an item that has none. `notes`, `totp`, `folderId`
        // and `favorite` are never set by this flow.
        if let deletedAt = item.deletedAt { object["deletedAt"] = deletedAt }
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    /// Push the login to the server.
    ///
    /// Never throws: the sheet must fill the field regardless. Every failure
    /// path leaves the login queued for the app-side drain and is logged.
    func publish(_ pending: SharedPendingPasswordItem) async -> PasswordPublishOutcome {
        do {
            // At format 1 the blob is authoritative and app-owned, so there is
            // nothing safe for the extension to write.
            let format = try await pusher.formatVersion()
            guard format == 2 else {
                Log.autofill.info("Vault is not on per-item records; leaving login queued")
                return .queued(reason: "format \(format)")
            }

            let request = try SharedRecordCrypto.encryptRecord(
                id: pending.item.id, kind: .item, payload: try payload(for: pending), vaultKey: vaultKey
            )

            _ = try await pusher.createRecord(request)

            // Deliberately NOT removed from the pending queue. The queue means
            // "not yet in the cache the extension reads", and only the main app
            // refreshes that cache — so the app clears it, after merging AND
            // refreshing. Its merge dedupes on item id, so an item already
            // pushed here is skipped rather than duplicated.
            Log.autofill.info("Pushed login \(pending.item.id, privacy: .public) to the server")
            return .published
        } catch {
            Log.autofill.error(
                "Login push failed, leaving it queued: \(String(describing: error), privacy: .public)"
            )
            return .queued(reason: String(describing: error))
        }
    }
}

// MARK: - Concrete adapters

/// Backs `PasswordRecordPushing` with the real Pass API.
struct APIPasswordPusher: PasswordRecordPushing {
    let api: PassAPIClient

    func formatVersion() async throws -> Int {
        let probe: SharedFormatProbe = try await api.get(PassAPIClient.Endpoint.keyInfo)
        return probe.formatVersion ?? 1
    }

    func createRecord(_ request: SharedRecordWriteRequest) async throws -> SharedRecordWriteResponse {
        try await api.post(PassAPIClient.Endpoint.records, body: request)
    }
}
```

- [ ] **Step 5: Register and run**

```bash
ruby scripts/register_shared_file.rb PasswordPublisher.swift Groo GrooAutoFill GrooTests
xcodebuild test -project Groo.xcodeproj -scheme Groo -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:GrooTests/PasswordPublisherTests
```
Expected: PASS, 8 tests.

- [ ] **Step 6: Commit**

```bash
git add Shared/PasswordPublisher.swift Shared/SharedConfig.swift GrooTests/Shared/PasswordPublisherTests.swift Groo.xcodeproj/project.pbxproj
git commit -m "feat(pass): publish a new login as one per-item record

Payload built by hand: SharedPassPasswordItem models no timestamps, and
every other client requires them. Never throws — a failed push leaves
the login queued."
```

---

### Task 5: Merge pending logins into what the sheet reads

Without this, a login created in the sheet vanishes from the next sheet until
the main app has run — the same defect that made a freshly registered passkey
unresolvable and produced `credentialIdentityNotFound`.

**Files:**
- Modify: `Shared/SharedCredentialMatcher.swift:103-109` (add a sibling below)
- Test: `GrooTests/Shared/SharedCredentialMatcherTests.swift` (append)

**Interfaces:**
- Consumes: `SharedPendingPasswordItem` (Task 2)
- Produces: `SharedCredentialMatcher.mergingPendingPasswords(vault:pending:) -> [SharedPassPasswordItem]`

- [ ] **Step 1: Write the failing test**

Append to `GrooTests/Shared/SharedCredentialMatcherTests.swift`, inside the
existing suite:

```swift
    // MARK: - Pending passwords

    private static func pendingPassword(id: String, name: String = "github.com") -> SharedPendingPasswordItem {
        SharedNewLoginDraft(name: name, username: "me", password: "hunter2", site: "github.com")
            .pendingItem(id: id, now: 1)
    }

    private static func vaultPassword(id: String) -> SharedPassPasswordItem {
        SharedPassPasswordItem(
            id: id, name: "github.com", username: "me", password: "hunter2",
            urls: ["https://github.com"]
        )
    }

    @Test func aPendingLoginNotYetInTheVaultIsAppended() {
        let merged = SharedCredentialMatcher.mergingPendingPasswords(
            vault: [Self.vaultPassword(id: "known")],
            pending: [Self.pendingPassword(id: "fresh")]
        )

        #expect(merged.map(\.id) == ["known", "fresh"])
    }

    @Test func aPendingLoginAlreadySyncedIsNotDuplicated() {
        // The push succeeded and the record came back down. The queue still
        // holds it, because only the app clears the queue.
        let merged = SharedCredentialMatcher.mergingPendingPasswords(
            vault: [Self.vaultPassword(id: "known")],
            pending: [Self.pendingPassword(id: "known")]
        )

        #expect(merged.map(\.id) == ["known"])
    }

    @Test func dedupeIsByIdNotByNameOrUsername() {
        // Two logins for the same site with the same username are legitimate.
        let merged = SharedCredentialMatcher.mergingPendingPasswords(
            vault: [Self.vaultPassword(id: "first")],
            pending: [Self.pendingPassword(id: "second")]
        )

        #expect(merged.count == 2)
    }

    @Test func anEmptyQueueChangesNothing() {
        let vault = [Self.vaultPassword(id: "known")]
        #expect(SharedCredentialMatcher.mergingPendingPasswords(vault: vault, pending: []).map(\.id) == ["known"])
    }
```

- [ ] **Step 2: Run the test and watch it fail**

Run: `xcodebuild test -project Groo.xcodeproj -scheme Groo -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:GrooTests/SharedCredentialMatcherTests`
Expected: build failure — no `mergingPendingPasswords`.

- [ ] **Step 3: Implement**

In `Shared/SharedCredentialMatcher.swift`, after `mergingPendingPasskeys`
(`:103-109`), add:

```swift
    /// Fold in logins created in the AutoFill sheet but not yet merged into the
    /// vault by the main app.
    ///
    /// Dedupe is by item id — the extension authors the id and the pushed
    /// record keeps it. Name or username would be wrong: two logins for the
    /// same site with the same username are legitimate.
    static func mergingPendingPasswords(
        vault: [SharedPassPasswordItem],
        pending: [SharedPendingPasswordItem]
    ) -> [SharedPassPasswordItem] {
        let knownIds = Set(vault.map(\.id))
        return vault + pending.map(\.item).filter { !knownIds.contains($0.id) }
    }
```

- [ ] **Step 4: Run the test and watch it pass**

Run: `xcodebuild test -project Groo.xcodeproj -scheme Groo -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:GrooTests/SharedCredentialMatcherTests`
Expected: PASS, including every pre-existing test in the suite.

- [ ] **Step 5: Commit**

```bash
git add Shared/SharedCredentialMatcher.swift GrooTests/Shared/SharedCredentialMatcherTests.swift
git commit -m "feat(pass): merge pending logins into the AutoFill credential list"
```

---

### Task 6: `AutoFillService.createPassword`

**Files:**
- Modify: `GrooAutoFill/AutoFillService.swift` — `loadCredentials()` (`:96-165`),
  `performRefresh(using:)` (`:224-268`), and a new section after
  `publishPasskey` (`:333`)
- Test: none directly — the extension target is not compilable into the test
  bundle. Every piece of logic this method composes is covered by Tasks 1-5;
  the composition is verified in Task 10's device run.

**Interfaces:**
- Consumes: `SharedNewLoginDraft`, `SharedPendingPasswordItem`,
  `SharedPendingPasswordsStore`, `PasswordPublisher`, `APIPasswordPusher`,
  `SharedCredentialMatcher.mergingPendingPasswords`,
  `SharedConfig.passwordPushDeadlineSeconds`
- Produces: `AutoFillService.createPassword(_ draft:) async throws -> SharedPassPasswordItem`,
  `AutoFillService.withPendingPasswords(_:key:) -> [SharedPassPasswordItem]`

- [ ] **Step 1: Add the pending-password read merge**

In `GrooAutoFill/AutoFillService.swift`, beside the existing
`withPendingPasskeys` (`:167`), add:

```swift
    /// Fold in logins created here but not yet merged into the vault by the
    /// main app. A queue that cannot be read must not fail the whole unlock.
    static func withPendingPasswords(
        _ passwords: [SharedPassPasswordItem],
        key: SymmetricKey
    ) -> [SharedPassPasswordItem] {
        do {
            let pending = try SharedPendingPasswordsStore.load(key: key)
            return SharedCredentialMatcher.mergingPendingPasswords(vault: passwords, pending: pending)
        } catch {
            Log.autofill.error(
                "Skipping pending logins: \(String(describing: error), privacy: .public)"
            )
            return passwords
        }
    }
```

- [ ] **Step 2: Apply it at all three read sites**

In `loadCredentials()`, the records branch (`:108-111`) becomes:

```swift
            let decoded = SharedRecordDecoder.decodeItems(cached.records, key: key)
            credentials = Self.withPendingPasswords(decoded.passwords, key: key)
            passkeys = Self.withPendingPasskeys(decoded.passkeys, key: key)
            return
```

At the end of the blob branch, the line `passkeys = Self.withPendingPasskeys(passkeys, key: key)`
(`:162`) gains a sibling directly above it:

```swift
        credentials = Self.withPendingPasswords(credentials, key: key)
        passkeys = Self.withPendingPasskeys(passkeys, key: key)
```

In `performRefresh(using:)` (`:250-257`), the decode block becomes:

```swift
        let decoded = SharedRecordDecoder.decodeItems(cached.records, key: key)
        let mergedPasswords = Self.withPendingPasswords(decoded.passwords, key: key)
        let mergedPasskeys = Self.withPendingPasskeys(decoded.passkeys, key: key)

        await MainActor.run {
            self.credentials = mergedPasswords
            self.passkeys = mergedPasskeys
        }

        await updateQuickTypeIdentities(passwords: mergedPasswords, passkeys: mergedPasskeys)
```

- [ ] **Step 3: Write `createPassword`**

After `publishPasskey(_:)` (ends `:361`), add:

```swift
    // MARK: - Creating a login from the sheet

    /// Save a login created in the sheet and return it for filling.
    ///
    /// Order matters. The queue write comes first because it is the only
    /// durability that does not depend on the network; the push is awaited
    /// because `completeRequest` tears this process down and would kill it
    /// mid-flight. Only the queue write can fail the save.
    func createPassword(_ draft: SharedNewLoginDraft) async throws -> SharedPassPasswordItem {
        guard let key = encryptionKey else {
            throw AutoFillError.vaultLocked
        }

        let pending = draft.pendingItem(
            id: UUID().uuidString.lowercased(),
            now: Int(Date().timeIntervalSince1970 * 1000)
        )

        // 1. Durable locally, before anything else can fail.
        try SharedPendingPasswordsStore.append(pending, key: key)
        credentials.append(pending.item)

        // 2. Best effort, bounded. A failure leaves it queued for the app.
        await publishPassword(pending)

        // 3. Offer it in QuickType without waiting for the app to run.
        await saveQuickTypeIdentity(for: pending.item)

        return pending.item
    }

    /// Push a freshly created login, bounded by a deadline. Never throws.
    private func publishPassword(_ pending: SharedPendingPasswordItem) async {
        guard let key = encryptionKey else {
            Log.autofill.error("Cannot push login: vault is locked")
            return
        }

        let session = GrooAuthFactory.makeTokenOnlySession()
        let api = PassAPIClient(
            tokenProvider: { try await session.accessToken() },
            // No force-refresh: one attempt only. Combined with the deadline
            // this makes a late refresh replay — which would revoke the token
            // family and sign the user out everywhere — structurally impossible.
            forceRefresh: { throw APIError.unauthorized }
        )

        let publisher = PasswordPublisher(pusher: APIPasswordPusher(api: api), vaultKey: key)

        let push = Task { await publisher.publish(pending) }
        let deadline = Task {
            try? await Task.sleep(for: .seconds(SharedConfig.passwordPushDeadlineSeconds))
            push.cancel()
        }
        let outcome = await push.value
        deadline.cancel()

        if case .queued(let reason) = outcome {
            Log.autofill.error("Login left queued: \(reason, privacy: .public)")
        }
    }

    /// Add one QuickType suggestion. Additive, not a replace: the full set is
    /// only known after a successful refresh.
    private func saveQuickTypeIdentity(for item: SharedPassPasswordItem) async {
        let store = ASCredentialIdentityStore.shared
        guard await store.state().isEnabled else { return }

        let identities: [ASPasswordCredentialIdentity] = item.urls.compactMap { urlString in
            let normalized = urlString.hasPrefix("http") ? urlString : "https://\(urlString)"
            guard let host = URL(string: normalized)?.host else { return nil }
            return ASPasswordCredentialIdentity(
                serviceIdentifier: ASCredentialServiceIdentifier(identifier: host, type: .domain),
                user: item.username,
                recordIdentifier: item.id
            )
        }
        guard !identities.isEmpty else { return }

        do {
            try await store.saveCredentialIdentities(identities)
        } catch {
            // QuickType drifts from the vault when this fails, but the item is
            // saved and the sheet shows it — so log rather than surface.
            Log.autofill.error(
                "Failed to add QuickType identity: \(String(describing: error), privacy: .public)"
            )
        }
    }
```

- [ ] **Step 4: Build the extension target**

Run: `xcodebuild -project Groo.xcodeproj -scheme Groo -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build`
Expected: BUILD SUCCEEDED.

- [ ] **Step 5: Run the full unit suite**

Run: `scripts/test.sh --unit`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add GrooAutoFill/AutoFillService.swift
git commit -m "feat(autofill): save a new login from the extension

Queue first, then a deadline-bounded push, then QuickType. Only the
queue write can fail the save — everything after it is best effort."
```

---

### Task 7: The form and its entry points

**Files:**
- Create: `GrooAutoFill/NewLoginView.swift`
- Modify: `GrooAutoFill/AutoFillCredentialListView.swift` (properties `:11-20`,
  toolbar `:106-113`, empty state `:225-232`)
- Modify: `GrooAutoFill/CredentialProviderViewController.swift`
  (`:143-160`, `:176-200`, `:218-227`)
- Test: manual (Task 10) — extension UI is not testable from `GrooTests`

**Interfaces:**
- Consumes: `AutoFillService.createPassword`, `SharedNewLoginDraft`,
  `SharedPasswordGenerator`
- Produces: `NewLoginView(service:site:onSaved:onCancel:)`;
  `AutoFillCredentialListView.allowsCreatingPassword: Bool`;
  `AutoFillCredentialListView.onCreated: (SharedPassPasswordItem) -> Void`

- [ ] **Step 1: Write the form**

Create `GrooAutoFill/NewLoginView.swift`:

```swift
//
//  NewLoginView.swift
//  GrooAutoFill
//
//  Create a login without leaving the sign-up flow. iOS never offers a
//  third-party provider its own save prompt — the only place a provider can
//  offer creation is inside its own sheet.
//

import SwiftUI

struct NewLoginView: View {
    @ObservedObject var service: AutoFillService
    /// Host of the site being filled, used to prefill the form.
    let site: String?
    let onSaved: (SharedPassPasswordItem) -> Void
    let onCancel: () -> Void

    @State private var draft: SharedNewLoginDraft
    @State private var revealPassword = false
    @State private var isSaving = false
    @State private var saveError: String?
    @FocusState private var usernameFocused: Bool

    init(
        service: AutoFillService,
        site: String?,
        onSaved: @escaping (SharedPassPasswordItem) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.service = service
        self.site = site
        self.onSaved = onSaved
        self.onCancel = onCancel
        _draft = State(initialValue: SharedNewLoginDraft(
            name: SharedNewLoginDraft.defaultName(forHost: site),
            site: site ?? ""
        ))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Login") {
                    TextField("Name", text: $draft.name)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    TextField("Username or email", text: $draft.username)
                        .textContentType(.username)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($usernameFocused)

                    passwordField
                }

                Section("Website") {
                    TextField("Website", text: $draft.site)
                        .textContentType(.URL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                if let saveError {
                    Section {
                        Text(saveError)
                            .foregroundStyle(.red)
                            .font(.footnote)
                    }
                }
            }
            .navigationTitle("New Login")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel", action: onCancel)
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Save", action: save)
                            .disabled(!draft.isSaveable)
                    }
                }
            }
            .onAppear { usernameFocused = true }
        }
    }

    @ViewBuilder
    private var passwordField: some View {
        HStack {
            Group {
                if revealPassword {
                    TextField("Password", text: $draft.password)
                } else {
                    SecureField("Password", text: $draft.password)
                }
            }
            .textContentType(.newPassword)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()

            Button {
                revealPassword.toggle()
            } label: {
                Image(systemName: revealPassword ? "eye.slash" : "eye")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel(revealPassword ? "Hide password" : "Show password")
        }

        Button {
            draft.password = SharedPasswordGenerator.generate(SharedPasswordGeneratorOptions())
            revealPassword = true
        } label: {
            Label("Generate Password", systemImage: "wand.and.stars")
        }
    }

    private func save() {
        isSaving = true
        saveError = nil
        Task {
            do {
                let item = try await service.createPassword(draft)
                onSaved(item)
            } catch {
                // The one failure the user must see: without the queue write
                // there is no durability at all, so nothing may be filled.
                isSaving = false
                saveError = "Couldn't save this login. \(error.localizedDescription)"
            }
        }
    }
}
```

- [ ] **Step 2: Add the entry points to the list view**

In `GrooAutoFill/AutoFillCredentialListView.swift`, add two properties beside
the existing ones (`:11-20`):

```swift
    /// Whether this presentation can be answered with a password credential.
    /// Set explicitly by the controller per entry point — never inferred.
    var allowsCreatingPassword = false
    var onCreated: ((SharedPassPasswordItem) -> Void)? = nil
```

Add the sheet state beside `@State private var searchText = ""`:

```swift
    @State private var showingNewLogin = false
```

Extend the toolbar (`:106-113`) so it reads:

```swift
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        onCancel()
                    }
                }
                if allowsCreatingPassword && service.isUnlocked {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showingNewLogin = true
                        } label: {
                            Label("New Login", systemImage: "plus")
                        }
                    }
                }
            }
            .sheet(isPresented: $showingNewLogin) {
                NewLoginView(
                    service: service,
                    site: siteName,
                    onSaved: { item in
                        showingNewLogin = false
                        onCreated?(item)
                    },
                    onCancel: { showingNewLogin = false }
                )
            }
```

Replace the empty-state `ContentUnavailableView` (`:225-232`) so it offers the
action rather than pointing at another app:

```swift
            if vaultIsEmpty {
                ContentUnavailableView {
                    Label("No Items", systemImage: "key.slash")
                } description: {
                    Text(allowsCreatingPassword
                         ? "Create a login here, or add passwords in the Groo app"
                         : "Add passwords in the Groo app to fill them here")
                } actions: {
                    if allowsCreatingPassword {
                        Button("New Login") { showingNewLogin = true }
                    }
                }
            } else if isSearching && searchResultCredentials.isEmpty && searchResultPasskeys.isEmpty {
```

- [ ] **Step 3: Set the flag per entry point in the controller**

In `GrooAutoFill/CredentialProviderViewController.swift`, add a stored property
beside `currentServiceIdentifiers` (`:19`):

```swift
    /// Whether the presentation in progress can be completed with an
    /// `ASPasswordCredential`. True for the credential-list entry points and
    /// for the list fallback; false for a passkey assertion, which must be
    /// answered with `completeAssertionRequest`. Set explicitly per entry
    /// point: an inferred rule silently becomes wrong when one is added.
    private var allowsCreatingPassword = false
```

Change `updateServiceIdentifiers` (`:122-125`) to take the flag:

```swift
    private func updateServiceIdentifiers(
        _ identifiers: [ASCredentialServiceIdentifier],
        allowsCreatingPassword: Bool
    ) {
        currentServiceIdentifiers = identifiers
        self.allowsCreatingPassword = allowsCreatingPassword
        show(rootView: AnyView(makeCredentialListView(serviceIdentifiers: identifiers)))
    }
```

Extend `makeCredentialListView` (`:143-160`) with the two new arguments:

```swift
            allowsCreatingPassword: allowsCreatingPassword,
            onCreated: { [weak self] item in
                self?.selectCredential(item)
            },
```

Place them after `allowedCredentialIds:` and before `onSelect:`, matching the
declaration order in the view.

Update the three call sites:

- `prepareInterfaceToProvideCredential(for credentialIdentity:)` (`:179`):
  `updateServiceIdentifiers([credentialIdentity.serviceIdentifier], allowsCreatingPassword: true)`
- `prepareCredentialList(for:)` (`:187`):
  `updateServiceIdentifiers(serviceIdentifiers, allowsCreatingPassword: true)`
- `prepareCredentialList(for:requestParameters:)` (`:198`):
  `updateServiceIdentifiers(serviceIdentifiers, allowsCreatingPassword: true)`
- `completePendingRequest()`'s fallback (`:86`):
  `updateServiceIdentifiers([identity.serviceIdentifier], allowsCreatingPassword: true)`
- `viewDidLoad`'s initial call (`:42`) keeps the default: change it to
  `setupUI(rootView: AnyView(makeCredentialListView(serviceIdentifiers: currentServiceIdentifiers)))`
  unchanged — `allowsCreatingPassword` is still `false` there, which is correct:
  nothing has told us what iOS is asking for yet.

The passkey paths (`prepareInterface(forPasskeyRegistration:)` and the
`ASPasskeyCredentialRequest` branch of
`prepareInterfaceToProvideCredential(for credentialRequest:)`) must NOT set the
flag — they never present the list.

- [ ] **Step 4: Build**

Run: `xcodebuild -project Groo.xcodeproj -scheme Groo -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build`
Expected: BUILD SUCCEEDED.

- [ ] **Step 5: Run the full unit suite**

Run: `scripts/test.sh --unit`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add GrooAutoFill/NewLoginView.swift GrooAutoFill/AutoFillCredentialListView.swift GrooAutoFill/CredentialProviderViewController.swift
git commit -m "feat(autofill): offer New Login in the credential sheet

Gated on an explicit per-entry-point flag rather than inferred from the
request shape — a passkey assertion must not be answered with a password."
```

---

### Task 8: Drain the queue in the main app

Also fixes a latent hazard that already applies to passkeys: the drain POSTs a
record whose id the server may already hold (the extension pushed it), and
`writeRecordIfChanged` (`PassService.swift:951-989`) chooses POST purely on
`recordState` — which can be stale. The server answers `409 RECORD_EXISTS`,
which is **not** the `recordConflict` the PUT path handles, so `saveVault()`
throws. Refreshing records before merging removes the case entirely.

**Files:**
- Modify: `Groo/Features/Pass/PendingPasskeyStoring.swift`
- Modify: `Groo/Features/Pass/PassService.swift` — rename at `:1003`, the nine
  call sites, and the init at `:81-94`
- Create: `GrooTests/Support/InMemoryPendingPasswordStore.swift`
- Test: `GrooTests/Features/Pass/PassServiceMergePendingTests.swift`
- Test: `GrooTests/Features/Pass/PassServiceIntegrationTests.swift` (extend `makeEnv` at `:37-86`, append drain tests beside `syncDrainsPasskeysQueuedByAutoFill` at `:410`)

**Interfaces:**
- Consumes: `SharedPendingPasswordItem`, `SharedPendingPasswordsStore`
- Produces:
  - `protocol PendingPasswordStoring { func load(key:) throws -> [SharedPendingPasswordItem]; func clear() }`
  - `struct SharedPendingPasswordStore: PendingPasswordStoring`
  - `PassService.mergePendingItems() async` (replaces `mergePendingPasskeys()`)
  - `PassService.init(..., pendingPasswords: any PendingPasswordStoring = SharedPendingPasswordStore(), ...)`

- [ ] **Step 1: Write the failing test**

Create `GrooTests/Features/Pass/PassServiceMergePendingTests.swift`:

```swift
//
//  PassServiceMergePendingTests.swift
//  GrooTests
//
//  The drain that moves logins created in the AutoFill sheet into the vault.
//

import CryptoKit
import Foundation
import Testing
@testable import Groo

@MainActor
struct PassServiceMergePendingTests {

    static func pending(id: String, name: String = "github.com") -> SharedPendingPasswordItem {
        SharedNewLoginDraft(name: name, username: "me", password: "hunter2", site: "github.com")
            .pendingItem(id: id, now: 1_700_000_000_123)
    }

    /// The payload the app rebuilds when draining must be byte-identical to the
    /// one the extension already pushed. If it is not, every drain rewrites a
    /// record that was already correct — and on a stale `recordState` that
    /// rewrite is a POST against an id the server already holds.
    @Test func theDrainedPayloadMatchesWhatTheExtensionPushed() throws {
        let envelope = Self.pending(id: "item-1")

        let extensionPayload = try PasswordPublisher(
            pusher: PasswordPublisherTests.SpyPusher(),
            vaultKey: SymmetricKey(size: .bits256)
        ).payload(for: envelope)

        let appItem = PassService.passwordItem(from: envelope)
        let appPayload = try JSONEncoder().encode(appItem)

        func normalized(_ data: Data) throws -> Data {
            try JSONSerialization.data(
                withJSONObject: try JSONSerialization.jsonObject(with: data),
                options: [.sortedKeys]
            )
        }

        #expect(try normalized(appPayload) == normalized(extensionPayload))
    }

    @Test func theRebuiltItemKeepsTheQueuedTimestamps() {
        let item = PassService.passwordItem(from: Self.pending(id: "item-1"))

        // Re-stamping loses when the user actually created it, and makes the
        // payload differ from the pushed record.
        #expect(item.createdAt == 1_700_000_000_123)
        #expect(item.updatedAt == 1_700_000_000_123)
    }

    @Test func theRebuiltItemLeavesUnusedOptionalsNil() {
        let item = PassService.passwordItem(from: Self.pending(id: "item-1"))

        // Any non-nil value here is encoded, and the extension omits all four —
        // which would make the two payloads differ.
        #expect(item.notes == nil)
        #expect(item.totp == nil)
        #expect(item.folderId == nil)
        #expect(item.favorite == nil)
    }
}
```

- [ ] **Step 2: Run the test and watch it fail**

Run: `xcodebuild test -project Groo.xcodeproj -scheme Groo -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:GrooTests/PassServiceMergePendingTests`
Expected: build failure — no `PassService.passwordItem(from:)`, and
`PasswordPublisherTests.SpyPusher` must be visible (it is: same target).

- [ ] **Step 3: Add the storing seam**

In `Groo/Features/Pass/PendingPasskeyStoring.swift`, append:

```swift
protocol PendingPasswordStoring {
    func load(key: SymmetricKey) throws -> [SharedPendingPasswordItem]
    func clear()
}

/// Production implementation, backed by the App Group queue file.
struct SharedPendingPasswordStore: PendingPasswordStoring {
    func load(key: SymmetricKey) throws -> [SharedPendingPasswordItem] {
        try SharedPendingPasswordsStore.load(key: key)
    }

    func clear() {
        SharedPendingPasswordsStore.clear()
    }
}
```

- [ ] **Step 4: Add the in-memory fake**

Create `GrooTests/Support/InMemoryPendingPasswordStore.swift`:

```swift
//
//  InMemoryPendingPasswordStore.swift
//  GrooTests
//
//  PendingPasswordStoring fake standing in for the App Group queue the AutoFill
//  extension writes to.
//

import CryptoKit
import Foundation
@testable import Groo

final class InMemoryPendingPasswordStore: PendingPasswordStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var _items: [SharedPendingPasswordItem] = []
    private var _clearCount = 0

    /// Set to make `load` throw, standing in for an unreadable queue file.
    var loadError: Error?

    var items: [SharedPendingPasswordItem] {
        get { lock.withLock { _items } }
        set { lock.withLock { _items = newValue } }
    }

    /// How many times the queue was cleared — a merge that fails must not clear.
    var clearCount: Int { lock.withLock { _clearCount } }

    func load(key: SymmetricKey) throws -> [SharedPendingPasswordItem] {
        if let loadError { throw loadError }
        return items
    }

    func clear() {
        lock.withLock {
            _clearCount += 1
            _items = []
        }
    }
}
```

- [ ] **Step 5: Rename the drain and add the password half**

In `Groo/Features/Pass/PassService.swift`:

Add the dependency beside `pendingPasskeys` (`:57`, `:85`, `:94`):

```swift
    private let pendingPasswords: any PendingPasswordStoring
```
```swift
        pendingPasswords: any PendingPasswordStoring = SharedPendingPasswordStore(),
```
```swift
        self.pendingPasswords = pendingPasswords
```

Rename `func mergePendingPasskeys() async` (`:1003`) to
`func mergePendingItems() async` and restructure it as below. Note the records
refresh at the top and the re-read of `vault` after it.

```swift
    /// Rebuild a queued login as the vault's own model.
    ///
    /// `static` and `internal` so the payload-equality test can reach it: the
    /// JSON this produces must match `PasswordPublisher.payload` exactly.
    /// Every optional stays nil — the encoder omits nil, and the extension's
    /// payload omits all four.
    static func passwordItem(from pending: SharedPendingPasswordItem) -> PassPasswordItem {
        PassPasswordItem(
            id: pending.item.id,
            type: .password,
            name: pending.item.name,
            username: pending.item.username,
            password: pending.item.password,
            urls: pending.item.urls,
            notes: nil,
            totp: nil,
            folderId: nil,
            favorite: nil,
            createdAt: pending.createdAt,
            updatedAt: pending.updatedAt
        )
    }

    /// Merge everything the AutoFill extension created while the app wasn't
    /// running — passkeys and logins — then push and clear the queues.
    func mergePendingItems() async {
        guard let key = encryptionKey else { return }

        // Refresh records first. The extension may already have pushed a record
        // for a queued item; without this, `writeRecordIfChanged` sees no local
        // record, POSTs the same id, and the server answers 409 RECORD_EXISTS —
        // which is not the recordConflict the PUT path recovers from, so the
        // whole save throws. A failure here is not fatal: the merge still runs
        // against what we have, and a genuinely stale write just stays queued.
        if formatVersion == 2 {
            do {
                try await loadFromRecords(using: key)
            } catch {
                Log.pass.error(
                    "Could not refresh records before draining pending items: \(String(describing: error), privacy: .public)"
                )
            }
        }

        guard var vault = vault else { return }

        let pendingPasskeyItems: [SharedPassPasskeyItem]
        do {
            pendingPasskeyItems = try pendingPasskeys.load(key: key)
        } catch {
            // Never clear an unreadable queue; already logged by the store
            Log.pass.error("Cannot read pending passkey queue: \(String(describing: error), privacy: .public)")
            pendingPasskeyItems = []
        }

        let pendingPasswordItems: [SharedPendingPasswordItem]
        do {
            pendingPasswordItems = try pendingPasswords.load(key: key)
        } catch {
            Log.pass.error("Cannot read pending login queue: \(String(describing: error), privacy: .public)")
            pendingPasswordItems = []
        }

        guard !pendingPasskeyItems.isEmpty || !pendingPasswordItems.isEmpty else { return }

        let existingCredentialIds = Set(vault.items.compactMap { item -> String? in
            guard case .passkey(let passkey) = item else { return nil }
            return passkey.credentialId
        })
        let existingIds = Set(vault.items.map(\.id))

        let now = Int(Date().timeIntervalSince1970 * 1000)
        var added = false

        for shared in pendingPasskeyItems where !existingCredentialIds.contains(shared.credentialId) {
            let item = PassPasskeyItem(
                id: shared.id,
                name: shared.name,
                rpId: shared.rpId,
                rpName: shared.rpName,
                credentialId: shared.credentialId,
                publicKey: shared.publicKey,
                privateKey: shared.privateKey,
                userHandle: shared.userHandle,
                userName: shared.userName,
                signCount: shared.signCount,
                createdAt: now,
                updatedAt: now
            )
            vault.items.append(.passkey(item))
            added = true
        }

        // Dedupe by id, not by name or username: two logins for the same site
        // with the same username are legitimate.
        for pending in pendingPasswordItems where !existingIds.contains(pending.item.id) {
            vault.items.append(.password(Self.passwordItem(from: pending)))
            added = true
        }

        do {
            if added {
                vault.lastModified = now
                self.vault = vault
                try await saveVault()
                Log.pass.info(
                    "Merged \(pendingPasskeyItems.count) passkey(s) and \(pendingPasswordItems.count) login(s) from AutoFill"
                )
            }
            pendingPasskeys.clear()
            pendingPasswords.clear()
            pendingSyncCount = 0
        } catch {
            // Keep both queues so the merge retries on the next unlock/sync —
            // but a persistent failure must be observable, hence the count.
            pendingSyncCount = pendingPasskeyItems.count + pendingPasswordItems.count
            Log.pass.error(
                "Failed to sync pending AutoFill items, will retry: \(String(describing: error), privacy: .public)"
            )
        }
    }
```

Add the observable count beside `lastError` (`:77`):

```swift
    /// Items created in the AutoFill sheet that a drain has failed to sync.
    /// Zero on every normal path — this exists so a *persistently* failing
    /// drain, where a password lives only on this device, is visible.
    private(set) var pendingSyncCount = 0
```

- [ ] **Step 6: Update all nine call sites**

Replace `mergePendingPasskeys()` with `mergePendingItems()` at
`PassService.swift:185, 234, 303, 325, 364, 1073, 1089, 1129` and
`Groo/ContentView.swift:90`. Verify none remain:

Run: `grep -rn "mergePendingPasskeys" Groo GrooAutoFill GrooTests Shared`
Expected: no output.

- [ ] **Step 7: Cover the drain's behaviour end to end**

The payload tests above check the *shape* of what is merged. These check that
the merge actually happens, and — the case that matters — that a failed save
keeps the queues.

In `GrooTests/Features/Pass/PassServiceIntegrationTests.swift`, extend
`makeEnv` (`:37-86`) with a second queue. Add the parameter:

```swift
        pending: InMemoryPendingPasskeyStore = InMemoryPendingPasskeyStore(),
        pendingPasswords: InMemoryPendingPasswordStore = InMemoryPendingPasswordStore()
```

pass it to the service:

```swift
        let service = PassService(
            api: api,
            crypto: crypto,
            keychain: keychain,
            vaultStore: PassVaultStore(directoryURL: tempDir),
            credentialService: credentials,
            pendingPasskeys: pending,
            pendingPasswords: pendingPasswords)
```

add it to `Env` (beside `let pending: InMemoryPendingPasskeyStore`, `:29`):

```swift
        let pendingPasswords: InMemoryPendingPasswordStore
```

and to the returned value:

```swift
        return Env(service: service, keychain: keychain, credentials: credentials,
                   key: key, salt: salt, tempDir: tempDir, pending: pending,
                   pendingPasswords: pendingPasswords)
```

Then append these tests beside `syncDrainsPasskeysQueuedByAutoFill` (`:410`),
inside the same suite:

```swift
    static func makeSharedPassword(id: String = "item-1") -> SharedPendingPasswordItem {
        SharedNewLoginDraft(name: "github.com", username: "me", password: "hunter2", site: "github.com")
            .pendingItem(id: id, now: 1_700_000_000_123)
    }

    /// Re-stub the vault GET that `sync()` performs before the drain PUTs.
    static func stubVaultGetForSync(items: [PassVaultItem], key: SymmetricKey, version: Int) throws {
        let vault = PassVault(version: 1, items: items, folders: [], lastModified: 1_700_000_000_000)
        let combined = try crypto.encryptData(try JSONEncoder().encode(vault), using: key)
        StubURLProtocol.enqueue(
            method: "GET", pathSuffix: "/v1/vault",
            json: #"{"encryptedData":"\#(combined.dropFirst(12).base64EncodedString())","iv":"\#(combined.prefix(12).base64EncodedString())","version":\#(version),"updatedAt":1700000002}"#)
    }

    @Test func syncDrainsLoginsQueuedByAutoFill() async throws {
        let env = try Self.makeEnv(items: [])
        _ = try await env.service.unlock(password: Self.password)

        env.pendingPasswords.items = [Self.makeSharedPassword()]

        try Self.stubVaultGetForSync(items: [], key: env.key, version: 4)
        Self.stubVaultPut(version: 5)

        try await env.service.sync()

        let uploaded = try Self.decodeUploadedVault(key: env.key)
        let passwords = uploaded.vault.items.compactMap { item -> PassPasswordItem? in
            guard case .password(let password) = item else { return nil }
            return password
        }
        #expect(passwords.map(\.id) == ["item-1"])
        #expect(passwords.first?.password == "hunter2")
        // The queued timestamps survive the drain — see the payload-equality test.
        #expect(passwords.first?.createdAt == 1_700_000_000_123)
        #expect(env.pendingPasswords.clearCount == 1)
        #expect(env.pendingPasswords.items.isEmpty)
        #expect(env.service.pendingSyncCount == 0)
    }

    @Test func aLoginAlreadyInTheVaultIsNotMergedTwice() async throws {
        // The extension pushed the record and it came back on sync, but the
        // queue still holds it — only the app clears the queue.
        let existing = PassVaultItem.password(PassService.passwordItem(from: Self.makeSharedPassword()))
        let env = try Self.makeEnv(items: [existing])
        _ = try await env.service.unlock(password: Self.password)

        env.pendingPasswords.items = [Self.makeSharedPassword()]

        try Self.stubVaultGetForSync(items: [existing], key: env.key, version: 4)
        Self.stubVaultPut(version: 5)

        try await env.service.sync()

        // Nothing was added, so nothing needed uploading — but the queue is
        // still cleared, because its contents are already in the vault.
        #expect(env.pendingPasswords.clearCount == 1)
        #expect(env.service.pendingSyncCount == 0)
    }

    @Test func aFailedSaveKeepsBothQueuesAndReportsTheCount() async throws {
        let env = try Self.makeEnv(items: [])
        _ = try await env.service.unlock(password: Self.password)

        env.pending.items = [Self.makeSharedPasskey()]
        env.pendingPasswords.items = [Self.makeSharedPassword()]

        try Self.stubVaultGetForSync(items: [], key: env.key, version: 4)
        // The upload fails. Clearing here would destroy the only copy of both
        // the passkey private key and the password.
        StubURLProtocol.enqueue(
            method: "PUT", pathSuffix: "/v1/vault", status: 500,
            json: #"{"error":"boom"}"#)

        _ = try? await env.service.sync()

        #expect(env.pending.clearCount == 0)
        #expect(env.pendingPasswords.clearCount == 0)
        #expect(env.pending.items.count == 1)
        #expect(env.pendingPasswords.items.count == 1)
        #expect(env.service.pendingSyncCount == 2)
    }
```

`syncDrainsPasskeysQueuedByAutoFill` must keep passing untouched — it is the
regression guard that the rename did not change passkey behaviour.

- [ ] **Step 8: Run the tests**

```bash
xcodebuild test -project Groo.xcodeproj -scheme Groo -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:GrooTests/PassServiceMergePendingTests
scripts/test.sh --unit
```
Expected: PASS. Any existing test referring to `mergePendingPasskeys` needs its
call renamed — that is the intended compile error from D6, not a behaviour
change.

- [ ] **Step 9: Commit**

```bash
git add Groo/Features/Pass/PassService.swift Groo/Features/Pass/PendingPasskeyStoring.swift Groo/ContentView.swift GrooTests/Features/Pass/PassServiceMergePendingTests.swift GrooTests/Features/Pass/PassServiceIntegrationTests.swift GrooTests/Support/InMemoryPendingPasswordStore.swift
git commit -m "feat(pass): drain AutoFill logins into the vault

Renames the passkey drain rather than adding a parallel one, so a missed
call site is a compile error. Refreshes records first: the extension may
already have pushed the record, and a POST on an id the server holds
answers 409 RECORD_EXISTS, which the PUT conflict path cannot recover."
```

---

### Task 9: Waiting-to-sync banner

**Files:**
- Modify: `Groo/Features/Pass/Views/PassItemListView.swift:33-34`
- Test: manual (Task 10) plus the existing snapshot suite

**Interfaces:**
- Consumes: `PassService.pendingSyncCount` (Task 8), `PassService.sync()`

- [ ] **Step 1: Add the banner**

In `Groo/Features/Pass/Views/PassItemListView.swift`, add a state property
beside `actionError` (`:20`):

```swift
    @State private var isRetryingSync = false
```

Add the banner as the first element inside the `List` (before the favourites
section at `:35`):

```swift
            if passService.pendingSyncCount > 0 {
                Section {
                    HStack(spacing: Theme.Spacing.sm) {
                        Image(systemName: "exclamationmark.arrow.triangle.2.circlepath")
                            .foregroundStyle(.orange)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(passService.pendingSyncCount) item\(passService.pendingSyncCount == 1 ? "" : "s") waiting to sync")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Text("Created in AutoFill and saved on this device only.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        if isRetryingSync {
                            ProgressView()
                        } else {
                            Button("Retry") {
                                isRetryingSync = true
                                Task {
                                    defer { isRetryingSync = false }
                                    do {
                                        try await passService.sync()
                                    } catch {
                                        actionError = error.localizedDescription
                                    }
                                }
                            }
                            .font(.subheadline)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
```

- [ ] **Step 2: Build and run the suite**

```bash
scripts/test.sh --unit
```
Expected: PASS. `PassViewSnapshotTests` renders this screen with a
`pendingSyncCount` of 0, so no snapshot should move. If one does, the banner is
rendering when the count is zero — fix the condition, not the snapshot.

- [ ] **Step 3: Commit**

```bash
git add Groo/Features/Pass/Views/PassItemListView.swift
git commit -m "feat(pass): surface AutoFill items a drain has failed to sync"
```

---

### Task 10: Verification runbook

The form is extension UI and cannot be snapshot-tested from `GrooTests`, and
AutoFill cannot be exercised from `GrooUITests`. This task is the only coverage
of the composed flow — do not skip it, and record the actual results.

**Files:**
- Create: `docs/superpowers/acceptance/2026-08-25-autofill-create-login.md`

- [ ] **Step 1: Full suite and clean build**

```bash
xcodebuild clean -project Groo.xcodeproj -scheme Groo
scripts/test.sh --all
```

A clean build matters here: the extension is embedded at
`Groo.app/PlugIns/GrooAutoFill.appex` and the embed step does not always re-run,
so an incremental build can leave you testing the previous extension binary.

- [ ] **Step 2: Simulator pass**

Install the app, unlock the vault once so the encryption key reaches the shared
keychain, enable Groo under Settings → General → AutoFill & Passwords, then in
Safari open any sign-up form and tap the password field.

Record for each: PASS/FAIL and what you actually saw.

1. The `+` button appears in the sheet after unlock.
2. New Login prefills the site and a name; the username field has focus.
3. Generate produces a 20-character password and reveals it.
4. Save fills **both** the username and password fields on the page.
5. Re-opening the sheet on the same site lists the new login under
   "Suggested for <host>" — this is the pending-merge read path.
6. Opening the Groo app shows the login in the vault, and the banner does not
   appear.

- [ ] **Step 3: Offline pass**

With the device in Airplane Mode, repeat 1-4. Then:

7. The save still fills the field, within roughly the 5-second deadline.
8. Opening the Groo app while still offline shows the banner with a count of 1.
9. Turning networking back on and tapping Retry clears the banner, and the item
   appears in the vault.

- [ ] **Step 4: Device pass**

Repeat steps 2 and 3 on a physical device. Face ID, the shared keychain and the
App Group all behave differently there, and extension logs are only readable
from a device log archive (`sudo log collect --device-udid <udid>`).

10. Confirm the record reached the server: the item is visible in the `pass` web
    app after a refresh.
11. Confirm no credential material was logged:
    `log show --predicate 'subsystem == "dev.groo.ios"' --last 30m | grep -ci hunter2`
    Expected: `0`.

- [ ] **Step 5: Write the runbook with the results filled in**

Create `docs/superpowers/acceptance/2026-08-25-autofill-create-login.md`
containing the eleven checks above with the observed result beside each, the
device and OS version used, and anything that failed. **A check that was not
run is recorded as "not run", never as a pass.**

- [ ] **Step 6: Commit**

```bash
git add docs/superpowers/acceptance/2026-08-25-autofill-create-login.md
git commit -m "docs: acceptance results for creating a login from AutoFill"
```

---

## Post-implementation

After Task 10, run a data-security review over the whole diff before the branch
is merged, covering: the new queue file's contents and lifetime, that no
credential field reaches a log, that `forceRefresh` is still disabled on every
extension-built `PassAPIClient`, and that `allowsCreatingPassword` is false on
every path that must be answered with `completeAssertionRequest`.
