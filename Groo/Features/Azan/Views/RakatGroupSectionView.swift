//
//  RakatGroupSectionView.swift
//  Groo
//
//  Renders one RakatGroupGuide: header, niyyah, rakat flow with posture icons, notes.
//

import SwiftUI

struct RakatGroupSectionView: View {
    let group: RakatGroupGuide

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Colored left-border header
            groupHeader

            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                niyyahSection
                rakatFlowSection
                if !group.notes.isEmpty {
                    notesSection
                }
            }
            .padding(Theme.Spacing.lg)
        }
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.lg)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: Theme.Radius.lg)
                .fill(group.unit.category.color)
                .frame(width: 4)
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg))
    }

    // MARK: - Header

    private var groupHeader: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Circle()
                .fill(group.unit.category.color)
                .frame(width: 10, height: 10)

            Text(group.displayTitle.uppercased())
                .font(.caption.weight(.bold))
                .tracking(0.5)

            Spacer()
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.top, Theme.Spacing.lg)
        .padding(.bottom, Theme.Spacing.md)
    }

    // MARK: - Niyyah

    private var niyyahSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("NIYYAH")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .tracking(0.3)

            Text(group.niyyah.arabic)
                .font(.callout)
                .environment(\.layoutDirection, .rightToLeft)
                .frame(maxWidth: .infinity, alignment: .trailing)

            Text(group.niyyah.transliteration)
                .font(.caption)
                .foregroundStyle(.secondary)
                .italic()

            Text(group.niyyah.english)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(Theme.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.md)
                .fill(Color(.tertiarySystemGroupedBackground))
        )
    }

    // MARK: - Rakat Flow

    private var rakatFlowSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            ForEach(group.rakats) { rakat in
                rakatView(rakat)
            }
        }
    }

    private func rakatView(_ rakat: RakatDetail) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            // Rakat number header
            HStack(spacing: Theme.Spacing.sm) {
                Text("RAKAT \(rakat.number)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(group.unit.category.color)
                    .tracking(0.3)

                if let sitting = rakat.sittingType {
                    Text("·")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Text(sitting == .midTashahhud ? "Mid-sitting" : "Final sitting")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            // Action timeline
            actionTimeline(rakat.actions)
        }
    }

    private func actionTimeline(_ actions: [RakatAction]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(actions.enumerated()), id: \.element.id) { index, action in
                let showPosture = shouldShowPosture(action: action, index: index, actions: actions)
                let isLast = index == actions.count - 1

                HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                    // Posture icon column (fixed width)
                    ZStack {
                        if showPosture, let posture = action.posture {
                            PrayerPostureIcon(posture: posture, size: 28)
                        }
                    }
                    .frame(width: 28)

                    // Timeline connector
                    VStack(spacing: 0) {
                        Circle()
                            .fill(action.isSpecial ? Color.orange : group.unit.category.color.opacity(0.5))
                            .frame(width: 6, height: 6)
                            .padding(.top, 6)

                        if !isLast {
                            Rectangle()
                                .fill(Color(.separator).opacity(0.3))
                                .frame(width: 1)
                                .frame(maxHeight: .infinity)
                        }
                    }
                    .frame(width: 6)

                    // Action content
                    actionContent(action)
                        .padding(.bottom, isLast ? 0 : Theme.Spacing.sm)
                }
            }
        }
    }

    private func actionContent(_ action: RakatAction) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
            HStack(spacing: Theme.Spacing.xs) {
                Text(action.name)
                    .font(.subheadline.weight(action.isSpecial ? .bold : .medium))
                    .foregroundStyle(action.isSpecial ? .orange : .primary)

                if action.isAloud {
                    HStack(spacing: 2) {
                        Image(systemName: "speaker.wave.2")
                            .font(.system(size: 8))
                        Text("Aloud")
                            .font(.caption2.weight(.medium))
                    }
                    .padding(.horizontal, Theme.Spacing.xs)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.orange.opacity(0.15)))
                    .foregroundStyle(.orange)
                }
            }

            if let arabic = action.arabicText {
                Text(arabic)
                    .font(.caption)
                    .environment(\.layoutDirection, .rightToLeft)
                    .lineLimit(1)
                    .foregroundStyle(.primary.opacity(0.8))
            }

            if let translit = action.transliteration {
                Text(translit)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .italic()
            }

            Text(action.instruction)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(action.isSpecial ? Theme.Spacing.sm : 0)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if action.isSpecial {
                RoundedRectangle(cornerRadius: Theme.Radius.sm)
                    .fill(Color.orange.opacity(0.08))
            }
        }
    }

    // Only show posture icon when it changes from the previous action
    private func shouldShowPosture(action: RakatAction, index: Int, actions: [RakatAction]) -> Bool {
        guard action.posture != nil else { return false }
        if index == 0 { return true }

        // Walk back to find the last action that had a posture
        for i in stride(from: index - 1, through: 0, by: -1) {
            if let prevPosture = actions[i].posture {
                return action.posture != prevPosture
            }
        }
        return true
    }

    // MARK: - Notes

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            ForEach(Array(group.notes.enumerated()), id: \.offset) { _, note in
                HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                    Text("•")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
