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
