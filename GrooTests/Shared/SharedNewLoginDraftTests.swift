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
