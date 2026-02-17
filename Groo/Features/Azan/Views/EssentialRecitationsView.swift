//
//  EssentialRecitationsView.swift
//  Groo
//
//  Expandable list of essential prayer recitations with full Arabic,
//  transliteration, and translation, with audio playback.
//

import SwiftUI

// MARK: - Sheet Wrapper

struct EssentialRecitationsSheet: View {
    @State private var expandedId: String?
    @Environment(\.dismiss) private var dismiss

    private var audioService: RecitationAudioService { .shared }

    var body: some View {
        NavigationStack {
            ScrollView {
                EssentialRecitationsView(
                    recitations: PrayerGuideDataProvider.essentialRecitations(),
                    expandedId: $expandedId,
                    audioService: audioService
                )
            }
            .background(Color(.systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Essential Recitations")
                        .font(.headline)
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") {
                        audioService.stop()
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - List View

struct EssentialRecitationsView: View {
    let recitations: [PrayerRecitation]

    @Binding var expandedId: String?
    let audioService: RecitationAudioService

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(recitations.enumerated()), id: \.element.id) { index, recitation in
                if index > 0 {
                    Divider()
                        .padding(.leading, Theme.Spacing.lg)
                }

                recitationRow(recitation)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.lg)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .padding(Theme.Spacing.lg)
    }

    // MARK: - Row

    private func recitationRow(_ recitation: PrayerRecitation) -> some View {
        let isExpanded = expandedId == recitation.id

        return VStack(alignment: .leading, spacing: 0) {
            // Header row
            Button {
                withAnimation(.easeInOut(duration: Theme.Animation.fast)) {
                    expandedId = isExpanded ? nil : recitation.id
                }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                        Text(recitation.name)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                    }

                    Spacer()

                    Text(recitation.usedIn)
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, Theme.Spacing.sm)
                        .padding(.vertical, Theme.Spacing.xxs)
                        .background(Capsule().fill(Theme.Brand.primary.opacity(0.12)))
                        .foregroundStyle(Theme.Brand.primary)

                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .padding(.vertical, Theme.Spacing.md)
                .padding(.horizontal, Theme.Spacing.lg)
            }
            .buttonStyle(.plain)

            // Expanded content
            if isExpanded {
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    // Audio play button
                    if let fileName = recitation.audioFileName {
                        audioButton(fileName: fileName)
                    }

                    // Arabic
                    Text(recitation.arabicText)
                        .font(.callout)
                        .environment(\.layoutDirection, .rightToLeft)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .lineSpacing(6)

                    // Transliteration
                    Text(recitation.transliteration)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .italic()
                        .lineSpacing(4)

                    // Translation
                    Text(recitation.translation)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineSpacing(4)
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.bottom, Theme.Spacing.lg)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    // MARK: - Audio Button

    private func audioButton(fileName: String) -> some View {
        let isPlaying = audioService.isCurrentlyPlaying(fileName)

        return Button {
            audioService.play(fileName)
        } label: {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: isPlaying ? "stop.fill" : "play.fill")
                    .font(.caption)
                Text(isPlaying ? "Stop" : "Play Audio")
                    .font(.caption.weight(.medium))
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
            .background(
                Capsule().fill(isPlaying ? Color.red.opacity(0.12) : Theme.Brand.primary.opacity(0.12))
            )
            .foregroundStyle(isPlaying ? .red : Theme.Brand.primary)
        }
        .buttonStyle(.plain)
    }
}
