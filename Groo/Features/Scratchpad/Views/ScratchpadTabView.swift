//
//  ScratchpadTabView.swift
//  Groo
//
//  Tab wrapper for ScratchpadView with unlock functionality.
//

import SwiftUI

struct ScratchpadTabView: View {
    let padService: PadService
    let syncService: SyncService

    @State private var isUnlocked = false

    var body: some View {
        Group {
            if isUnlocked {
                ScratchpadView(padService: padService, syncService: syncService)
            } else {
                ScratchpadUnlockView(
                    padService: padService,
                    onUnlock: {
                        isUnlocked = true
                    }
                )
            }
        }
        .onAppear {
            isUnlocked = padService.isUnlocked
        }
    }
}

// MARK: - Unlock View

private struct ScratchpadUnlockView: View {
    let padService: PadService
    let onUnlock: () -> Void

    @State private var password = ""
    @State private var isUnlocking = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                Image(systemName: "note.text")
                    .font(.system(size: 64))
                    .foregroundStyle(Theme.Brand.primary)

                Text("Scratchpad Locked")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("Enter your encryption password to access your scratchpads")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                VStack(spacing: 16) {
                    SecureField("Encryption Password", text: $password)
                        .textFieldStyle(.roundedBorder)
                        .textContentType(.password)
                        .submitLabel(.go)
                        .onSubmit(unlock)
                        .padding(.horizontal, 32)

                    if let error = error {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    Button(action: unlock) {
                        if isUnlocking {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Text("Unlock")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(password.isEmpty || isUnlocking)
                    .padding(.horizontal, 32)
                }

                Spacer()
                Spacer()
            }
            .navigationTitle("Scratchpad")
        }
        .tint(Theme.Brand.primary)
    }

    private func unlock() {
        guard !password.isEmpty else { return }

        isUnlocking = true
        error = nil

        Task {
            do {
                try await padService.unlock(password: password)
                onUnlock()
            } catch {
                self.error = "Invalid password"
            }
            isUnlocking = false
        }
    }
}

#Preview {
    ScratchpadTabView(
        padService: PadService(api: APIClient(baseURL: Config.padAPIBaseURL)),
        syncService: SyncService(api: APIClient(baseURL: Config.padAPIBaseURL))
    )
}
