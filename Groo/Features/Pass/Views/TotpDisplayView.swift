//
//  TotpDisplayView.swift
//  Groo
//
//  Displays TOTP codes with countdown timer and copy functionality.
//

import SwiftUI
import Combine

struct TotpDisplayView: View {
    let config: PassTotpConfig
    let onCopy: (String) -> Void

    @State private var code = ""
    @State private var secondsRemaining = 0
    @State private var progress: Double = 0

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            // Progress ring
            ZStack {
                Circle()
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 3)
                    .frame(width: 40, height: 40)

                Circle()
                    .trim(from: 0, to: 1 - progress)
                    .stroke(progressColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .frame(width: 40, height: 40)
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1), value: progress)

                Text("\(secondsRemaining)")
                    .font(.caption)
                    .fontWeight(.medium)
                    .monospacedDigit()
            }

            // Code display
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text("2FA Code")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(formattedCode)
                    .font(.system(.title2, design: .monospaced))
                    .fontWeight(.semibold)
                    .foregroundStyle(codeColor)
            }

            Spacer()

            // Copy button
            Button {
                onCopy(code)
            } label: {
                Image(systemName: "doc.on.doc")
                    .foregroundStyle(Theme.Brand.primary)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
        .onAppear {
            updateCode()
        }
        .onReceive(timer) { _ in
            updateCode()
        }
    }

    private var formattedCode: String {
        // Insert space in the middle for readability
        let midpoint = code.count / 2
        let left = String(code.prefix(midpoint))
        let right = String(code.suffix(code.count - midpoint))
        return "\(left) \(right)"
    }

    private var progressColor: Color {
        if secondsRemaining <= 5 {
            return .red
        } else if secondsRemaining <= 10 {
            return .orange
        }
        return Theme.Brand.primary
    }

    private var codeColor: Color {
        if secondsRemaining <= 5 {
            return .red
        }
        return .primary
    }

    private func updateCode() {
        let now = Date()
        code = TotpService.generateCode(config: config, time: now)
        secondsRemaining = TotpService.secondsRemaining(period: config.period, time: now)
        progress = TotpService.progress(period: config.period, time: now)
    }
}

#Preview {
    VStack(spacing: 20) {
        TotpDisplayView(
            config: PassTotpConfig(
                secret: "JBSWY3DPEHPK3PXP",
                algorithm: .sha1,
                digits: 6,
                period: 30
            ),
            onCopy: { _ in }
        )

        TotpDisplayView(
            config: PassTotpConfig(
                secret: "JBSWY3DPEHPK3PXP",
                algorithm: .sha256,
                digits: 8,
                period: 30
            ),
            onCopy: { _ in }
        )
    }
    .padding()
}
