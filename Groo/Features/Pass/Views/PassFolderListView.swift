//
//  PassFolderListView.swift
//  Groo
//
//  View for managing vault folders (create, rename, delete).
//

import SwiftUI

struct PassFolderListView: View {
    let passService: PassService
    let onDismiss: () -> Void
    let onSelectFolder: (PassFolder?) -> Void

    @State private var showingNewFolder = false
    @State private var editingFolder: PassFolder?
    @State private var newFolderName = ""
    @State private var editFolderName = ""

    var body: some View {
        NavigationStack {
            List {
                // All items row
                Button {
                    onSelectFolder(nil)
                } label: {
                    Label("All Items", systemImage: "tray.full")
                }
                .foregroundStyle(.primary)

                // Folders
                Section("Folders") {
                    if passService.folders.isEmpty {
                        Text("No folders yet")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(passService.folders) { folder in
                            folderRow(folder)
                        }
                    }
                }
            }
            .navigationTitle("Folders")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") {
                        onDismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        newFolderName = ""
                        showingNewFolder = true
                    } label: {
                        Image(systemName: "folder.badge.plus")
                    }
                }
            }
            .alert("New Folder", isPresented: $showingNewFolder) {
                TextField("Folder name", text: $newFolderName)
                Button("Cancel", role: .cancel) {}
                Button("Create") {
                    createFolder()
                }
                .disabled(newFolderName.trimmingCharacters(in: .whitespaces).isEmpty)
            } message: {
                Text("Enter a name for the new folder")
            }
            .alert("Rename Folder", isPresented: .init(
                get: { editingFolder != nil },
                set: { if !$0 { editingFolder = nil } }
            )) {
                TextField("Folder name", text: $editFolderName)
                Button("Cancel", role: .cancel) {
                    editingFolder = nil
                }
                Button("Save") {
                    renameFolder()
                }
                .disabled(editFolderName.trimmingCharacters(in: .whitespaces).isEmpty)
            } message: {
                Text("Enter a new name for the folder")
            }
        }
    }

    private func folderRow(_ folder: PassFolder) -> some View {
        HStack {
            Label(folder.name, systemImage: "folder")

            Spacer()

            Text("\(itemCount(for: folder))")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onSelectFolder(folder)
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                deleteFolder(folder)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .swipeActions(edge: .leading) {
            Button {
                editFolderName = folder.name
                editingFolder = folder
            } label: {
                Label("Rename", systemImage: "pencil")
            }
            .tint(.orange)
        }
        .contextMenu {
            Button {
                editFolderName = folder.name
                editingFolder = folder
            } label: {
                Label("Rename", systemImage: "pencil")
            }

            Button(role: .destructive) {
                deleteFolder(folder)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private func itemCount(for folder: PassFolder) -> Int {
        passService.getItemsInFolder(folder.id).count
    }

    private func createFolder() {
        let name = newFolderName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }

        let folder = PassFolder(
            id: UUID().uuidString.lowercased(),
            name: name,
            parentId: nil
        )

        Task {
            try? await passService.addFolder(folder)
        }
    }

    private func renameFolder() {
        guard var folder = editingFolder else { return }
        let name = editFolderName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }

        folder.name = name

        Task {
            try? await passService.updateFolder(folder)
            editingFolder = nil
        }
    }

    private func deleteFolder(_ folder: PassFolder) {
        Task {
            try? await passService.deleteFolder(folder)
        }
    }
}

#Preview {
    PassFolderListView(
        passService: PassService(),
        onDismiss: {},
        onSelectFolder: { _ in }
    )
}
