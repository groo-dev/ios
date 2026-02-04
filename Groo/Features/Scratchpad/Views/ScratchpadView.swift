//
//  ScratchpadView.swift
//  Groo
//
//  Main scratchpad container with list and editor.
//  Manages loading, editing, and auto-saving scratchpad content.
//

import SwiftUI
import WebKit
import PhotosUI
import UniformTypeIdentifiers

struct ScratchpadView: View {
    let padService: PadService
    let syncService: SyncService

    @State private var allPads: [DecryptedScratchpad] = []
    @State private var selectedPad: DecryptedScratchpad?
    @State private var isLoading = true
    @State private var error: String?
    @State private var webView: WKWebView?
    @State private var isSaving = false
    @State private var lastSavedContent: String = ""
    @State private var showDeleteConfirmation = false
    @State private var padToDelete: DecryptedScratchpad?
    @State private var isCreating = false

    // Debounce timer for auto-save
    @State private var saveTask: Task<Void, Never>?

    // File attachment state
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var showFilePicker = false
    @State private var isUploadingFile = false

    // Real-time sync
    @State private var webSocketService: WebSocketService?
    @State private var isWebSocketConnected = false

    // For iPad split view
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        Group {
            if isLoading {
                loadingView
            } else if let error = error {
                errorView(error)
            } else if allPads.isEmpty {
                emptyView
            } else {
                contentView
            }
        }
        .task {
            await loadAllScratchpads()
            setupWebSocket()
        }
        .onDisappear {
            webSocketService?.disconnect()
        }
        .confirmationDialog(
            "Delete Scratchpad",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let pad = padToDelete {
                    Task { await deletePad(pad) }
                }
            }
            Button("Cancel", role: .cancel) {
                padToDelete = nil
            }
        } message: {
            Text("This scratchpad will be permanently deleted.")
        }
    }

    // MARK: - Content View

    @ViewBuilder
    private var contentView: some View {
        if horizontalSizeClass == .regular {
            // iPad: Side-by-side layout
            HStack(spacing: 0) {
                // Sidebar
                ScratchpadListView(
                    pads: allPads,
                    selectedId: selectedPad?.id,
                    onSelect: selectPad,
                    onDelete: confirmDelete,
                    onCreate: { Task { await createPad() } }
                )
                .frame(width: 280)

                Divider()

                // Editor
                if let pad = selectedPad {
                    editorView(pad)
                } else {
                    noSelectionView
                }
            }
        } else {
            // iPhone: Navigation-based layout
            NavigationStack {
                ScratchpadListView(
                    pads: allPads,
                    selectedId: selectedPad?.id,
                    onSelect: selectPad,
                    onDelete: confirmDelete,
                    onCreate: { Task { await createPad() } }
                )
                .navigationTitle("Scratchpads")
                .navigationDestination(item: $selectedPad) { pad in
                    editorView(pad)
                        .navigationTitle(pad.title)
                        .navigationBarTitleDisplayMode(.inline)
                }
            }
        }
    }

    // MARK: - Views

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Loading scratchpads...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundStyle(.orange)

            Text("Failed to load scratchpads")
                .font(.headline)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Retry") {
                Task { await loadAllScratchpads() }
            }
            .buttonStyle(.bordered)
        }
        .padding()
    }

    private var emptyView: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("No scratchpads")
                .font(.headline)

            Text("Create your first scratchpad to get started")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button {
                Task { await createPad() }
            } label: {
                Label("New Scratchpad", systemImage: "square.and.pencil")
            }
            .buttonStyle(.bordered)
            .disabled(isCreating)
        }
        .padding()
    }

    private var noSelectionView: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Select a scratchpad")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
    }

    private func editorView(_ pad: DecryptedScratchpad) -> some View {
        VStack(spacing: 0) {
            // Editor
            ZStack(alignment: .bottomTrailing) {
                ScratchpadWebView(
                    initialContent: pad.content,
                    onContentChange: { newContent in
                        handleContentChange(newContent, padId: pad.id)
                    },
                    onReady: {
                        print("[Scratchpad] Editor ready for pad: \(pad.id)")
                    },
                    onError: { errorMessage in
                        print("[Scratchpad] Editor error: \(errorMessage)")
                    },
                    webView: $webView
                )

                // Status indicator
                HStack(spacing: 8) {
                    // Sync indicator
                    if isSaving || isUploadingFile {
                        HStack(spacing: 6) {
                            ProgressView()
                                .scaleEffect(0.7)
                            Text(isUploadingFile ? "Uploading..." : "Saving...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        // Connection status
                        HStack(spacing: 4) {
                            Circle()
                                .fill(isWebSocketConnected ? Color.green : Color.orange)
                                .frame(width: 6, height: 6)
                            Text(isWebSocketConnected ? "Synced" : "Offline")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
                .padding()
            }

            // File attachments section
            if !pad.files.isEmpty {
                Divider()
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(pad.files) { file in
                            FileAttachmentChip(file: file, padService: padService)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                }
                .background(Color(.systemGray6).opacity(0.5))
            }

            // Attachment toolbar
            Divider()
            HStack(spacing: 16) {
                Menu {
                    PhotosPicker(
                        selection: $selectedPhotos,
                        maxSelectionCount: 10,
                        matching: .any(of: [.images, .videos])
                    ) {
                        Label("Photo Library", systemImage: "photo.on.rectangle")
                    }

                    Button {
                        showFilePicker = true
                    } label: {
                        Label("Files", systemImage: "folder")
                    }
                } label: {
                    Label("Attach", systemImage: "paperclip")
                        .font(.subheadline)
                }
                .disabled(isUploadingFile)

                Spacer()

                Text("\(pad.files.count) attachment\(pad.files.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
            .background(Color(.systemGray6).opacity(0.3))
        }
        .onChange(of: pad.id) { _, _ in
            // Reset saved content tracking when switching pads
            lastSavedContent = pad.content
        }
        .onChange(of: selectedPhotos) { _, newItems in
            Task {
                await loadSelectedPhotos(newItems, for: pad)
                selectedPhotos = []
            }
        }
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true
        ) { result in
            handleFileImport(result, for: pad)
        }
    }

    // MARK: - File Attachment Handling

    private func loadSelectedPhotos(_ items: [PhotosPickerItem], for pad: DecryptedScratchpad) async {
        guard !items.isEmpty else { return }

        isUploadingFile = true

        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self) {
                let mimeType: String
                let fileName: String

                if let uti = item.supportedContentTypes.first {
                    mimeType = uti.preferredMIMEType ?? "application/octet-stream"
                    let ext = uti.preferredFilenameExtension ?? "bin"
                    fileName = "photo_\(Int(Date().timeIntervalSince1970)).\(ext)"
                } else {
                    mimeType = "image/jpeg"
                    fileName = "photo_\(Int(Date().timeIntervalSince1970)).jpg"
                }

                await uploadFile(name: fileName, type: mimeType, data: data, to: pad)
            }
        }

        isUploadingFile = false
    }

    private func handleFileImport(_ result: Result<[URL], Error>, for pad: DecryptedScratchpad) {
        switch result {
        case .success(let urls):
            Task {
                isUploadingFile = true

                for url in urls {
                    guard url.startAccessingSecurityScopedResource() else { continue }
                    defer { url.stopAccessingSecurityScopedResource() }

                    if let data = try? Data(contentsOf: url) {
                        let fileName = url.lastPathComponent
                        let mimeType = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
                        await uploadFile(name: fileName, type: mimeType, data: data, to: pad)
                    }
                }

                isUploadingFile = false
            }
        case .failure(let error):
            print("[Scratchpad] File import failed: \(error.localizedDescription)")
        }
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

            print("[Scratchpad] File uploaded: \(name)")
        } catch {
            print("[Scratchpad] File upload failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Data Loading

    private func loadAllScratchpads() async {
        isLoading = true
        error = nil

        // Ensure we have synced data
        await syncService.sync()

        // Get all scratchpads
        let encryptedPads = syncService.getEncryptedScratchpads()

        var decrypted: [DecryptedScratchpad] = []
        for encryptedPad in encryptedPads {
            if let pad = try? padService.decryptScratchpad(encryptedPad) {
                decrypted.append(pad)
            }
        }

        // Sort by updatedAt descending
        allPads = decrypted.sorted { $0.updatedAt > $1.updatedAt }

        // Don't auto-select - let user tap to open a pad

        isLoading = false
    }

    // MARK: - Pad Selection

    private func selectPad(_ pad: DecryptedScratchpad) {
        // Save any pending changes before switching
        saveTask?.cancel()

        selectedPad = pad
        lastSavedContent = pad.content

        // Update webview content
        webView?.evaluateJavaScript(EditorCommand.setContent(pad.content).jsCall, completionHandler: nil)
    }

    // MARK: - Create Pad

    private func createPad() async {
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
            print("[Scratchpad] Create failed: \(error.localizedDescription)")
        }

        isCreating = false
    }

    // MARK: - Delete Pad

    private func confirmDelete(_ pad: DecryptedScratchpad) {
        padToDelete = pad
        showDeleteConfirmation = true
    }

    private func deletePad(_ pad: DecryptedScratchpad) async {
        do {
            try await syncService.deleteScratchpad(id: pad.id)

            // Remove from local list
            allPads.removeAll { $0.id == pad.id }

            // Select another pad if we deleted the selected one
            if selectedPad?.id == pad.id {
                selectedPad = allPads.first
                if let newPad = selectedPad {
                    lastSavedContent = newPad.content
                    webView?.evaluateJavaScript(EditorCommand.setContent(newPad.content).jsCall, completionHandler: nil)
                }
            }
        } catch {
            print("[Scratchpad] Delete failed: \(error.localizedDescription)")
        }

        padToDelete = nil
    }

    // MARK: - Content Changes

    private func handleContentChange(_ newContent: String, padId: String) {
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

        // Debounce save by 500ms
        saveTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000) // 500ms

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
            print("[Scratchpad] Content saved successfully")
        } catch {
            print("[Scratchpad] Save failed: \(error.localizedDescription)")
        }

        isSaving = false
    }

    // MARK: - WebSocket Setup

    private func setupWebSocket() {
        let ws = WebSocketService()
        ws.onScratchpadUpdated = { [self] id in
            handleRemoteScratchpadUpdate(id: id)
        }
        ws.onScratchpadCreated = { [self] id in
            handleRemoteScratchpadCreated(id: id)
        }
        ws.onScratchpadDeleted = { [self] id in
            handleRemoteScratchpadDeleted(id: id)
        }
        ws.onConnected = { [self] in
            isWebSocketConnected = true
            print("[Scratchpad] WebSocket connected")
        }
        ws.onDisconnected = { [self] (_: Error?) in
            isWebSocketConnected = false
            print("[Scratchpad] WebSocket disconnected")
        }
        ws.connect()
        webSocketService = ws
    }

    /// Handle real-time update from another device
    private func handleRemoteScratchpadUpdate(id: String) {
        Task {
            // Don't refresh if we're currently editing this pad
            if selectedPad?.id == id && isSaving {
                return
            }

            // Sync first to get latest data
            await syncService.sync()

            // Refresh the specific scratchpad
            if let encryptedPad = syncService.getEncryptedScratchpad(id: id),
               let decrypted = try? padService.decryptScratchpad(encryptedPad) {

                if let index = allPads.firstIndex(where: { $0.id == id }) {
                    allPads[index] = decrypted
                }

                // If this is the selected pad, update the editor
                if selectedPad?.id == id {
                    selectedPad = decrypted
                    lastSavedContent = decrypted.content
                    webView?.evaluateJavaScript(EditorCommand.setContent(decrypted.content).jsCall, completionHandler: nil)
                }
            }
        }
    }

    /// Handle new scratchpad created on another device
    private func handleRemoteScratchpadCreated(id: String) {
        Task {
            await loadAllScratchpads()
        }
    }

    /// Handle scratchpad deleted on another device
    private func handleRemoteScratchpadDeleted(id: String) {
        allPads.removeAll { $0.id == id }

        if selectedPad?.id == id {
            selectedPad = allPads.first
            if let newPad = selectedPad {
                lastSavedContent = newPad.content
                webView?.evaluateJavaScript(EditorCommand.setContent(newPad.content).jsCall, completionHandler: nil)
            }
        }
    }
}

// MARK: - Hashable conformance for navigationDestination

extension DecryptedScratchpad: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

#Preview {
    ScratchpadView(
        padService: PadService(api: APIClient(baseURL: Config.padAPIBaseURL)),
        syncService: SyncService(api: APIClient(baseURL: Config.padAPIBaseURL))
    )
}
