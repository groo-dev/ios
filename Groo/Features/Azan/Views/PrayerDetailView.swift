//
//  PrayerDetailView.swift
//  Groo
//
//  Interactive prayer guide sheet with madhab-aware rakat breakdown,
//  per-group niyyah, rakat-by-rakat walkthrough, and persona-based rules.
//

import SwiftUI

struct PrayerDetailView: View {
    let prayer: Prayer

    @AppStorage("prayerGuideMadhab") private var madhabRaw = FiqhMadhab.hanafi.rawValue
    @AppStorage("prayerGuideRole") private var roleRaw = PrayerRole.munfarid.rawValue
    @AppStorage("prayerGuideTraveling") private var isTraveling = false
    @AppStorage("prayerGuideQaza") private var isQaza = false

    @Environment(\.dismiss) private var dismiss

    private var madhab: FiqhMadhab {
        FiqhMadhab(rawValue: madhabRaw) ?? .hanafi
    }

    private var role: PrayerRole {
        PrayerRole(rawValue: roleRaw) ?? .munfarid
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    if let guide = PrayerGuideDataProvider.guide(for: prayer, madhab: madhab, role: role, isTraveling: isTraveling, isQaza: isQaza) {
                        VStack(spacing: Theme.Spacing.lg) {
                            headerSection(guide)
                            settingsSection
                            rakatSection(guide, scrollProxy: proxy)

                            // Per-group walkthroughs
                            ForEach(guide.groups) { group in
                                RakatGroupSectionView(group: group)
                                    .id(group.unit.id)
                            }

                            if !guide.generalNotes.isEmpty {
                                notesSection(guide)
                            }
                            disclaimerFooter
                        }
                        .padding(Theme.Spacing.lg)
                    } else {
                        madhabUnavailableView
                    }
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Prayer Guide")
                        .font(.headline)
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: - Header

    private func headerSection(_ guide: PrayerGuideData) -> some View {
        VStack(spacing: Theme.Spacing.sm) {
            Image(systemName: prayer.icon)
                .font(.title)
                .foregroundStyle(Theme.Brand.primary)

            Text(guide.arabicName)
                .font(.title2.bold())
                .environment(\.layoutDirection, .rightToLeft)

            Text("\(prayer.displayName)\(isQaza ? " · Qaza" : "") · \(guide.fardCount) Fard Rakats")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(Theme.Spacing.xl)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.lg)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    // MARK: - Settings (Madhab + Role + Travel)

    private var settingsSection: some View {
        VStack(spacing: Theme.Spacing.md) {
            // Madhab picker
            HStack {
                Text("Madhab")
                    .font(.subheadline.weight(.medium))
                Spacer()
                Picker("Madhab", selection: $madhabRaw) {
                    ForEach(FiqhMadhab.allCases) { m in
                        Text(m.displayName).tag(m.rawValue)
                    }
                }
                .pickerStyle(.menu)
                .tint(Theme.Brand.primary)
            }

            Divider()

            // Role picker
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text("Praying as")
                    .font(.subheadline.weight(.medium))

                HStack(spacing: Theme.Spacing.sm) {
                    ForEach(PrayerRole.allCases) { r in
                        Button {
                            withAnimation(.easeInOut(duration: Theme.Animation.fast)) {
                                roleRaw = r.rawValue
                            }
                        } label: {
                            HStack(spacing: Theme.Spacing.xs) {
                                Image(systemName: r.icon)
                                    .font(.caption)
                                Text(r.displayName)
                                    .font(.subheadline)
                            }
                            .padding(.horizontal, Theme.Spacing.md)
                            .padding(.vertical, Theme.Spacing.sm)
                            .background(
                                Capsule()
                                    .fill((isQaza ? .munfarid : role) == r ? Theme.Brand.primary : Color(.tertiarySystemGroupedBackground))
                            )
                            .foregroundStyle((isQaza ? .munfarid : role) == r ? .white : .primary)
                        }
                        .buttonStyle(.plain)
                        .disabled(isQaza)
                    }
                }
                .opacity(isQaza ? 0.5 : 1.0)
            }

            Divider()

            // Travel toggle
            Toggle(isOn: $isTraveling) {
                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: "airplane")
                        .font(.subheadline)
                        .foregroundStyle(isTraveling ? Theme.Brand.primary : .secondary)
                    Text("Traveling (Musāfir)")
                        .font(.subheadline.weight(.medium))
                }
            }
            .tint(Theme.Brand.primary)

            Divider()

            // Qaza (Makeup) toggle
            Toggle(isOn: $isQaza) {
                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.subheadline)
                        .foregroundStyle(isQaza ? Theme.Brand.primary : .secondary)
                    Text("Qaza (Makeup)")
                        .font(.subheadline.weight(.medium))
                }
            }
            .tint(Theme.Brand.primary)
        }
        .padding(Theme.Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.lg)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    // MARK: - Rakat Breakdown

    private func rakatSection(_ guide: PrayerGuideData, scrollProxy: ScrollViewProxy) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            sectionHeader("Rakat Breakdown")
            RakatBreakdownView(rakats: guide.rakatBreakdown) { unit in
                withAnimation {
                    scrollProxy.scrollTo(unit.id, anchor: .top)
                }
            }
        }
        .padding(Theme.Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.lg)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    // MARK: - Notes

    private func notesSection(_ guide: PrayerGuideData) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            sectionHeader("Notes")

            ForEach(Array(guide.generalNotes.enumerated()), id: \.offset) { _, note in
                HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                    Text("•")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(note)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(Theme.Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.lg)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    // MARK: - Disclaimer

    private var disclaimerFooter: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "info.circle")
                .font(.caption)
            Text("Consult a qualified scholar for detailed rulings.")
                .font(.caption)
        }
        .foregroundStyle(.tertiary)
        .frame(maxWidth: .infinity)
        .padding(.top, Theme.Spacing.sm)
    }

    // MARK: - Madhab Unavailable

    private var madhabUnavailableView: some View {
        VStack(spacing: Theme.Spacing.lg) {
            settingsSection

            VStack(spacing: Theme.Spacing.md) {
                Image(systemName: "book.closed")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                Text("\(madhab.displayName) guide coming soon")
                    .font(.headline)
                Text("Switch to Hanafi for the full prayer guide, or check back in a future update.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(Theme.Spacing.xxl)
        }
        .padding(Theme.Spacing.lg)
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .tracking(0.5)
    }
}
