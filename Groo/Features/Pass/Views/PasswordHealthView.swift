//
//  PasswordHealthView.swift
//  Groo
//
//  Displays password health analysis with actionable insights.
//

import SwiftUI

struct PasswordHealthView: View {
    let passService: PassService
    let onDismiss: () -> Void
    let onSelectItem: (PassVaultItem) -> Void

    @State private var report: PasswordHealthReport?

    var body: some View {
        NavigationStack {
            Group {
                if let report = report {
                    ScrollView {
                        VStack(spacing: 20) {
                            // Overall Score Card
                            scoreCard(report)

                            // Issue Categories
                            if report.weakCount > 0 {
                                issueSection(
                                    title: "Weak Passwords",
                                    count: report.weakCount,
                                    icon: "exclamationmark.shield.fill",
                                    color: .red,
                                    items: report.weakPasswords
                                )
                            }

                            if report.reusedCount > 0 {
                                reusedSection(report.reusedPasswords)
                            }

                            if report.oldCount > 0 {
                                issueSection(
                                    title: "Old Passwords",
                                    count: report.oldCount,
                                    icon: "clock.fill",
                                    color: .orange,
                                    items: report.oldPasswords,
                                    subtitle: "Not updated in 90+ days"
                                )
                            }

                            if report.withoutTwoFactorCount > 0 {
                                issueSection(
                                    title: "Missing 2FA",
                                    count: report.withoutTwoFactorCount,
                                    icon: "lock.open.fill",
                                    color: .yellow,
                                    items: report.withoutTwoFactor,
                                    subtitle: "No two-factor authentication"
                                )
                            }

                            if report.weakCount == 0 && report.reusedCount == 0 &&
                               report.oldCount == 0 && report.withoutTwoFactorCount == 0 {
                                allGoodView
                            }
                        }
                        .padding()
                    }
                } else {
                    ProgressView("Analyzing passwords...")
                }
            }
            .navigationTitle("Password Health")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        onDismiss()
                    }
                }
            }
        }
        .task {
            analyzePasswords()
        }
    }

    // MARK: - Score Card

    private func scoreCard(_ report: PasswordHealthReport) -> some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.2), lineWidth: 12)
                    .frame(width: 120, height: 120)

                Circle()
                    .trim(from: 0, to: CGFloat(report.overallScore) / 100)
                    .stroke(
                        scoreColor(report.scoreColor),
                        style: StrokeStyle(lineWidth: 12, lineCap: .round)
                    )
                    .frame(width: 120, height: 120)
                    .rotationEffect(.degrees(-90))

                VStack(spacing: 2) {
                    Text("\(report.overallScore)")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                    Text("/ 100")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Text(report.scoreLabel)
                .font(.headline)
                .foregroundStyle(scoreColor(report.scoreColor))

            Text("\(report.totalPasswords) passwords analyzed")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Issue Section

    private func issueSection(
        title: String,
        count: Int,
        icon: String,
        color: Color,
        items: [PassPasswordItem],
        subtitle: String? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(color)
                Text(title)
                    .font(.headline)
                Spacer()
                Text("\(count)")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundStyle(color)
            }

            if let subtitle = subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            ForEach(items.prefix(5), id: \.id) { item in
                Button {
                    if let vaultItem = findVaultItem(for: item) {
                        onSelectItem(vaultItem)
                    }
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name)
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Text(item.username)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)
            }

            if items.count > 5 {
                Text("and \(items.count - 5) more...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Reused Section

    private func reusedSection(_ reusedGroups: [String: [PassPasswordItem]]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "doc.on.doc.fill")
                    .foregroundStyle(.purple)
                Text("Reused Passwords")
                    .font(.headline)
                Spacer()
                Text("\(reusedGroups.values.flatMap { $0 }.count)")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundStyle(.purple)
            }

            Text("Same password used on multiple sites")
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            ForEach(Array(reusedGroups.values.prefix(3)), id: \.first?.id) { group in
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(group.count) accounts share a password:")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    ForEach(group.prefix(3), id: \.id) { item in
                        Button {
                            if let vaultItem = findVaultItem(for: item) {
                                onSelectItem(vaultItem)
                            }
                        } label: {
                            HStack {
                                Text("• \(item.name)")
                                    .font(.subheadline)
                                Spacer()
                            }
                        }
                        .buttonStyle(.plain)
                    }

                    if group.count > 3 {
                        Text("  and \(group.count - 3) more...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - All Good View

    private var allGoodView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)

            Text("All passwords look good!")
                .font(.headline)

            Text("No weak, reused, or old passwords found.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Helpers

    private func analyzePasswords() {
        let items = passService.getItems(type: nil)
        report = PasswordHealthAnalyzer.analyze(items: items)
    }

    private func findVaultItem(for password: PassPasswordItem) -> PassVaultItem? {
        passService.getItem(id: password.id)
    }

    private func scoreColor(_ colorName: String) -> Color {
        switch colorName {
        case "green": return .green
        case "blue": return .blue
        case "orange": return .orange
        case "red": return .red
        default: return .gray
        }
    }
}
