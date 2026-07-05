//
//  PadViewSnapshotTests.swift
//  GrooTests
//
//  Phase 7: render/snapshot coverage for the Pad views over an unlocked
//  PadService (biometric fake-keychain path — no network) and an offline
//  SyncService. Encrypted fixtures are produced with the env's real key so
//  decryption succeeds end-to-end.
//

import SnapshotTesting
import SwiftUI
import Testing
import CryptoKit
@testable import Groo

extension NetworkStubbedSuites {

@MainActor
@Suite(.serialized, .snapshots(record: .missing))
struct PadViewSnapshotTests {
    static let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)

    /// Encrypt text with the env's key and return the PadEncryptedPayload
    /// JSON string LocalPadItem/LocalScratchpad store.
    static func encryptedJSON(_ text: String, key: SymmetricKey) throws -> String {
        let combined = try CryptoService().encryptData(Data(text.utf8), using: key)
        let payload = PadEncryptedPayload(
            ciphertext: combined.dropFirst(12).base64EncodedString(),
            iv: combined.prefix(12).base64EncodedString(),
            version: 1)
        return String(decoding: try JSONEncoder().encode(payload), as: UTF8.self)
    }

    static func encryptedPayload(_ text: String, key: SymmetricKey) throws -> PadEncryptedPayload {
        let combined = try CryptoService().encryptData(Data(text.utf8), using: key)
        return PadEncryptedPayload(
            ciphertext: combined.dropFirst(12).base64EncodedString(),
            iv: combined.prefix(12).base64EncodedString(),
            version: 1)
    }

    static func offlineSync(store: LocalStore) -> SyncService {
        SyncService(
            api: APIClient(baseURL: URL(string: "https://pad.test")!,
                           sessionConfiguration: StubURLProtocol.stubbedConfiguration(),
                           tokenProvider: { "pad-token" }),
            store: store, monitorsNetwork: false)
    }

    static func lockedPadService() throws -> (service: PadService, store: LocalStore) {
        let store = try InMemoryLocalStore.make()
        let service = PadService(
            api: APIClient(baseURL: URL(string: "https://pad.test")!,
                           sessionConfiguration: StubURLProtocol.stubbedConfiguration(),
                           tokenProvider: { "pad-token" }),
            keychain: InMemoryKeychain(), store: store)
        return (service, store)
    }

    static func seedItem(_ env: PadServiceTests.Env, id: String, text: String,
                         files: [PadFileAttachment] = []) throws {
        let item = LocalPadItem(id: id, encryptedTextJSON: try Self.encryptedJSON(text, key: env.key),
                                createdAt: Self.fixedDate, syncedAt: Self.fixedDate)
        if !files.isEmpty { item.files = files }
        env.store.context.insert(item)
        try env.store.context.save()
    }

    static func fileAttachment(_ env: PadServiceTests.Env, id: String, name: String,
                               type: String, size: Int) throws -> PadFileAttachment {
        PadFileAttachment(id: id,
                          encryptedName: try Self.encryptedPayload(name, key: env.key),
                          size: size,
                          encryptedType: try Self.encryptedPayload(type, key: env.key),
                          r2Key: "files/\(id)")
    }

    // MARK: - Unlock / shell

    @Test func padUnlockLocked() throws {
        StubURLProtocol.reset()
        let (service, store) = try Self.lockedPadService()
        assertViewSnapshot(
            of: PadUnlockView(padService: service, syncService: Self.offlineSync(store: store),
                              onUnlock: {}, onSignOut: {}),
            named: "locked")
    }

    @Test func padViewLockedShell() throws {
        StubURLProtocol.reset()
        let (service, store) = try Self.lockedPadService()
        assertViewSnapshot(
            of: PadView(padService: service, syncService: Self.offlineSync(store: store), onSignOut: {}),
            named: "locked")
    }

    // MARK: - List

    @Test func padListPopulated() async throws {
        StubURLProtocol.reset()
        let env = try PadServiceTests.makeUnlockedEnv()
        try Self.seedItem(env, id: "item-1", text: "Meeting notes for Monday")
        try Self.seedItem(env, id: "item-2", text: "https://example.com/shared-link",
                          files: [try Self.fileAttachment(env, id: "f-1", name: "report.pdf",
                                                          type: "application/pdf", size: 82_944)])
        await assertSettledViewSnapshot(
            of: NavigationStack {
                PadListView(padService: env.service, syncService: Self.offlineSync(store: env.store))
            },
            named: "populated")
    }

    @Test func padListEmpty() async throws {
        StubURLProtocol.reset()
        let env = try PadServiceTests.makeUnlockedEnv()
        await assertSettledViewSnapshot(
            of: NavigationStack {
                PadListView(padService: env.service, syncService: Self.offlineSync(store: env.store))
            },
            named: "empty")
    }

    // NB: named `padItemRowVariants` (not `itemRowVariants`) — Xcode's resource
    // copy phase flattens every __Snapshots__ directory into one bundle-root
    // directory by filename, so this would otherwise collide with
    // PassViewSnapshotTests.itemRowVariants's identically-named PNG.
    @Test func padItemRowVariants() throws {
        StubURLProtocol.reset()
        let env = try PadServiceTests.makeUnlockedEnv()
        let plain = DecryptedListItem(id: "i-1", text: "Short note", files: [],
                                      createdAt: 1_700_000_000_000)
        let withFile = DecryptedListItem(
            id: "i-2", text: "Contract draft",
            files: [DecryptedFileAttachment(id: "f-1", name: "contract.docx",
                                            type: "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
                                            size: 120_832, r2Key: "files/f-1")],
            createdAt: 1_700_000_000_000)
        let long = DecryptedListItem(id: "i-3",
                                     text: String(repeating: "A very long pad entry line. ", count: 12),
                                     files: [], createdAt: 1_700_000_000_000)
        let rows = List {
            ItemRow(item: plain, padService: env.service, onCopy: {}, onDelete: {})
            ItemRow(item: withFile, padService: env.service, onCopy: {}, onDelete: {})
            ItemRow(item: long, padService: env.service, onCopy: {}, onDelete: {})
        }
        assertViewSnapshot(of: rows, named: "variants")
    }

    // MARK: - Add sheet / FAB / toast

    @Test func addItemSheetRendersOnly() throws {
        StubURLProtocol.reset()
        let env = try PadServiceTests.makeUnlockedEnv()
        // Focused TextEditor (caret) on appear — render-only by rule.
        ViewRender.assertRenders(
            NavigationStack {
                AddItemSheet(padService: env.service, syncService: Self.offlineSync(store: env.store))
            })
    }

    @Test func pasteFAB() throws {
        StubURLProtocol.reset()
        let env = try PadServiceTests.makeUnlockedEnv()
        assertViewSnapshot(
            of: PasteFAB(padService: env.service, syncService: Self.offlineSync(store: env.store),
                         onItemAdded: {})
                .padding(),
            named: "default", size: CGSize(width: 200, height: 160))
    }

    @Test func toastVariants() {
        let stack = VStack(spacing: 12) {
            ToastView(message: "Copied to clipboard", style: .success)
            ToastView(message: "Something went wrong", style: .error)
            ToastView(message: "Syncing…", style: .info)
        }.padding()
        assertViewSnapshot(of: stack, named: "styles", size: CGSize(width: 402, height: 260))
        assertViewSnapshot(
            of: Color.clear.toast(isPresented: .constant(true), message: "Copied!", style: .success),
            named: "modifier-presented")
    }

    @Test func toastStateTransitions() {
        let state = ToastState()
        #expect(!state.isPresented)
        state.showCopied()
        #expect(state.isPresented)
        #expect(state.style == .success)
        state.showError("nope")
        #expect(state.message == "nope")
        #expect(state.style == .error)
        state.show("info", style: .info)
        #expect(state.style == .info)
    }

    // MARK: - File attachments

    @Test func fileAttachmentComponents() throws {
        StubURLProtocol.reset()
        let env = try PadServiceTests.makeUnlockedEnv()
        let files = [
            DecryptedFileAttachment(id: "f-1", name: "report.pdf", type: "application/pdf",
                                    size: 82_944, r2Key: "files/f-1"),
            DecryptedFileAttachment(id: "f-2", name: "photo.jpg", type: "image/jpeg",
                                    size: 2_411_724, r2Key: "files/f-2"),
        ]
        let pending = PendingFile(name: "notes.txt", type: "text/plain", data: Data("hello".utf8))
        let stack = VStack(alignment: .leading, spacing: 16) {
            FileAttachmentChip(file: files[0], padService: env.service)
            FileAttachmentsGrid(files: files, padService: env.service)
            PendingFileChip(file: pending, onRemove: {})
        }.padding()
        assertViewSnapshot(of: stack, named: "components", size: CGSize(width: 402, height: 320))
    }

    @Test func filePreviewSheetRendersOnly() {
        // Hosts a WKWebView (async paint) — render-only.
        ViewRender.assertRenders(
            FilePreviewSheet(data: Data("hello preview".utf8), mimeType: "text/plain",
                             fileName: "notes.txt"))
    }

    @Test func fileIconHelperMappings() {
        #expect(FileIconHelper.icon(for: "application/pdf") != FileIconHelper.icon(for: "image/jpeg"))
        #expect(!FileIconHelper.icon(for: "application/x-unknown-blob").isEmpty)   // fallback icon
        #expect(FileIconHelper.formatSize(0) != "")
        #expect(FileIconHelper.formatSize(82_944).contains("K") || FileIconHelper.formatSize(82_944).lowercased().contains("kb"))
    }
}
}
