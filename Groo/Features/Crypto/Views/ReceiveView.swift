//
//  ReceiveView.swift
//  Groo
//
//  Receive view showing wallet QR code and copyable address.
//

import SwiftUI
import CoreImage.CIFilterBuiltins

struct ReceiveView: View {
    let address: String

    @State private var copied = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: Theme.Spacing.xl) {
            Spacer()

            // QR Code
            if let qrImage = generateQRCode(from: address) {
                Image(uiImage: qrImage)
                    .interpolation(.none)
                    .resizable()
                    .aspectRatio(1, contentMode: .fit)
                    .frame(width: 220, height: 220)
                    .padding()
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg))
                    .shadow(color: .black.opacity(0.1), radius: 8)
            }

            // Address
            VStack(spacing: Theme.Spacing.sm) {
                Text("Your Address")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(address)
                    .font(.caption.monospaced())
                    .multilineTextAlignment(.center)
                    .textSelection(.enabled)
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
            }
            .padding(.horizontal, Theme.Spacing.xl)

            // Copy button
            Button {
                UIPasteboard.general.string = address
                copied = true
                UIImpactFeedbackGenerator(style: .light).impactOccurred()

                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    copied = false
                }
            } label: {
                Label(
                    copied ? "Copied!" : "Copy Address",
                    systemImage: copied ? "checkmark" : "doc.on.doc"
                )
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Theme.Brand.primary)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
            }
            .padding(.horizontal, Theme.Spacing.xl)

            // Share button
            ShareLink(item: address) {
                Label("Share Address", systemImage: "square.and.arrow.up")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .foregroundStyle(Theme.Brand.primary)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
            }
            .padding(.horizontal, Theme.Spacing.xl)

            Spacer()
        }
        .navigationTitle("Receive")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - QR Code Generator

    private func generateQRCode(from string: String) -> UIImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()

        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"

        guard let outputImage = filter.outputImage else { return nil }

        let scale = 256 / outputImage.extent.width
        let scaledImage = outputImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        guard let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) else {
            return nil
        }

        return UIImage(cgImage: cgImage)
    }
}
