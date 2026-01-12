//
//  QuickInputBar.swift
//  Groo
//
//  Floating action buttons for quick item creation.
//

import SwiftUI
import UniformTypeIdentifiers

struct PadFABButtons: View {
    let padService: PadService
    let syncService: SyncService
    let onAddItem: () -> Void
    let onItemAdded: () -> Void

    @State private var toastState = ToastState()
    @State private var isCreating = false

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            // Paste button (secondary)
            Button {
                pasteFromClipboard()
            } label: {
                ZStack {
                    Image(systemName: "doc.on.clipboard")
                        .font(.title3)
                        .fontWeight(.medium)
                        .opacity(isCreating ? 0 : 1)

                    if isCreating {
                        ProgressView()
                            .scaleEffect(0.8)
                    }
                }
                .foregroundStyle(.tint)
                .frame(width: 50, height: 50)
                .background(.thinMaterial)
                .clipShape(Circle())
                .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
            }
            .disabled(isCreating)

            // Add button (primary, opens sheet)
            Button(action: onAddItem) {
                Image(systemName: "plus")
                    .font(.title3)
                    .fontWeight(.medium)
                    .foregroundStyle(.white)
                    .frame(width: 50, height: 50)
                    .background(.tint)
                    .clipShape(Circle())
                    .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)
            }
        }
        .padding(.trailing, Theme.Spacing.lg)
        .padding(.bottom, Theme.Spacing.lg)
        .toast(isPresented: $toastState.isPresented, message: toastState.message, style: toastState.style)
    }

    private func pasteFromClipboard() {
        let pasteboard = UIPasteboard.general

        // Check what's in clipboard
        let hasText = pasteboard.hasStrings
        let hasImages = pasteboard.hasImages
        let hasURLs = pasteboard.hasURLs

        guard hasText || hasImages || hasURLs else {
            toastState.showError("Clipboard is empty")
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            return
        }

        isCreating = true

        Task {
            do {
                var text = ""
                var files: [PadFileAttachment] = []

                // Handle text
                if let string = pasteboard.string, !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    text = string.trimmingCharacters(in: .whitespacesAndNewlines)
                }

                // Handle images
                if let images = pasteboard.images {
                    for (index, image) in images.enumerated() {
                        if let data = image.jpegData(compressionQuality: 0.8) {
                            let fileName = "pasted_\(Date().timeIntervalSince1970)_\(index).jpg"
                            let attachment = try await padService.uploadFile(
                                name: fileName,
                                type: "image/jpeg",
                                data: data
                            )
                            files.append(attachment)
                        }
                    }
                }

                // Handle file URLs (from Files app)
                if let urls = pasteboard.urls {
                    for url in urls {
                        guard url.startAccessingSecurityScopedResource() else { continue }
                        defer { url.stopAccessingSecurityScopedResource() }

                        if let data = try? Data(contentsOf: url) {
                            let fileName = url.lastPathComponent
                            let mimeType = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
                            let attachment = try await padService.uploadFile(
                                name: fileName,
                                type: mimeType,
                                data: data
                            )
                            files.append(attachment)
                        }
                    }
                }

                // Create item if we have content
                guard !text.isEmpty || !files.isEmpty else {
                    await MainActor.run {
                        toastState.showError("Nothing to paste")
                        isCreating = false
                    }
                    return
                }

                let item = try padService.createEncryptedItem(text: text, files: files)
                await syncService.addItem(item)

                await MainActor.run {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    toastState.show("Item added", style: .success)
                    isCreating = false
                    onItemAdded()
                }
            } catch {
                await MainActor.run {
                    toastState.showError("Failed to create item")
                    isCreating = false
                }
            }
        }
    }
}

#Preview {
    ZStack(alignment: .bottomTrailing) {
        Color.gray.opacity(0.1).ignoresSafeArea()
        PadFABButtons(
            padService: PadService(api: APIClient(baseURL: Config.padAPIBaseURL)),
            syncService: SyncService(api: APIClient(baseURL: Config.padAPIBaseURL)),
            onAddItem: {},
            onItemAdded: {}
        )
    }
    .tint(Theme.Brand.primary)
}
