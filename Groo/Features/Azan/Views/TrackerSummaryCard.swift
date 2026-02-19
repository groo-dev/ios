//
//  TrackerSummaryCard.swift
//  Groo
//
//  Compact tracker card showing streak, weekly progress, and navigation buttons.
//

import SwiftUI

struct TrackerSummaryCard: View {
    let trackingService: PrayerTrackingService

    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            if trackingService.totalPrayersLogged == 0 {
                emptyState
            } else {
                statsRow
            }

            Divider()

            HStack(spacing: Theme.Spacing.md) {
                NavigationLink {
                    PrayerAnalyticsView(trackingService: trackingService)
                } label: {
                    Label("View Details", systemImage: "chart.bar")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.Brand.primary)
                }

                Spacer()

                NavigationLink {
                    PrayerLogView(trackingService: trackingService)
                } label: {
                    Label("Log Prayers", systemImage: "calendar.badge.plus")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.Brand.primary)
                }
            }
        }
        .padding(Theme.Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.lg)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    private var emptyState: some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: "sparkles")
                .font(.title2)
                .foregroundStyle(Theme.Brand.primary)

            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text("Start Tracking")
                    .font(.subheadline.weight(.semibold))
                Text("Tap \"I prayed\" above to begin your journey")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }

    private var statsRow: some View {
        HStack(spacing: Theme.Spacing.lg) {
            HStack(spacing: Theme.Spacing.xs) {
                Image(systemName: "flame.fill")
                    .foregroundStyle(.orange)
                Text("\(trackingService.currentStreak) day streak")
                    .font(.subheadline.weight(.semibold))
            }

            Spacer()

            Text("This week: \(Int(trackingService.thisWeekPercent))%")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}
