//
//  ScratchpadListView.swift
//  Groo
//
//  Sidebar list of scratchpads with create/delete support.
//

import SwiftUI

struct ScratchpadListView: View {
    let pads: [DecryptedScratchpad]
    let selectedId: String?
    let onSelect: (DecryptedScratchpad) -> Void
    let onDelete: (DecryptedScratchpad) -> Void
    let onCreate: () -> Void

    var body: some View {
        List {
            ForEach(pads) { pad in
                ScratchpadRow(
                    pad: pad,
                    isSelected: pad.id == selectedId
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    onSelect(pad)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        onDelete(pad)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        .listStyle(.plain)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: onCreate) {
                    Image(systemName: "square.and.pencil")
                }
            }
        }
    }
}

// MARK: - Scratchpad Row

struct ScratchpadRow: View {
    let pad: DecryptedScratchpad
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(pad.title)
                .font(.headline)
                .lineLimit(1)

            Text(previewText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            Text(pad.updatedAt, style: .relative)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
        .listRowBackground(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
    }

    private var previewText: String {
        // Get content after first line (title)
        let lines = pad.content.split(separator: "\n", omittingEmptySubsequences: false)
        if lines.count > 1 {
            let preview = lines.dropFirst().joined(separator: " ").trimmingCharacters(in: .whitespaces)
            return preview.isEmpty ? "No additional content" : preview
        }
        return "No additional content"
    }
}

#Preview {
    NavigationStack {
        ScratchpadListView(
            pads: [
                DecryptedScratchpad(
                    id: "1",
                    content: "# Meeting Notes\nDiscussed project timeline",
                    files: [],
                    createdAt: Int(Date().timeIntervalSince1970 * 1000),
                    updatedAt: Int(Date().timeIntervalSince1970 * 1000)
                ),
                DecryptedScratchpad(
                    id: "2",
                    content: "# Ideas\nNew feature brainstorm",
                    files: [],
                    createdAt: Int(Date().timeIntervalSince1970 * 1000),
                    updatedAt: Int(Date().timeIntervalSince1970 * 1000) - 3600000
                )
            ],
            selectedId: "1",
            onSelect: { _ in },
            onDelete: { _ in },
            onCreate: {}
        )
        .navigationTitle("Scratchpads")
    }
}
