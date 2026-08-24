//
//  NewLoginView.swift
//  GrooAutoFill
//
//  Create a login without leaving the sign-up flow. iOS never offers a
//  third-party provider its own save prompt — the only place a provider can
//  offer creation is inside its own sheet.
//

import SwiftUI

struct NewLoginView: View {
    @ObservedObject var service: AutoFillService
    /// Host of the site being filled, used to prefill the form.
    let site: String?
    let onSaved: (SharedPassPasswordItem) -> Void
    let onCancel: () -> Void

    @State private var draft: SharedNewLoginDraft
    @State private var revealPassword = false
    @State private var isSaving = false
    @State private var saveError: String?
    @FocusState private var usernameFocused: Bool

    init(
        service: AutoFillService,
        site: String?,
        onSaved: @escaping (SharedPassPasswordItem) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.service = service
        self.site = site
        self.onSaved = onSaved
        self.onCancel = onCancel
        _draft = State(initialValue: SharedNewLoginDraft(
            name: SharedNewLoginDraft.defaultName(forHost: site),
            site: site ?? ""
        ))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Login") {
                    TextField("Name", text: $draft.name)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    TextField("Username or email", text: $draft.username)
                        .textContentType(.username)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($usernameFocused)

                    passwordField
                }

                Section("Website") {
                    TextField("Website", text: $draft.site)
                        .textContentType(.URL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                if let saveError {
                    Section {
                        Text(saveError)
                            .foregroundStyle(.red)
                            .font(.footnote)
                    }
                }
            }
            .navigationTitle("New Login")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel", action: onCancel)
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Save", action: save)
                            .disabled(!draft.isSaveable)
                    }
                }
            }
            .onAppear { usernameFocused = true }
        }
    }

    @ViewBuilder
    private var passwordField: some View {
        HStack {
            Group {
                if revealPassword {
                    TextField("Password", text: $draft.password)
                } else {
                    SecureField("Password", text: $draft.password)
                }
            }
            .textContentType(.newPassword)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()

            Button {
                revealPassword.toggle()
            } label: {
                Image(systemName: revealPassword ? "eye.slash" : "eye")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel(revealPassword ? "Hide password" : "Show password")
        }

        Button {
            draft.password = SharedPasswordGenerator.generate(SharedPasswordGeneratorOptions())
            revealPassword = true
        } label: {
            Label("Generate Password", systemImage: "wand.and.stars")
        }
    }

    private func save() {
        isSaving = true
        saveError = nil
        Task {
            do {
                let item = try await service.createPassword(draft)
                onSaved(item)
            } catch {
                // The one failure the user must see: without the queue write
                // there is no durability at all, so nothing may be filled.
                isSaving = false
                saveError = "Couldn't save this login. \(error.localizedDescription)"
            }
        }
    }
}
