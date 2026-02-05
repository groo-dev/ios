//
//  QuickInputBar.swift
//  Groo
//
//  Floating paste button for quick item creation from clipboard.
//

import SwiftUI

struct PasteFAB: View {
    let padService: PadService
    let syncService: SyncService
    let onItemAdded: () -> Void

    @State private var toastState = ToastState()
    @State private var isCreating = false

    var body: some View {
        Button {
            pasteFromClipboard()
        } label: {
            ZStack {
                Image(systemName: "doc.on.clipboard")
                    .font(.body)
                    .opacity(isCreating ? 0 : 1)

                if isCreating {
                    ProgressView()
                        .scaleEffect(0.7)
                }
            }
            .padding(12)
        }
        .disabled(isCreating)
        .modifier(GlassCircleModifier())
        .padding(.trailing, Theme.Spacing.lg)
        .padding(.bottom, Theme.Spacing.lg)
        .toast(isPresented: $toastState.isPresented, message: toastState.message, style: toastState.style)
    }

    private func pasteFromClipboard() {
        isCreating = true

        Task {
            do {
                guard let item = try await padService.createFromClipboard() else {
                    toastState.showError("Clipboard is empty")
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                    isCreating = false
                    return
                }

                await syncService.addItem(item)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                toastState.show("Item added", style: .success)
                isCreating = false
                onItemAdded()
            } catch {
                toastState.showError("Failed to create item")
                isCreating = false
            }
        }
    }
}

private struct GlassCircleModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content.glassEffect(.regular.interactive())
        } else {
            content
                .background(.thinMaterial)
                .clipShape(Circle())
                .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
        }
    }
}

#Preview {
    ZStack(alignment: .bottomTrailing) {
        Color.gray.opacity(0.1).ignoresSafeArea()
        PasteFAB(
            padService: PadService(api: APIClient(baseURL: Config.padAPIBaseURL)),
            syncService: SyncService(api: APIClient(baseURL: Config.padAPIBaseURL)),
            onItemAdded: {}
        )
    }
    .tint(Theme.Brand.primary)
}
