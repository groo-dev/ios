//
//  ScratchpadTabView.swift
//  Groo
//
//  Tab wrapper for ScratchpadView with unlock functionality.
//

import SwiftUI
import os

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
        // Unlike PadUnlockView, this screen DID show a visible bar before the
        // hoist (its own NavigationStack carried navigationTitle below). The
        // host now supplies the single NavigationStack instead of a second,
        // redundant one — the title renders through it unchanged. Do not add
        // .toolbar(.hidden, for: .navigationBar) here: that would silently
        // drop the title, which ScratchpadViewSnapshotTests.scratchpadTabLocked
        // pins pixel-for-pixel.
        .navigationTitle("Scratchpad")
        .tint(Theme.Brand.primary)
    }

    private func unlock() {
        guard !password.isEmpty else { return }

        isUnlocking = true
        error = nil

        Task {
            do {
                guard try await padService.unlock(password: password) else {
                    self.error = "Incorrect password"
                    isUnlocking = false
                    return
                }
                onUnlock()
            } catch {
                Log.scratchpad.error("Unlock failed: \(String(describing: error))")
                self.error = error.localizedDescription
            }
            isUnlocking = false
        }
    }
}

#Preview {
    NavigationStack {
        ScratchpadTabView(
            padService: PadService(api: APIClient(baseURL: Config.padAPIBaseURL)),
            syncService: SyncService(api: APIClient(baseURL: Config.padAPIBaseURL))
        )
    }
}
