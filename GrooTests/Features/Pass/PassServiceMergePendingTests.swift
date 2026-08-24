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
