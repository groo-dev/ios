//
//  ScratchpadView.swift
//  Groo
//
//  Main scratchpad container with list and editor. State/logic lives in
//  ScratchpadStore (Phase 7 extraction); this view owns only the WebKit
//  editor plumbing and the photo/file picker UI.
//

import SwiftUI
import WebKit
import PhotosUI
import UniformTypeIdentifiers
import os

struct ScratchpadView: View {
    let padService: PadService
    let syncService: SyncService
    /// Test seam: inject a pre-built (possibly pre-loaded) store. Production
    /// leaves this nil and resolves one with a real WebSocket factory.
    var store: ScratchpadStore? = nil

    @Environment(AuthService.self) private var authService
    @State private var resolvedStore: ScratchpadStore?

    var body: some View {
        Group {
            if let resolvedStore {
                ScratchpadContentView(store: resolvedStore, padService: padService)
            } else {
                Color.clear
            }
        }
        .onAppear {
            guard resolvedStore == nil else { return }
            if let store {
                resolvedStore = store
            } else {
                let auth = authService
                resolvedStore = ScratchpadStore(
                    padService: padService,
                    syncService: syncService,
                    makeWebSocket: { WebSocketService(authService: auth) }
                )
            }
        }
    }
}

private struct ScratchpadContentView: View {
    @Bindable var store: ScratchpadStore
    let padService: PadService

    @State private var webView: WKWebView?
    @State private var showDeleteConfirmation = false
    @State private var padToDelete: DecryptedScratchpad?

    // File attachment state
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var showFilePicker = false

    // For iPad split view
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.isPushedDestination) private var isPushedDestination

    /// The regular-width branch never had a NavigationStack of its own; the
    /// host supplies one now, so it suppresses the bar it would inherit —
    /// but only when rendering as a tab root. Applied here, at the level
    /// that composes all four body states (loading/error/empty/content),
    /// not just the loaded contentView branch: isLoading defaults to true,
    /// so every iPad visit hits loadingView first, and an empty or
    /// permanently failed load never reaches contentView at all. Gated by
    /// horizontalSizeClass rather than idiom, so also skipped when pushed
    /// from More — a Max-size iPhone in landscape reports .regular too, and
    /// a pushed screen needs its back button visible.
    private var suppressesNavigationBar: Bool {
        horizontalSizeClass == .regular && !isPushedDestination
    }

    var body: some View {
        Group {
            if store.isLoading {
                loadingView
            } else if let error = store.error {
                errorView(error)
            } else if store.allPads.isEmpty {
                emptyView
            } else {
                contentView
            }
        }
        .toolbar(suppressesNavigationBar ? .hidden : .visible, for: .navigationBar)
        .task {
            store.setEditorContent = { [bind = $webView] content in
                bind.wrappedValue?.evaluateJavaScript(EditorCommand.setContent(content).jsCall) { _, error in
                    if let error = error {
                        Log.scratchpad.error("Failed to set editor content: \(error.localizedDescription)")
                    }
                }
            }
            await store.loadAllScratchpads()
            await store.setupWebSocket()
        }
        .onDisappear {
            store.disconnect()
        }
        .safeAreaInset(edge: .top) {
            if let warning = store.loadWarning {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text(warning)
                    Spacer()
                    Button {
                        store.dismissLoadWarning()
                    } label: {
                        Image(systemName: "xmark")
                    }
                }
                .font(.caption)
                .foregroundStyle(.orange)
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial)
            }
        }
        .alert(
            "Something Went Wrong",
            isPresented: Binding(
                get: { store.actionError != nil },
                set: { if !$0 { store.actionError = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.actionError ?? "")
        }
        .confirmationDialog(
            "Delete Scratchpad",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let pad = padToDelete {
                    Task {
                        await store.deletePad(pad)
                        padToDelete = nil
                    }
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
                    pads: store.allPads,
                    selectedId: store.selectedPad?.id,
                    onSelect: store.selectPad,
                    onDelete: confirmDelete,
                    onCreate: { Task { await store.createPad() } }
                )
                .frame(width: 280)

                Divider()

                // Editor
                if let pad = store.selectedPad {
                    editorView(pad)
                } else {
                    noSelectionView
                }
            }
        } else {
            // iPhone: Navigation-based layout. The stack is the host's; the
            // destination registers against it.
            ScratchpadListView(
                pads: store.allPads,
                selectedId: store.selectedPad?.id,
                onSelect: store.selectPad,
                onDelete: confirmDelete,
                onCreate: { Task { await store.createPad() } }
            )
            .navigationTitle("Scratchpads")
            .navigationDestination(item: $store.selectedPad) { pad in
                editorView(pad)
                    .navigationTitle(pad.title)
                    .navigationBarTitleDisplayMode(.inline)
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
                Task { await store.loadAllScratchpads() }
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
                Task { await store.createPad() }
            } label: {
                Label("New Scratchpad", systemImage: "square.and.pencil")
            }
            .buttonStyle(.bordered)
            .disabled(store.isCreating)
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
                        store.handleContentChange(newContent, padId: pad.id)
                    },
                    onReady: {
                        Log.scratchpad.info("Editor ready for pad: \(pad.id)")
                    },
                    onError: { errorMessage in
                        Log.scratchpad.error("Editor error: \(errorMessage)")
                    },
                    webView: $webView
                )

                // Status indicator
                HStack(spacing: 8) {
                    // Sync indicator
                    if store.isSaving || store.isUploadingFile {
                        HStack(spacing: 6) {
                            ProgressView()
                                .scaleEffect(0.7)
                            Text(store.isUploadingFile ? "Uploading..." : "Saving...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else if store.saveFailed {
                        // Save failure - distinct from offline so data loss is visible
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 6, height: 6)
                            Text("Save failed")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    } else {
                        // Connection status
                        HStack(spacing: 4) {
                            Circle()
                                .fill(store.isWebSocketConnected ? Color.green : Color.orange)
                                .frame(width: 6, height: 6)
                            Text(store.isWebSocketConnected ? "Synced" : "Offline")
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
                .disabled(store.isUploadingFile)

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
            store.resetSavedContent(to: pad.content)
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

    // MARK: - File Attachment Handling (data collection only — uploads live in the store)

    private func loadSelectedPhotos(_ items: [PhotosPickerItem], for pad: DecryptedScratchpad) async {
        guard !items.isEmpty else { return }

        var uploads: [ScratchpadStore.PendingUpload] = []
        var failedCount = 0

        for item in items {
            let data: Data?
            do {
                data = try await item.loadTransferable(type: Data.self)
            } catch {
                Log.scratchpad.error("Failed to load selected photo: \(String(describing: error))")
                failedCount += 1
                continue
            }

            guard let data else {
                Log.scratchpad.error("Selected photo returned no data")
                failedCount += 1
                continue
            }

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

            uploads.append(ScratchpadStore.PendingUpload(name: fileName, type: mimeType, data: data))
        }

        if failedCount > 0 {
            store.actionError = "\(failedCount) photo\(failedCount == 1 ? "" : "s") couldn't be loaded"
        }

        await store.uploadFiles(uploads, to: pad)
    }

    private func handleFileImport(_ result: Result<[URL], Error>, for pad: DecryptedScratchpad) {
        switch result {
        case .success(let urls):
            Task {
                var uploads: [ScratchpadStore.PendingUpload] = []
                var failedCount = 0

                for url in urls {
                    guard url.startAccessingSecurityScopedResource() else {
                        Log.scratchpad.error("Skipped imported file (security-scoped access denied): \(url.lastPathComponent)")
                        failedCount += 1
                        continue
                    }
                    defer { url.stopAccessingSecurityScopedResource() }

                    do {
                        let data = try Data(contentsOf: url)
                        let fileName = url.lastPathComponent
                        let mimeType = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
                        uploads.append(ScratchpadStore.PendingUpload(name: fileName, type: mimeType, data: data))
                    } catch {
                        Log.scratchpad.error("Failed to read imported file \(url.lastPathComponent): \(String(describing: error))")
                        failedCount += 1
                    }
                }

                if failedCount > 0 {
                    store.actionError = "\(failedCount) file\(failedCount == 1 ? "" : "s") couldn't be read"
                }

                await store.uploadFiles(uploads, to: pad)
            }
        case .failure(let error):
            Log.scratchpad.error("File import failed: \(String(describing: error))")
            store.actionError = error.localizedDescription
        }
    }

    private func confirmDelete(_ pad: DecryptedScratchpad) {
        padToDelete = pad
        showDeleteConfirmation = true
    }
}

// MARK: - Hashable conformance for navigationDestination

extension DecryptedScratchpad: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

#Preview {
    NavigationStack {
        ScratchpadView(
            padService: PadService(api: APIClient(baseURL: Config.padAPIBaseURL)),
            syncService: SyncService(api: APIClient(baseURL: Config.padAPIBaseURL))
        )
    }
    .environment(AuthService())
}
