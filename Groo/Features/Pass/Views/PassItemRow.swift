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
            HStack(spacing: Theme.Spacing.sm) {
                // Type icon
                Image(systemName: item.isCorrupted ? "exclamationmark.triangle.fill" : item.type.icon)
                    .font(.subheadline)
                    .foregroundStyle(item.isCorrupted ? .orange : Theme.Brand.primary)
                    .frame(width: 24)

                // Item info
                VStack(alignment: .leading, spacing: 0) {
                    Text(item.name)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    if let subtitle = itemSubtitle {
                        Text(subtitle)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                if item.favorite {
                    Image(systemName: "star.fill")
                        .font(.caption2)
                        .foregroundStyle(.yellow)
                }

                if case .password = item, let onCopy = onCopyPassword {
                    Button {
                        onCopy()
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.caption)
                            .foregroundStyle(Theme.Brand.primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, Theme.Spacing.xs)
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
        case .cryptoWallet(let walletItem):
            return walletItem.address.prefix(6) + "..." + walletItem.address.suffix(4)
        case .corrupted:
            return "Corrupted - tap to delete"
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
