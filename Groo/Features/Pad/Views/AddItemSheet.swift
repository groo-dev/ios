//
//  AddItemSheet.swift
//  Groo
//
//  Sheet for adding new Pad items with text and file attachments.
//

import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import UIKit
import os

struct AddItemSheet: View {
    @Environment(\.dismiss) private var dismiss

    let padService: PadService
    let syncService: SyncService

    @State private var text = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var pendingFiles: [PendingFile] = []
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var showFilePicker = false
    @State private var showCamera = false
    @State private var showAttachmentMenu = false
    @FocusState private var isTextFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Text input
                TextEditor(text: $text)
                    .focused($isTextFocused)
                    .padding(Theme.Spacing.sm)
                    .scrollContentBackground(.hidden)
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
                    .padding(.horizontal)
                    .padding(.top)

                // Pending files preview
                if !pendingFiles.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: Theme.Spacing.sm) {
                            ForEach(pendingFiles) { file in
                                PendingFileChip(file: file) {
                                    withAnimation {
                                        pendingFiles.removeAll { $0.id == file.id }
                                    }
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                    .padding(.top, Theme.Spacing.md)
                }

                if let error = errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.horizontal)
                        .padding(.top, Theme.Spacing.sm)
                }

                Spacer()
            }
            .navigationTitle("Add Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        submit()
                    } label: {
                        if isSubmitting {
                            ProgressView()
                        } else {
                            Text("Add")
                                .fontWeight(.semibold)
                        }
                    }
                    .disabled(!canSubmit || isSubmitting)
                }

                // Keyboard accessory
                ToolbarItemGroup(placement: .keyboard) {
                    Button {
                        pasteFromClipboard()
                    } label: {
                        Image(systemName: "doc.on.clipboard")
                    }

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
                        Image(systemName: "paperclip")
                    }

                    Button {
                        showCamera = true
                    } label: {
                        Image(systemName: "camera")
                    }

                    Spacer()

                    Button {
                        isTextFocused = false
                    } label: {
                        Image(systemName: "keyboard.chevron.compact.down")
                    }
                }
            }
            .onAppear {
                isTextFocused = true
            }
            .onChange(of: selectedPhotos) { _, newItems in
                Task {
                    await loadSelectedPhotos(newItems)
                    selectedPhotos = []
                }
            }
            .fileImporter(
                isPresented: $showFilePicker,
                allowedContentTypes: [.item],
                allowsMultipleSelection: true
            ) { result in
                handleFileImport(result)
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraPicker { image in
                    handleCameraImage(image)
                }
                .ignoresSafeArea()
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(canSubmit)
    }

    private var canSubmit: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !pendingFiles.isEmpty
    }

    private func loadSelectedPhotos(_ items: [PhotosPickerItem]) async {
        var failedCount = 0

        for item in items {
            let data: Data?
            do {
                data = try await item.loadTransferable(type: Data.self)
            } catch {
                Log.pad.error("Failed to load selected photo: \(String(describing: error))")
                failedCount += 1
                continue
            }

            guard let data else {
                Log.pad.error("Selected photo returned no data")
                failedCount += 1
                continue
            }

            let mimeType: String
            let fileName: String

            if let uti = item.supportedContentTypes.first {
                mimeType = uti.preferredMIMEType ?? "application/octet-stream"
                let ext = uti.preferredFilenameExtension ?? "bin"
                fileName = "photo_\(Date().timeIntervalSince1970).\(ext)"
            } else {
                mimeType = "image/jpeg"
                fileName = "photo_\(Date().timeIntervalSince1970).jpg"
            }

            let pendingFile = PendingFile(name: fileName, type: mimeType, data: data)
            await MainActor.run {
                withAnimation {
                    pendingFiles.append(pendingFile)
                }
            }
        }

        if failedCount > 0 {
            await MainActor.run {
                errorMessage = "\(failedCount) photo\(failedCount == 1 ? "" : "s") couldn't be loaded"
            }
        }
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            for url in urls {
                guard url.startAccessingSecurityScopedResource() else {
                    Log.pad.error("Skipped imported file (security-scoped access denied): \(url.lastPathComponent)")
                    errorMessage = "Couldn't access \(url.lastPathComponent)"
                    continue
                }
                defer { url.stopAccessingSecurityScopedResource() }

                do {
                    let data = try Data(contentsOf: url)
                    let fileName = url.lastPathComponent
                    let mimeType = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"

                    let pendingFile = PendingFile(name: fileName, type: mimeType, data: data)
                    withAnimation {
                        pendingFiles.append(pendingFile)
                    }
                } catch {
                    Log.pad.error("Failed to read imported file \(url.lastPathComponent): \(String(describing: error))")
                    errorMessage = "Couldn't read \(url.lastPathComponent)"
                }
            }
        case .failure(let error):
            Log.pad.error("File import failed: \(String(describing: error))")
            errorMessage = error.localizedDescription
        }
    }

    private func handleCameraImage(_ image: UIImage) {
        guard let data = image.jpegData(compressionQuality: 0.8) else {
            Log.pad.error("Failed to encode camera image as JPEG")
            errorMessage = "Couldn't process camera photo"
            return
        }
        let fileName = "camera_\(Date().timeIntervalSince1970).jpg"
        let pendingFile = PendingFile(name: fileName, type: "image/jpeg", data: data)
        withAnimation {
            pendingFiles.append(pendingFile)
        }
    }

    private func pasteFromClipboard() {
        let pasteboard = UIPasteboard.general

        // Handle text - append to existing text
        if let string = pasteboard.string, !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if text.isEmpty {
                text = string.trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                text += "\n" + string.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        // Handle images
        if let images = pasteboard.images {
            for (index, image) in images.enumerated() {
                if let data = image.jpegData(compressionQuality: 0.8) {
                    let fileName = "pasted_\(Date().timeIntervalSince1970)_\(index).jpg"
                    let pendingFile = PendingFile(name: fileName, type: "image/jpeg", data: data)
                    withAnimation {
                        pendingFiles.append(pendingFile)
                    }
                } else {
                    Log.pad.error("Failed to encode pasted image \(index) as JPEG")
                }
            }
        }

        // Handle file URLs (from Files app)
        if let urls = pasteboard.urls {
            for url in urls {
                guard url.startAccessingSecurityScopedResource() else {
                    Log.pad.error("Skipped pasted file (security-scoped access denied): \(url.lastPathComponent)")
                    continue
                }
                defer { url.stopAccessingSecurityScopedResource() }

                do {
                    let data = try Data(contentsOf: url)
                    let fileName = url.lastPathComponent
                    let mimeType = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
                    let pendingFile = PendingFile(name: fileName, type: mimeType, data: data)
                    withAnimation {
                        pendingFiles.append(pendingFile)
                    }
                } catch {
                    Log.pad.error("Failed to read pasted file \(url.lastPathComponent): \(String(describing: error))")
                }
            }
        }
    }

    private func submit() {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canSubmit else { return }

        isSubmitting = true
        errorMessage = nil

        Task {
            do {
                // Upload files first
                var uploadedFiles: [PadFileAttachment] = []
                for file in pendingFiles {
                    let attachment = try await padService.uploadFile(
                        name: file.name,
                        type: file.type,
                        data: file.data
                    )
                    uploadedFiles.append(attachment)
                }

                // Create encrypted item with files
                let encryptedItem = try padService.createEncryptedItem(text: trimmedText, files: uploadedFiles)
                await syncService.addItem(encryptedItem)

                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                isSubmitting = false
            }
        }
    }
}

// MARK: - Camera Picker

struct CameraPicker: UIViewControllerRepresentable {
    let onCapture: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker

        init(_ parent: CameraPicker) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.onCapture(image)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

#Preview {
    AddItemSheet(
        padService: PadService(api: APIClient(baseURL: Config.padAPIBaseURL)),
        syncService: SyncService(api: APIClient(baseURL: Config.padAPIBaseURL))
    )
}
