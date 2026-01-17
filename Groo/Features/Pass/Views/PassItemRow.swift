//
//  PassItemRow.swift
//  Groo
//
//  Row component for displaying a vault item in a list.
//

import SwiftUI

struct PassItemRow: View {
    let item: PassVaultItem
    let onTap: () -> Void
    let onCopyPassword: (() -> Void)?

    init(item: PassVaultItem, onTap: @escaping () -> Void, onCopyPassword: (() -> Void)? = nil) {
        self.item = item
        self.onTap = onTap
        self.onCopyPassword = onCopyPassword
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: Theme.Spacing.md) {
                // Type icon
                Image(systemName: item.type.icon)
                    .font(.title3)
                    .foregroundStyle(Theme.Brand.primary)
                    .frame(width: 32)

                // Item info
                VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                    Text(item.name)
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    // Subtitle based on item type
                    if let subtitle = itemSubtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                // Favorite indicator
                if item.favorite {
                    Image(systemName: "star.fill")
                        .font(.caption)
                        .foregroundStyle(.yellow)
                }

                // Quick copy button for passwords
                if case .password = item, let onCopy = onCopyPassword {
                    Button {
                        onCopy()
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.body)
                            .foregroundStyle(Theme.Brand.primary)
                    }
                    .buttonStyle(.plain)
                }

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, Theme.Spacing.sm)
            .padding(.horizontal, Theme.Spacing.md)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var itemSubtitle: String? {
        switch item {
        case .password(let passwordItem):
            if !passwordItem.username.isEmpty {
                return passwordItem.username
            }
            if let url = passwordItem.urls.first {
                return formatURL(url)
            }
            return nil
        case .card(let cardItem):
            return "•••• \(String(cardItem.number.suffix(4)))"
        case .bankAccount(let bankItem):
            return bankItem.bankName
        case .note:
            return "Secure Note"
        case .passkey(let passkeyItem):
            return passkeyItem.rpName
        case .file(let fileItem):
            return fileItem.fileName
        }
    }

    private func formatURL(_ urlString: String) -> String {
        guard let url = URL(string: urlString),
              let host = url.host else {
            return urlString
        }
        return host.replacingOccurrences(of: "www.", with: "")
    }
}

#Preview {
    List {
        PassItemRow(
            item: .password(PassPasswordItem.create(
                name: "GitHub",
                username: "user@example.com",
                urls: ["https://github.com"]
            )),
            onTap: {},
            onCopyPassword: {}
        )

        PassItemRow(
            item: .note(PassNoteItem.create(name: "Secret Note")),
            onTap: {}
        )
    }
}
