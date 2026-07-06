//
//  ScratchpadStore.swift
//  Groo
//
//  Phase 7 extraction of ScratchpadView's state/logic: loading, selection,
//  debounced auto-save, CRUD, file-attachment bookkeeping, and real-time
//  WebSocket handling. Behavior-identical to the former view functions;
//  the view owns only WebKit/picker plumbing.
//

import Foundation
import os

@MainActor
@Observable
final class ScratchpadStore {
    struct PendingUpload {
        let name: String
        let type: String
        let data: Data
    }

    private(set) var allPads: [DecryptedScratchpad] = []
    var selectedPad: DecryptedScratchpad?
    private(set) var isLoading = true
    private(set) var error: String?
    private(set) var isSaving = false
    private(set) var saveFailed = false
    private(set) var lastSavedContent: String = ""
    var actionError: String?
    private(set) var loadWarning: String?
    private(set) var isCreating = false
    private(set) var isUploadingFile = false
    private(set) var isWebSocketConnected = false
    private(set) var saveTask: Task<Void, Never>?
    private(set) var webSocketService: WebSocketService?

    /// Assigned by the hosting view — pushes content into the WKWebView
    /// editor. Tests assign a recorder.
    var setEditorContent: (String) -> Void = { _ in }

    private let padService: PadService
    private let syncService: SyncService
    private let makeWebSocket: @MainActor () -> WebSocketService
    private let saveDebounce: Duration

    init(
        padService: PadService,
        syncService: SyncService,
        makeWebSocket: @escaping @MainActor () -> WebSocketService,
        saveDebounce: Duration = .milliseconds(500)
    ) {
        self.padService = padService
        self.syncService = syncService
        self.makeWebSocket = makeWebSocket
        self.saveDebounce = saveDebounce
    }

    func dismissLoadWarning() {
        loadWarning = nil
    }

    // MARK: - Data Loading

    func loadAllScratchpads() async {
        isLoading = true
        error = nil

        // Ensure we have synced data
        await syncService.sync()

        // Get all scratchpads
        let encryptedPads = syncService.getEncryptedScratchpads()

        var decrypted: [DecryptedScratchpad] = []
        var failedCount = 0
        for encryptedPad in encryptedPads {
            do {
                decrypted.append(try padService.decryptScratchpad(encryptedPad))
            } catch {
                failedCount += 1
                Log.scratchpad.error("Failed to decrypt scratchpad \(encryptedPad.id): \(String(describing: error))")
            }
        }

        // Distinguish decrypt failures from an empty list
        loadWarning = failedCount > 0
            ? "\(failedCount) scratchpad\(failedCount == 1 ? "" : "s") couldn't be decrypted"
            : nil

        // Sort by updatedAt descending
        allPads = decrypted.sorted { $0.updatedAt > $1.updatedAt }

        // Don't auto-select - let user tap to open a pad

        isLoading = false
    }

    // MARK: - Pad Selection

    func selectPad(_ pad: DecryptedScratchpad) {
        // Save any pending changes before switching
        saveTask?.cancel()

        selectedPad = pad
        lastSavedContent = pad.content

        // Update webview content
        setEditorContent(pad.content)
    }

    /// Reset saved-content tracking when the editor switches pads.
    func resetSavedContent(to content: String) {
        lastSavedContent = content
    }

    // MARK: - Create Pad

    func createPad() async {
        isCreating = true

        do {
            let newId = try await syncService.createScratchpad(
                encryptedContent: padService.encryptScratchpadContent("# New Scratchpad\n")
            )

            // Reload to get the new pad
            await loadAllScratchpads()

            // Select the new pad
            if let newPad = allPads.first(where: { $0.id == newId }) {
                selectPad(newPad)
            }
        } catch {
            Log.scratchpad.error("Create failed: \(String(describing: error))")
            actionError = "Couldn't create scratchpad: \(error.localizedDescription)"
        }

        isCreating = false
    }

    // MARK: - Delete Pad

    func deletePad(_ pad: DecryptedScratchpad) async {
        do {
            try await syncService.deleteScratchpad(id: pad.id)

            // Remove from local list
            allPads.removeAll { $0.id == pad.id }

            // Select another pad if we deleted the selected one
            if selectedPad?.id == pad.id {
                selectedPad = allPads.first
                if let newPad = selectedPad {
                    lastSavedContent = newPad.content
                    setEditorContent(newPad.content)
                }
            }
        } catch {
            Log.scratchpad.error("Delete failed for pad \(pad.id): \(String(describing: error))")
            actionError = "Couldn't delete scratchpad: \(error.localizedDescription)"
        }
    }

    // MARK: - Content Changes

    func handleContentChange(_ newContent: String, padId: String) {
        // Skip if content hasn't actually changed
        guard newContent != lastSavedContent else { return }

        // Update local state
        if let index = allPads.firstIndex(where: { $0.id == padId }) {
            allPads[index].content = newContent
        }
        if selectedPad?.id == padId {
            selectedPad?.content = newContent
        }

        // Cancel any pending save
        saveTask?.cancel()

        // Debounce save (500ms in production; tests inject .zero)
        saveTask = Task {
            try? await Task.sleep(for: saveDebounce)

            guard !Task.isCancelled else { return }

            await saveContent(newContent, padId: padId)
        }
    }

    private func saveContent(_ content: String, padId: String) async {
        isSaving = true

        do {
            let encrypted = try padService.encryptScratchpadContent(content)
            try await syncService.updateScratchpad(id: padId, encryptedContent: encrypted)
            lastSavedContent = content
            saveFailed = false
        } catch {
            // Leave lastSavedContent untouched so the next edit retries the save
            Log.scratchpad.error("Save failed for pad \(padId): \(String(describing: error))")
            saveFailed = true
        }

        isSaving = false
    }

    // MARK: - File Attachments

    func uploadFiles(_ uploads: [PendingUpload], to pad: DecryptedScratchpad) async {
        guard !uploads.isEmpty else { return }
        isUploadingFile = true
        for upload in uploads {
            await uploadFile(name: upload.name, type: upload.type, data: upload.data, to: pad)
        }
        isUploadingFile = false
    }

    private func uploadFile(name: String, type: String, data: Data, to pad: DecryptedScratchpad) async {
        do {
            // Upload the file
            let attachment = try await padService.uploadFile(name: name, type: type, data: data)

            // Add to scratchpad
            try await syncService.addFileToScratchpad(id: pad.id, file: attachment)

            // Update local state
            let decryptedFile = DecryptedFileAttachment(
                id: attachment.id,
                name: name,
                type: type,
                size: attachment.size,
                r2Key: attachment.r2Key
            )

            if let index = allPads.firstIndex(where: { $0.id == pad.id }) {
                var updatedFiles = allPads[index].files
                updatedFiles.append(decryptedFile)
                allPads[index] = DecryptedScratchpad(
                    id: allPads[index].id,
                    content: allPads[index].content,
                    files: updatedFiles,
                    createdAt: Int(allPads[index].createdAt.timeIntervalSince1970 * 1000),
                    updatedAt: Int(Date().timeIntervalSince1970 * 1000)
                )

                if selectedPad?.id == pad.id {
                    selectedPad = allPads[index]
                }
            }

            Log.scratchpad.info("File uploaded: \(name)")
        } catch {
            Log.scratchpad.error("File upload failed for \(name): \(String(describing: error))")
            actionError = "Couldn't upload \(name): \(error.localizedDescription)"
        }
    }

    // MARK: - WebSocket

    func setupWebSocket() async {
        let ws = makeWebSocket()
        ws.onScratchpadUpdated = { [weak self] id in
            Task { await self?.remoteScratchpadUpdated(id: id) }
        }
        ws.onScratchpadCreated = { [weak self] _ in
            Task { await self?.loadAllScratchpads() }
        }
        ws.onScratchpadDeleted = { [weak self] id in
            self?.remoteScratchpadDeleted(id: id)
        }
        ws.onConnected = { [weak self] in
            self?.isWebSocketConnected = true
            Log.scratchpad.info("WebSocket connected")
        }
        ws.onDisconnected = { [weak self] (error: Error?) in
            self?.isWebSocketConnected = false
            if let error = error {
                Log.scratchpad.error("WebSocket disconnected: \(String(describing: error))")
            } else {
                Log.scratchpad.info("WebSocket disconnected")
            }
        }
        await ws.connect()
        webSocketService = ws
    }

    func disconnect() {
        webSocketService?.disconnect()
    }

    /// Handle real-time update from another device
    func remoteScratchpadUpdated(id: String) async {
        // Don't refresh if we're currently editing this pad
        if selectedPad?.id == id && isSaving {
            return
        }

        // Sync first to get latest data
        await syncService.sync()

        // Refresh the specific scratchpad
        if let encryptedPad = syncService.getEncryptedScratchpad(id: id) {
            let decrypted: DecryptedScratchpad
            do {
                decrypted = try padService.decryptScratchpad(encryptedPad)
            } catch {
                Log.scratchpad.error("Failed to decrypt remote update for pad \(id): \(String(describing: error))")
                return
            }

            if let index = allPads.firstIndex(where: { $0.id == id }) {
                allPads[index] = decrypted
            }

            // If this is the selected pad, update the editor
            if selectedPad?.id == id {
                selectedPad = decrypted
                lastSavedContent = decrypted.content
                setEditorContent(decrypted.content)
            }
        }
    }

    /// Handle scratchpad deleted on another device
    func remoteScratchpadDeleted(id: String) {
        allPads.removeAll { $0.id == id }

        if selectedPad?.id == id {
            selectedPad = allPads.first
            if let newPad = selectedPad {
                lastSavedContent = newPad.content
                setEditorContent(newPad.content)
            }
        }
    }
}
