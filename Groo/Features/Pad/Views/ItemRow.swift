//
//  ItemRow.swift
//  Groo
//
//  Individual Pad item row with copy action.
//

import SwiftUI

struct ItemRow: View {
    let item: DecryptedListItem
    let padService: PadService

    @State private var showCopied = false

    var body: some View {
        Button {
            copyToClipboard()
        } label: {
            HStack(alignment: .top, spacing: Theme.Spacing.md) {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text(item.text)
                        .font(.body)
                        .lineLimit(Theme.LineLimit.itemPreview)
                        .foregroundStyle(.primary)

                    HStack(spacing: Theme.Spacing.sm) {
                        Text(item.createdAt, style: .relative)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if !item.files.isEmpty {
                            Label("\(item.files.count)", systemImage: "paperclip")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Spacer()

                if showCopied {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .rowPadding()
    }

    private func copyToClipboard() {
        padService.copyToClipboard(item.text)
        withAnimation {
            showCopied = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation {
                showCopied = false
            }
        }
    }
}

#Preview {
    List {
        ItemRow(
            item: DecryptedListItem(
                id: "1",
                text: "This is a sample item with some text that might be longer",
                files: [],
                createdAt: Int(Date().timeIntervalSince1970 * 1000)
            ),
            padService: PadService(api: APIClient(baseURL: Config.padAPIBaseURL))
        )
    }
}
