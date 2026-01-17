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
    let onSelect: (SharedPassPasswordItem) -> Void
    let onCancel: () -> Void

    @State private var searchText = ""

    private var displayedCredentials: [SharedPassPasswordItem] {
        if searchText.isEmpty {
            return service.filteredCredentials(for: serviceIdentifiers)
        } else {
            return service.searchCredentials(query: searchText)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if service.isLoading {
                    loadingView
                } else if !service.isUnlocked {
                    unlockView
                } else if displayedCredentials.isEmpty {
                    emptyView
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

            Text("Vault Locked")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Authenticate to access your passwords")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if let error = service.error {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.footnote)
                    .padding(.horizontal)
            }

            Button {
                Task {
                    do {
                        try await service.unlock()
                    } catch {
                        service.error = error.localizedDescription
                    }
                }
            } label: {
                Label("Unlock with Face ID", systemImage: "faceid")
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

    // MARK: - Empty View

    private var emptyView: some View {
        VStack(spacing: 16) {
            Image(systemName: "key.slash")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("No Passwords Found")
                .font(.title3)
                .fontWeight(.medium)

            if !serviceIdentifiers.isEmpty {
                Text("No saved passwords for this website")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding()
    }

    // MARK: - Credentials List

    private var credentialsList: some View {
        List {
            ForEach(displayedCredentials) { credential in
                Button {
                    onSelect(credential)
                } label: {
                    CredentialRow(credential: credential)
                }
                .buttonStyle(.plain)
            }
        }
        .listStyle(.plain)
        .searchable(text: $searchText, prompt: "Search passwords")
    }
}

// MARK: - Credential Row

struct CredentialRow: View {
    let credential: SharedPassPasswordItem

    var body: some View {
        HStack(spacing: 12) {
            // Icon
            Image(systemName: "key.fill")
                .font(.title3)
                .foregroundStyle(.blue)
                .frame(width: 32)

            // Info
            VStack(alignment: .leading, spacing: 2) {
                Text(credential.name)
                    .font(.body)
                    .fontWeight(.medium)

                Text(credential.username)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}
