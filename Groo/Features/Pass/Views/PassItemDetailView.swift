//
//  PassItemDetailView.swift
//  Groo
//
//  Detail view for viewing and interacting with vault items.
//

import SwiftUI

struct PassItemDetailView: View {
    let item: PassVaultItem
    let passService: PassService
    let onDismiss: () -> Void

    @State private var showPassword = false
    @State private var copiedField: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                // Header
                header

                Divider()

                // Content based on item type
                switch item {
                case .password(let passwordItem):
                    passwordContent(passwordItem)
                case .card(let cardItem):
                    cardContent(cardItem)
                case .bankAccount(let bankItem):
                    bankAccountContent(bankItem)
                case .note(let noteItem):
                    noteContent(noteItem)
                case .passkey(let passkeyItem):
                    passkeyContent(passkeyItem)
                case .file(let fileItem):
                    fileContent(fileItem)
                case .corrupted(let corruptedItem):
                    corruptedContent(corruptedItem)
                }

                // Metadata
                Divider()
                    .padding(.top, Theme.Spacing.md)

                metadataSection
            }
            .padding(Theme.Spacing.lg)
        }
        .navigationTitle(item.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .overlay(alignment: .bottom) {
            if copiedField != nil {
                copiedToast
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: Theme.Spacing.md) {
            // Type icon
            ZStack {
                Circle()
                    .fill(item.isCorrupted ? Color.orange.opacity(0.1) : Theme.Brand.primary.opacity(0.1))
                    .frame(width: 56, height: 56)

                Image(systemName: item.isCorrupted ? "exclamationmark.triangle.fill" : item.type.icon)
                    .font(.title2)
                    .foregroundStyle(item.isCorrupted ? .orange : Theme.Brand.primary)
            }

            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(item.name)
                    .font(.title2)
                    .fontWeight(.bold)

                Text(item.isCorrupted ? "Corrupted" : item.type.label)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if item.favorite {
                Image(systemName: "star.fill")
                    .foregroundStyle(.yellow)
            }
        }
    }

    // MARK: - Password Content

    private func passwordContent(_ item: PassPasswordItem) -> some View {
        VStack(spacing: Theme.Spacing.md) {
            // Username
            if !item.username.isEmpty {
                fieldRow(
                    label: "Username",
                    value: item.username,
                    icon: "person.fill",
                    canCopy: true
                )
            }

            // Password
            fieldRow(
                label: "Password",
                value: showPassword ? item.password : String(repeating: "•", count: 12),
                icon: "key.fill",
                canCopy: true,
                copyValue: item.password,
                trailing: {
                    Button {
                        showPassword.toggle()
                    } label: {
                        Image(systemName: showPassword ? "eye.slash.fill" : "eye.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            )

            // URLs
            if !item.urls.isEmpty {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text("Websites")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    ForEach(item.urls, id: \.self) { url in
                        Link(destination: URL(string: url) ?? URL(string: "https://example.com")!) {
                            HStack {
                                Image(systemName: "link")
                                Text(formatURL(url))
                                Spacer()
                                Image(systemName: "arrow.up.right")
                                    .font(.caption)
                            }
                            .font(.body)
                        }
                    }
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
            }

            // TOTP
            if let totp = item.totp {
                TotpDisplayView(config: totp) { code in
                    copy(code, field: "2FA Code")
                }
            }

            // Notes
            if let notes = item.notes, !notes.isEmpty {
                notesSection(notes)
            }
        }
    }

    // MARK: - Card Content

    private func cardContent(_ item: PassCardItem) -> some View {
        VStack(spacing: Theme.Spacing.md) {
            fieldRow(
                label: "Card Number",
                value: formatCardNumber(item.number),
                icon: "creditcard.fill",
                canCopy: true,
                copyValue: item.number
            )

            HStack(spacing: Theme.Spacing.md) {
                fieldRow(
                    label: "Expiry",
                    value: "\(item.expMonth)/\(item.expYear)",
                    icon: "calendar",
                    canCopy: true
                )

                fieldRow(
                    label: "CVV",
                    value: showPassword ? item.cvv : "•••",
                    icon: "lock.fill",
                    canCopy: true,
                    copyValue: item.cvv,
                    trailing: {
                        Button {
                            showPassword.toggle()
                        } label: {
                            Image(systemName: showPassword ? "eye.slash.fill" : "eye.fill")
                                .foregroundStyle(.secondary)
                        }
                    }
                )
            }

            fieldRow(
                label: "Cardholder",
                value: item.cardholderName,
                icon: "person.fill",
                canCopy: true
            )

            if let notes = item.notes, !notes.isEmpty {
                notesSection(notes)
            }
        }
    }

    // MARK: - Bank Account Content

    private func bankAccountContent(_ item: PassBankAccountItem) -> some View {
        VStack(spacing: Theme.Spacing.md) {
            fieldRow(
                label: "Bank Name",
                value: item.bankName,
                icon: "building.columns",
                canCopy: false
            )

            fieldRow(
                label: "Account Number",
                value: showPassword ? item.accountNumber : "••••" + item.accountNumber.suffix(4),
                icon: "number.circle",
                canCopy: true,
                copyValue: item.accountNumber,
                trailing: {
                    Button {
                        showPassword.toggle()
                    } label: {
                        Image(systemName: showPassword ? "eye.slash.fill" : "eye.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            )

            if let routing = item.routingNumber, !routing.isEmpty {
                fieldRow(
                    label: "Routing Number",
                    value: routing,
                    icon: "arrow.left.arrow.right",
                    canCopy: true
                )
            }

            if let iban = item.iban, !iban.isEmpty {
                fieldRow(
                    label: "IBAN",
                    value: iban,
                    icon: "globe",
                    canCopy: true
                )
            }

            if let notes = item.notes, !notes.isEmpty {
                notesSection(notes)
            }
        }
    }

    // MARK: - Note Content

    private func noteContent(_ item: PassNoteItem) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Note")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(item.content)
                .font(.body)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))

            Button {
                copy(item.content, field: "Note")
            } label: {
                Label("Copy Note", systemImage: "doc.on.doc")
                    .font(.subheadline)
            }
        }
    }

    // MARK: - Passkey Content

    private func passkeyContent(_ item: PassPasskeyItem) -> some View {
        VStack(spacing: Theme.Spacing.md) {
            fieldRow(
                label: "Website",
                value: item.rpName,
                icon: "globe",
                canCopy: false
            )

            fieldRow(
                label: "Username",
                value: item.userName,
                icon: "person.fill",
                canCopy: true
            )

            fieldRow(
                label: "Relying Party",
                value: item.rpId,
                icon: "link",
                canCopy: true
            )
        }
    }

    // MARK: - File Content

    private func fileContent(_ item: PassFileItem) -> some View {
        VStack(spacing: Theme.Spacing.md) {
            fieldRow(
                label: "File Name",
                value: item.fileName,
                icon: "doc.fill",
                canCopy: false
            )

            fieldRow(
                label: "Size",
                value: formatFileSize(item.fileSize),
                icon: "doc.text.fill",
                canCopy: false
            )

            fieldRow(
                label: "Type",
                value: item.mimeType,
                icon: "info.circle.fill",
                canCopy: false
            )

            if let notes = item.notes, !notes.isEmpty {
                notesSection(notes)
            }

            // TODO: Download button
        }
    }

    // MARK: - Corrupted Content

    private func corruptedContent(_ item: PassCorruptedItem) -> some View {
        VStack(spacing: Theme.Spacing.md) {
            // Warning banner
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("This item is corrupted and cannot be displayed")
                    .font(.subheadline)
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(Color.orange.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))

            // Error details
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text("Error")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(item.error)
                    .font(.body)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
            }

            // Delete button
            Button(role: .destructive) {
                Task {
                    try? await passService.permanentlyDeleteItem(self.item)
                    onDismiss()
                }
            } label: {
                Label("Delete Corrupted Item", systemImage: "trash")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.red.opacity(0.1))
                    .foregroundStyle(.red)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
            }
        }
    }

    // MARK: - Metadata Section

    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text("Details")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Text("Created")
                    .foregroundStyle(.secondary)
                Spacer()
                Text(formatDate(item.createdAt))
            }
            .font(.footnote)

            HStack {
                Text("Modified")
                    .foregroundStyle(.secondary)
                Spacer()
                Text(formatDate(item.updatedAt))
            }
            .font(.footnote)
        }
    }

    // MARK: - Helper Views

    @ViewBuilder
    private func fieldRow<Trailing: View>(
        label: String,
        value: String,
        icon: String,
        canCopy: Bool,
        copyValue: String? = nil,
        @ViewBuilder trailing: () -> Trailing = { EmptyView() }
    ) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Image(systemName: icon)
                    .foregroundStyle(.secondary)
                    .frame(width: 20)

                Text(value)
                    .font(.body)

                Spacer()

                trailing()

                if canCopy {
                    Button {
                        copy(copyValue ?? value, field: label)
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .foregroundStyle(Theme.Brand.primary)
                    }
                }
            }
            .padding()
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
        }
    }

    private func notesSection(_ notes: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text("Notes")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(notes)
                .font(.body)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
        }
    }

    private var copiedToast: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text("\(copiedField ?? "Value") copied")
                .font(.subheadline)
                .fontWeight(.medium)
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.md)
        .background(.regularMaterial)
        .clipShape(Capsule())
        .shadow(radius: 4)
        .padding(.bottom, Theme.Spacing.xl)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    // MARK: - Helpers

    private func copy(_ value: String, field: String) {
        passService.copyToClipboard(value)
        withAnimation {
            copiedField = field
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation {
                if copiedField == field {
                    copiedField = nil
                }
            }
        }
    }

    private func formatURL(_ urlString: String) -> String {
        guard let url = URL(string: urlString),
              let host = url.host else {
            return urlString
        }
        return host.replacingOccurrences(of: "www.", with: "")
    }

    private func formatCardNumber(_ number: String) -> String {
        if showPassword {
            return number.enumerated().map { index, char in
                (index > 0 && index % 4 == 0) ? " \(char)" : String(char)
            }.joined()
        }
        return "•••• •••• •••• " + number.suffix(4)
    }

    private func formatFileSize(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }

    private func formatDate(_ timestamp: Int) -> String {
        let date = Date(timeIntervalSince1970: Double(timestamp) / 1000)
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

#Preview {
    NavigationStack {
        PassItemDetailView(
            item: .password(PassPasswordItem.create(
                name: "GitHub",
                username: "user@example.com",
                password: "secretpassword123",
                urls: ["https://github.com"]
            )),
            passService: PassService(),
            onDismiss: {}
        )
    }
}
