//
//  PassViewSnapshotTests.swift
//  GrooTests
//
//  Phase 7: render/snapshot coverage for all 11 Pass views over the
//  Phase 1 fake vault (makeEnv). Fixed-epoch fixtures; the canonical
//  decoded items carry fixed timestamps. Generator and TOTP surfaces are
//  render-only (random/live content).
//

import SnapshotTesting
import SwiftUI
import Testing
@testable import Groo

extension NetworkStubbedSuites {

@MainActor
@Suite(.serialized, .snapshots(record: .missing))
struct PassViewSnapshotTests {
    static let fixedMs = 1_700_000_000_000

    static func allItems() throws -> [PassVaultItem] {
        try VaultItemFixtures.allItemJSONs.map {
            try JSONDecoder().decode(PassVaultItem.self, from: Data($0.utf8))
        }
    }

    static func snapPassword(
        id: String = "pw-snap", name: String = "Example Login",
        password: String = "hunter2-secret", totp: PassTotpConfig? = nil,
        folderId: String? = nil, updatedAt: Int = fixedMs, deletedAt: Int? = nil
    ) -> PassVaultItem {
        .password(PassPasswordItem(
            id: id, type: .password, name: name, username: "user@example.com",
            password: password, urls: ["https://example.com/login"], notes: "Work account",
            totp: totp, folderId: folderId, favorite: true,
            createdAt: fixedMs, updatedAt: updatedAt, deletedAt: deletedAt))
    }

    static func makeUnlockedEnv(
        items: [PassVaultItem], folders: [PassFolder] = []
    ) async throws -> PassServiceIntegrationTests.Env {
        let env = try PassServiceIntegrationTests.makeEnv(items: items, folders: folders)
        _ = try await env.service.unlock(password: PassServiceIntegrationTests.password)
        return env
    }

    static func cleanUp(_ env: PassServiceIntegrationTests.Env) {
        try? FileManager.default.removeItem(at: env.tempDir)
    }

    // MARK: - Unlock / shell

    @Test func unlockViewLocked() throws {
        let env = try PassServiceIntegrationTests.makeEnv(items: [])
        defer { Self.cleanUp(env) }
        assertViewSnapshot(
            of: PassUnlockView(passService: env.service, onUnlock: {}, onSignOut: {}),
            named: "locked")
    }

    @Test func passViewLockedShell() throws {
        let env = try PassServiceIntegrationTests.makeEnv(items: [])
        defer { Self.cleanUp(env) }
        // .task fires checkVaultSetup against the stubbed key-info GET
        // (last-response-repeats); the async result lands post-draw.
        assertViewSnapshot(
            of: PassView(passService: env.service, onSignOut: {}),
            named: "locked")
    }

    // MARK: - Item list (dark + Dynamic Type representative set lives here)

    // NB: PassItemListView combines NavigationStack + .searchable(.automatic) +
    // .toolbar over a List with real ForEach row content. On this simulator
    // (iOS 26.4) that exact combination renders with an empty list body at the
    // standard 402x874 device canvas in this harness's offscreen
    // layer.render(in:) capture — confirmed by direct experiment: the same
    // view (same service, same items) renders every row correctly at a taller
    // canvas, and isolated repros without the toolbar+searchable combination
    // (or without real ForEach content) render fine at 874. It is not a
    // settle/timing issue — extra yields and RunLoop spins made no
    // difference. Use a generous fixed canvas height for these two tests so
    // the snapshot captures real row content instead of a misleading blank
    // page; unrelated to the device-size convention used elsewhere.
    static let tallListSize = CGSize(width: 402, height: 1800)
    static let tallListA11ySize = CGSize(width: 402, height: 2800)

    @Test func itemListPopulated() async throws {
        let env = try await Self.makeUnlockedEnv(items: Self.allItems())
        defer { Self.cleanUp(env) }
        let view = NavigationStack {
            PassItemListView(passService: env.service, onSelectItem: { _ in },
                             onAddItem: {}, onEditItem: { _ in })
        }
        assertViewSnapshot(of: view, named: "populated", size: Self.tallListSize)
    }

    @Test func itemListRepresentativeSet() async throws {
        let env = try await Self.makeUnlockedEnv(items: Self.allItems())
        defer { Self.cleanUp(env) }
        let view = NavigationStack {
            PassItemListView(passService: env.service, onSelectItem: { _ in },
                             onAddItem: {}, onEditItem: { _ in })
        }
        assertViewSnapshot(of: view, named: "dark", size: Self.tallListSize, appearance: .dark)
        assertViewSnapshot(
            of: view.environment(\.dynamicTypeSize, .accessibility2), named: "a11y-xl",
            size: Self.tallListA11ySize)
    }

    @Test func itemListEmpty() async throws {
        let env = try await Self.makeUnlockedEnv(items: [])
        defer { Self.cleanUp(env) }
        assertViewSnapshot(
            of: NavigationStack {
                PassItemListView(passService: env.service, onSelectItem: { _ in },
                                 onAddItem: {}, onEditItem: { _ in })
            },
            named: "empty")
    }

    // MARK: - Detail (every type; totp-bearing password is render-only)

    @Test func itemDetailEveryType() async throws {
        let items = try Self.allItems()
        let env = try await Self.makeUnlockedEnv(items: items)
        defer { Self.cleanUp(env) }

        // The canonical password fixture carries a TOTP config → live code →
        // render-only. Snapshot the password type via a no-totp twin instead.
        for item in items {
            let view = NavigationStack {
                PassItemDetailView(item: item, passService: env.service, onDismiss: {})
            }
            if case .password(let pwd) = item, pwd.totp != nil {
                ViewRender.assertRenders(view)
            } else {
                assertViewSnapshot(of: view, named: item.type.rawValue)
            }
        }
        assertViewSnapshot(
            of: NavigationStack {
                PassItemDetailView(item: Self.snapPassword(), passService: env.service, onDismiss: {})
            },
            named: "password")
    }

    @Test func itemDetailCorrupted() async throws {
        let corrupted = PassVaultItem.corrupted(PassCorruptedItem(
            id: "bad-1", rawJson: #"{"type":"alien"}"#,
            error: "unknown item type: alien", raw: nil))
        let env = try await Self.makeUnlockedEnv(items: [corrupted])
        defer { Self.cleanUp(env) }
        assertViewSnapshot(
            of: NavigationStack {
                PassItemDetailView(item: corrupted, passService: env.service, onDismiss: {})
            },
            named: "corrupted")
    }

    // Gap-menu lever 5 (P7 Task 9): PassItemDetailView branches not hit by
    // the canonical fixtures — not-favorite (no star), no notes (section
    // omitted), and multiple URLs (ForEach over 2+ rows).
    @Test func itemDetailExtraStates() async throws {
        let item = PassVaultItem.password(PassPasswordItem(
            id: "pw-extra", type: .password, name: "Multi URL Login", username: "user2@example.com",
            password: "another-secret",
            urls: ["https://example.com/login", "https://example.org/login"],
            notes: nil, totp: nil, folderId: nil, favorite: false,
            createdAt: Self.fixedMs, updatedAt: Self.fixedMs, deletedAt: nil))
        let env = try await Self.makeUnlockedEnv(items: [item])
        defer { Self.cleanUp(env) }
        assertViewSnapshot(
            of: NavigationStack {
                PassItemDetailView(item: item, passService: env.service, onDismiss: {})
            },
            named: "not-favorite-no-notes-multi-url")
    }

    // MARK: - Form (add per editable type + edit mode)

    @Test func formAddModes() async throws {
        let env = try await Self.makeUnlockedEnv(items: [], folders: [PassFolder(id: "f-1", name: "Work", parentId: nil)])
        defer { Self.cleanUp(env) }
        for type in [PassVaultItemType.password, .card, .bankAccount, .note] {
            assertViewSnapshot(
                of: NavigationStack {
                    PassItemFormView(passService: env.service, defaultType: type,
                                     onSave: {}, onCancel: {})
                },
                named: "add-\(type.rawValue)")
        }
    }

    @Test func formEditModes() async throws {
        let items = try Self.allItems()
        let env = try await Self.makeUnlockedEnv(items: items)
        defer { Self.cleanUp(env) }
        let note = try #require(items.first(where: { $0.type == .note }))
        assertViewSnapshot(
            of: NavigationStack {
                PassItemFormView(passService: env.service, editingItem: Self.snapPassword(),
                                 onSave: {}, onCancel: {})
            },
            named: "edit-password")
        assertViewSnapshot(
            of: NavigationStack {
                PassItemFormView(passService: env.service, editingItem: note,
                                 onSave: {}, onCancel: {})
            },
            named: "edit-note")
    }

    // MARK: - Folders / trash

    @Test func folderListStates() async throws {
        let folders = [PassFolder(id: "f-1", name: "Work", parentId: nil),
                       PassFolder(id: "f-2", name: "Personal", parentId: nil)]
        let populated = try await Self.makeUnlockedEnv(
            items: [Self.snapPassword(folderId: "f-1")], folders: folders)
        defer { Self.cleanUp(populated) }
        assertViewSnapshot(
            of: NavigationStack {
                PassFolderListView(passService: populated.service, onDismiss: {}, onSelectFolder: { _ in })
            },
            named: "populated")

        let empty = try await Self.makeUnlockedEnv(items: [])
        defer { Self.cleanUp(empty) }
        assertViewSnapshot(
            of: NavigationStack {
                PassFolderListView(passService: empty.service, onDismiss: {}, onSelectFolder: { _ in })
            },
            named: "empty")
    }

    @Test func trashStates() async throws {
        let deleted = Self.snapPassword(id: "pw-del", name: "Old Login", deletedAt: Self.fixedMs)
        let populated = try await Self.makeUnlockedEnv(items: [deleted])
        defer { Self.cleanUp(populated) }
        assertViewSnapshot(
            of: NavigationStack { PassTrashView(passService: populated.service, onDismiss: {}) },
            named: "populated")

        let empty = try await Self.makeUnlockedEnv(items: [])
        defer { Self.cleanUp(empty) }
        assertViewSnapshot(
            of: NavigationStack { PassTrashView(passService: empty.service, onDismiss: {}) },
            named: "empty")
    }

    // MARK: - Health report (settled: its .task is pure main-actor in-memory work)

    @Test func healthReportStates() async throws {
        let mixed = try await Self.makeUnlockedEnv(items: [
            Self.snapPassword(id: "pw-weak", name: "Weak", password: "123"),
            Self.snapPassword(id: "pw-reuse-1", name: "Reused A", password: "shared-password-1"),
            Self.snapPassword(id: "pw-reuse-2", name: "Reused B", password: "shared-password-1"),
            Self.snapPassword(id: "pw-old", name: "Old", password: "Str0ng!passphrase-old",
                              updatedAt: 1_500_000_000_000),
        ])
        defer { Self.cleanUp(mixed) }
        await assertSettledViewSnapshot(
            of: NavigationStack {
                PasswordHealthView(passService: mixed.service, onDismiss: {}, onSelectItem: { _ in })
            },
            named: "mixed-report")

        let empty = try await Self.makeUnlockedEnv(items: [])
        defer { Self.cleanUp(empty) }
        await assertSettledViewSnapshot(
            of: NavigationStack {
                PasswordHealthView(passService: empty.service, onDismiss: {}, onSelectItem: { _ in })
            },
            named: "empty-vault")
    }

    // MARK: - Rows / generator / TOTP

    @Test func itemRowVariants() throws {
        let items = try Self.allItems()
        let note = try #require(items.first(where: { $0.type == .note }))
        let stack = VStack(spacing: 0) {
            PassItemRow(item: Self.snapPassword(), onTap: {}, onCopyPassword: {})
            PassItemRow(item: note, onTap: {})
        }
        assertViewSnapshot(of: stack, named: "variants", size: CGSize(width: 402, height: 220))
    }

    @Test func passwordGeneratorRendersOnly() {
        // onAppear generates a random password — snapshot would differ every run.
        ViewRender.assertRenders(
            NavigationStack { PasswordGeneratorView(onPasswordGenerated: { _ in }) })
    }

    @Test func totpDisplayRendersOnly() {
        // Live code + countdown ring — render-only by the determinism rule.
        ViewRender.assertRenders(
            TotpDisplayView(
                config: PassTotpConfig(secret: "JBSWY3DPEHPK3PXP", algorithm: .sha1, digits: 6, period: 30),
                onCopy: { _ in })
            .padding(),
            size: CGSize(width: 402, height: 200))
    }
}
}
