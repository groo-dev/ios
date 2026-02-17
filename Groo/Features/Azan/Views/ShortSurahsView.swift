//
//  ShortSurahsView.swift
//  Groo
//
//  Expandable list of short surahs for recitation after al-Fatihah,
//  with full Arabic, transliteration, translation, and audio playback.
//

import SwiftUI

// MARK: - Sheet Wrapper

struct ShortSurahsSheet: View {
    @State private var expandedId: Int?
    @Environment(\.dismiss) private var dismiss

    private var audioService: RecitationAudioService { .shared }

    var body: some View {
        NavigationStack {
            ScrollView {
                ShortSurahsView(
                    surahs: PrayerGuideDataProvider.shortSurahs(),
                    expandedId: $expandedId,
                    audioService: audioService
                )
            }
            .background(Color(.systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Short Surahs")
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

struct ShortSurahsView: View {
    let surahs: [ShortSurah]

    @Binding var expandedId: Int?
    let audioService: RecitationAudioService

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(surahs.enumerated()), id: \.element.id) { index, surah in
                if index > 0 {
                    Divider()
                        .padding(.leading, Theme.Spacing.lg)
                }

                surahRow(surah)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.lg)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .padding(Theme.Spacing.lg)
    }

    // MARK: - Row

    private func surahRow(_ surah: ShortSurah) -> some View {
        let isExpanded = expandedId == surah.id

        return VStack(alignment: .leading, spacing: 0) {
            // Header row
            HStack {
                // Tap area for expand/collapse
                Button {
                    withAnimation(.easeInOut(duration: Theme.Animation.fast)) {
                        expandedId = isExpanded ? nil : surah.id
                    }
                } label: {
                    HStack(spacing: Theme.Spacing.sm) {
                        Text("\(surah.id)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Theme.Brand.primary)
                            .frame(width: 28, alignment: .center)

                        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                            HStack(spacing: Theme.Spacing.sm) {
                                Text(surah.name)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(.primary)

                                Text(surah.arabicName)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }

                            Text("\(surah.verseCount) verses")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.tertiary)
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    }
                }
                .buttonStyle(.plain)

                // Play button (always visible)
                audioButton(fileName: surah.audioFileName)
            }
            .padding(.vertical, Theme.Spacing.md)
            .padding(.horizontal, Theme.Spacing.lg)

            // Expanded content
            if isExpanded {
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    // Arabic
                    Text(surah.arabicText)
                        .font(.callout)
                        .environment(\.layoutDirection, .rightToLeft)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .lineSpacing(6)

                    // Transliteration
                    Text(surah.transliteration)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .italic()
                        .lineSpacing(4)

                    // Translation
                    Text(surah.translation)
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
            Image(systemName: isPlaying ? "stop.fill" : "play.fill")
                .font(.caption)
                .foregroundStyle(isPlaying ? .red : Theme.Brand.primary)
                .frame(width: Theme.Size.minTapTarget, height: Theme.Size.minTapTarget)
        }
        .buttonStyle(.plain)
    }
}
