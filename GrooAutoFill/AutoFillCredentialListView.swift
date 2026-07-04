//
//  AutoFillCredentialListView.swift
//  GrooAutoFill
//
//  SwiftUI view for displaying and selecting credentials.
//

import AuthenticationServices
import SwiftUI

struct AutoFillCredentialListView: View {
    @ObservedObject var service: AutoFillService
    let serviceIdentifiers: [ASCredentialServiceIdentifier]
    let rpId: String?
    var allowedCredentialIds: [Data] = []
    let onSelect: (SharedPassPasswordItem) -> Void
    var onSelectPasskey: ((SharedPassPasskeyItem) -> Void)? = nil
    let onCancel: () -> Void

    @State private var searchText = ""

    // MARK: - Derived Data

    /// Passkeys can only be returned for passkey requests
    private var isPasskeyRequest: Bool { rpId != nil }

    private var trimmedQuery: String {
        searchText.trimmingCharacters(in: .whitespaces)
    }

    private var isSearching: Bool { !trimmedQuery.isEmpty }

    /// Passkeys usable for the current request (rpId + allowedCredentials match)
    private var matchingPasskeys: [SharedPassPasskeyItem] {
        service.filteredPasskeys(for: rpId, allowedCredentialIds: allowedCredentialIds)
    }

    /// Passwords matching the current site's domain
    private var suggestedCredentials: [SharedPassPasswordItem] {
        service.filteredCredentials(for: serviceIdentifiers)
    }

    private var hasSuggestions: Bool {
        !matchingPasskeys.isEmpty || !suggestedCredentials.isEmpty
    }

    /// Everything not already shown in Suggested
    private var otherCredentials: [SharedPassPasswordItem] {
        let suggestedIds = Set(suggestedCredentials.map(\.id))
        return service.credentials.filter { !suggestedIds.contains($0.id) }
    }

    private var searchResultCredentials: [SharedPassPasswordItem] {
        service.searchCredentials(query: trimmedQuery)
    }

    private var searchResultPasskeys: [SharedPassPasskeyItem] {
        guard isPasskeyRequest else { return [] }
        let query = trimmedQuery.lowercased()
        return matchingPasskeys.filter { passkey in
            passkey.name.lowercased().contains(query) ||
            passkey.userName.lowercased().contains(query) ||
            passkey.rpId.lowercased().contains(query)
        }
    }

    /// Host of the site being logged into, for the Suggested section header
    private var siteName: String? {
        if let rpId { return rpId }
        return serviceIdentifiers.first.flatMap { identifier in
            switch identifier.type {
            case .domain:
                return identifier.identifier
            case .URL:
                return URL(string: identifier.identifier)?.host
            @unknown default:
                return nil
            }
        }
    }

    private var vaultIsEmpty: Bool {
        service.credentials.isEmpty && matchingPasskeys.isEmpty
    }

    var body: some View {
        NavigationStack {
            Group {
                if service.isLoading {
                    loadingView
                } else if !service.isUnlocked {
                    unlockView
                } else {
                    credentialsList
                }
            }
            .navigationTitle("Groo Pass")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        onCancel()
                    }
                }
            }
        }
    }

    // MARK: - Loading View

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
            Text("Loading...")
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Unlock View

    private var unlockView: some View {
        VStack(spacing: 24) {
            Image(systemName: "lock.fill")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("Groo Pass Is Locked")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Unlock to fill your passwords and passkeys")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if let error = service.error {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            Button {
                service.error = nil
                Task {
                    do {
                        try await service.unlock()
                    } catch {
                        // Show the real cause — a generic message makes keychain,
                        // decryption, and cancelled-Face-ID failures identical
                        service.error = error.localizedDescription
                    }
                }
            } label: {
                Label("Unlock", systemImage: "faceid")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.accentColor)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal, 32)
        }
        .padding()
    }

    // MARK: - Credentials List

    private var credentialsList: some View {
        List {
            if isSearching {
                searchResultSections
            } else {
                suggestedSection
                allItemsSection
            }
        }
        .listStyle(.insetGrouped)
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search all items"
        )
        .overlay {
            if vaultIsEmpty {
                ContentUnavailableView(
                    "No Items",
                    systemImage: "key.slash",
                    description: Text("Add passwords in the Groo app to fill them here")
                )
            } else if isSearching && searchResultCredentials.isEmpty && searchResultPasskeys.isEmpty {
                ContentUnavailableView.search(text: trimmedQuery)
            }
        }
    }

    @ViewBuilder
    private var searchResultSections: some View {
        if !searchResultPasskeys.isEmpty {
            Section("Passkeys") {
                passkeyRows(searchResultPasskeys)
            }
        }
        if !searchResultCredentials.isEmpty {
            Section("Passwords") {
                credentialRows(searchResultCredentials)
            }
        }
    }

    @ViewBuilder
    private var suggestedSection: some View {
        if hasSuggestions {
            Section {
                passkeyRows(matchingPasskeys)
                credentialRows(suggestedCredentials)
            } header: {
                if let siteName {
                    Text("Suggested for \(siteName)")
                } else {
                    Text("Suggested")
                }
            }
        }
    }

    @ViewBuilder
    private var allItemsSection: some View {
        if !otherCredentials.isEmpty {
            Section(hasSuggestions ? "All Items" : "Passwords") {
                credentialRows(otherCredentials)
            }
        }
    }

    private func credentialRows(_ credentials: [SharedPassPasswordItem]) -> some View {
        ForEach(credentials) { credential in
            Button {
                onSelect(credential)
            } label: {
                CredentialRow(credential: credential)
            }
            .buttonStyle(.plain)
        }
    }

    private func passkeyRows(_ passkeys: [SharedPassPasskeyItem]) -> some View {
        ForEach(passkeys) { passkey in
            Button {
                onSelectPasskey?(passkey)
            } label: {
                PasskeyRow(passkey: passkey)
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Monogram Icon

struct MonogramIcon: View {
    let name: String

    private static let palette: [Color] = [
        .blue, .indigo, .purple, .pink, .red, .orange, .teal, .green,
    ]

    private var color: Color {
        let hash = name.unicodeScalars.reduce(5381) { ($0 << 5) &+ $0 &+ Int($1.value) }
        return Self.palette[abs(hash) % Self.palette.count]
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.2))
            Text(name.first.map(String.init)?.uppercased() ?? "•")
                .font(.headline)
                .foregroundStyle(color)
        }
        .frame(width: 36, height: 36)
    }
}

// MARK: - Credential Row

struct CredentialRow: View {
    let credential: SharedPassPasswordItem

    var body: some View {
        HStack(spacing: 12) {
            MonogramIcon(name: credential.name)

            VStack(alignment: .leading, spacing: 2) {
                Text(credential.name)
                    .font(.body)
                    .fontWeight(.medium)
                    .lineLimit(1)

                Text(credential.username)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

// MARK: - Passkey Row

struct PasskeyRow: View {
    let passkey: SharedPassPasskeyItem

    var body: some View {
        HStack(spacing: 12) {
            MonogramIcon(name: passkey.name)

            VStack(alignment: .leading, spacing: 2) {
                Text(passkey.name)
                    .font(.body)
                    .fontWeight(.medium)
                    .lineLimit(1)

                Text(passkey.userName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Label("Passkey", systemImage: "person.badge.key.fill")
                .font(.caption)
                .foregroundStyle(.purple)
                .labelStyle(.titleAndIcon)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}
