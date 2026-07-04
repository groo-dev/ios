//
//  RegisterPasskeyView.swift
//  GrooAutoFill
//
//  Confirmation screen for creating a new passkey.
//

import SwiftUI

struct RegisterPasskeyView: View {
    @ObservedObject var service: AutoFillService
    let rpId: String
    let userName: String
    let onConfirm: () -> Void
    let onCancel: () -> Void

    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                Image(systemName: "person.badge.key.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.purple)

                Text("Create a Passkey")
                    .font(.title2)
                    .fontWeight(.semibold)

                VStack(spacing: 8) {
                    Text(rpId)
                        .font(.headline)
                    Text(userName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 32)

                Text("The passkey is saved to Groo Pass and syncs to your other devices.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                if let error = service.error {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                Spacer()

                Button {
                    guard !isSaving else { return }
                    isSaving = true
                    service.error = nil
                    onConfirm()
                } label: {
                    Group {
                        if isSaving {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Label("Save Passkey", systemImage: "faceid")
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.accentColor)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 16)
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
            .onChange(of: service.error) { _, newValue in
                if newValue != nil {
                    isSaving = false
                }
            }
        }
    }
}
