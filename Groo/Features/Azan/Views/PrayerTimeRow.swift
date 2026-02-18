//
//  PrayerTimeRow.swift
//  Groo
//
//  Single prayer time row for the Azan prayer list.
//

import SwiftUI

struct PrayerTimeRow: View {
    let entry: PrayerTimeEntry
    let onToggleNotification: (Prayer) -> Void
    var onTapPrayer: ((Prayer) -> Void)?

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            // Prayer icon
            Image(systemName: entry.prayer.icon)
                .font(.body)
                .foregroundStyle(iconColor)
                .frame(width: 24)

            // Prayer name + labels
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                HStack(spacing: Theme.Spacing.sm) {
                    Text(entry.displayName)
                        .font(.body.weight(entry.isCurrent || entry.isNext ? .semibold : .regular))
                        .foregroundStyle(entry.isPassed ? .secondary : .primary)

                    if let ramadanLabel = entry.ramadanLabel {
                        Text(ramadanLabel)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, Theme.Spacing.xs)
                            .padding(.vertical, 2)
                            .background(Theme.Brand.primary, in: Capsule())
                    }
                }

                if entry.adjustment != 0 {
                    Text("\(entry.adjustment > 0 ? "+" : "")\(entry.adjustment) min")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Time
            Text(entry.displayTime)
                .font(.body.monospacedDigit().weight(entry.isCurrent || entry.isNext ? .semibold : .regular))
                .foregroundStyle(entry.isPassed ? .secondary : .primary)

            // Notification bell (hide for info-only rows)
            if !entry.prayer.isInfoOnly {
                Button {
                    onToggleNotification(entry.prayer)
                } label: {
                    Image(systemName: entry.notificationEnabled ? "bell.fill" : "bell.slash")
                        .font(.caption)
                        .foregroundStyle(entry.notificationEnabled ? Theme.Brand.primary : Color.secondary)
                }
                .buttonStyle(.plain)

                // Chevron for tappable rows
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.quaternary)
            }
        }
        .padding(.vertical, Theme.Spacing.sm)
        .padding(.horizontal, Theme.Spacing.md)
        .background(
            rowBackground
        )
        .contentShape(Rectangle())
        .onTapGesture {
            if !entry.prayer.isInfoOnly {
                onTapPrayer?(entry.prayer)
            }
        }
    }

    @ViewBuilder
    private var rowBackground: some View {
        if entry.isCurrent, let urgency = entry.currentUrgency {
            RoundedRectangle(cornerRadius: Theme.Radius.sm)
                .fill(urgency.color.opacity(0.08))
        } else if entry.isNext {
            RoundedRectangle(cornerRadius: Theme.Radius.sm)
                .fill(Theme.Brand.primary.opacity(0.08))
        }
    }

    private var iconColor: Color {
        if entry.isCurrent, let urgency = entry.currentUrgency { return urgency.color }
        if entry.isNext { return Theme.Brand.primary }
        if entry.isPassed { return .secondary }
        return .primary
    }
}
