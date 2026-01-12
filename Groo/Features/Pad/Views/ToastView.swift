//
//  ToastView.swift
//  Groo
//
//  Reusable toast notification for success/error feedback.
//

import SwiftUI

// MARK: - Toast Style

enum ToastStyle {
    case success
    case error
    case info

    var icon: String {
        switch self {
        case .success: return "checkmark.circle.fill"
        case .error: return "xmark.circle.fill"
        case .info: return "info.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .success: return Theme.Colors.success
        case .error: return Theme.Colors.error
        case .info: return Theme.Colors.info
        }
    }
}

// MARK: - Toast View

struct ToastView: View {
    let message: String
    let style: ToastStyle

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: style.icon)
                .foregroundStyle(style.color)
            Text(message)
                .font(.subheadline)
                .fontWeight(.medium)
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.md)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
    }
}

// MARK: - Toast Modifier

struct ToastModifier: ViewModifier {
    @Binding var isPresented: Bool
    let message: String
    let style: ToastStyle
    var duration: Double = 2.0

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if isPresented {
                    ToastView(message: message, style: style)
                        .padding(.bottom, Theme.Spacing.xxl)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
                                withAnimation(Theme.Animation.normalSpring) {
                                    isPresented = false
                                }
                            }
                        }
                }
            }
            .animation(Theme.Animation.normalSpring, value: isPresented)
    }
}

extension View {
    func toast(isPresented: Binding<Bool>, message: String, style: ToastStyle, duration: Double = 2.0) -> some View {
        modifier(ToastModifier(isPresented: isPresented, message: message, style: style, duration: duration))
    }
}

// MARK: - Toast State

@Observable
class ToastState {
    var isPresented = false
    var message = ""
    var style: ToastStyle = .success

    func show(_ message: String, style: ToastStyle = .success) {
        self.message = message
        self.style = style
        withAnimation(Theme.Animation.normalSpring) {
            isPresented = true
        }
    }

    func showCopied() {
        show("Copied to clipboard", style: .success)
    }

    func showError(_ message: String) {
        show(message, style: .error)
    }
}

#Preview {
    VStack {
        ToastView(message: "Copied to clipboard", style: .success)
        ToastView(message: "Failed to copy", style: .error)
        ToastView(message: "Syncing...", style: .info)
    }
    .padding()
}
