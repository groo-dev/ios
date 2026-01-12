//
//  ItemRow.swift
//  Groo
//
//  Individual Pad item row with context menu and file attachments.
//

import SwiftUI

struct ItemRow: View {
    let item: DecryptedListItem
    let padService: PadService
    let onCopy: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            // Text content
            if !item.text.isEmpty {
                Text(item.text)
                    .font(.body)
                    .lineLimit(Theme.LineLimit.itemPreview)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            // File attachments
            if !item.files.isEmpty {
                FileAttachmentsGrid(files: item.files, padService: padService)
            }

            // Footer: timestamp
            Text(item.createdAt, style: .relative)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .rowPadding()
        .contentShape(Rectangle())
        .contextMenu {
            Button {
                onCopy()
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }

            if !item.text.isEmpty {
                ShareLink(item: item.text) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
            }

            Divider()

            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .onTapGesture {
            onCopy()
        }
    }
}

#Preview {
    List {
        ItemRow(
            item: DecryptedListItem(
                id: "1",
                text: "This is a sample item with some text that might be longer",
                files: [
                    DecryptedFileAttachment(
                        id: "f1",
                        name: "document.pdf",
                        type: "application/pdf",
                        size: 1024 * 256,
                        r2Key: "test"
                    ),
                    DecryptedFileAttachment(
                        id: "f2",
                        name: "photo.jpg",
                        type: "image/jpeg",
                        size: 1024 * 1024,
                        r2Key: "test2"
                    )
                ],
                createdAt: Int(Date().timeIntervalSince1970 * 1000)
            ),
            padService: PadService(api: APIClient(baseURL: Config.padAPIBaseURL)),
            onCopy: {},
            onDelete: {}
        )

        ItemRow(
            item: DecryptedListItem(
                id: "2",
                text: "Text only item",
                files: [],
                createdAt: Int(Date().timeIntervalSince1970 * 1000) - 3600000
            ),
            padService: PadService(api: APIClient(baseURL: Config.padAPIBaseURL)),
            onCopy: {},
            onDelete: {}
        )
    }
    .listStyle(.plain)
}
