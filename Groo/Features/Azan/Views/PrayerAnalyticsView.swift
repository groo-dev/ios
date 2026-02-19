//
//  PrayerAnalyticsView.swift
//  Groo
//
//  Full prayer tracking analytics: stats, weekly grid, per-prayer breakdown.
//

import SwiftUI

struct PrayerAnalyticsView: View {
    let trackingService: PrayerTrackingService

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.lg) {
                // Stats summary grid
                statsGrid

                // Weekly grid
                weeklyCard

                // Per-prayer breakdown
                breakdownCard

                // View full history
                NavigationLink {
                    PrayerLogView(trackingService: trackingService)
                } label: {
                    HStack {
                        Text("View Full History")
                            .font(.subheadline.weight(.medium))
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .foregroundStyle(Theme.Brand.primary)
                    .padding(Theme.Spacing.lg)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.Radius.lg)
                            .fill(Color(.secondarySystemGroupedBackground))
                    )
                }
            }
            .padding(Theme.Spacing.lg)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Prayer Analytics")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { trackingService.recalculate() }
    }

    // MARK: - Stats Grid

    private var statsGrid: some View {
        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible()),
            GridItem(.flexible()),
        ], spacing: Theme.Spacing.md) {
            statCell(value: "\(trackingService.currentStreak)", label: "Current Streak", icon: "flame.fill", color: .orange)
            statCell(value: "\(trackingService.bestStreak)", label: "Best Streak", icon: "trophy.fill", color: .yellow)
            statCell(value: "\(Int(trackingService.thisWeekPercent))%", label: "This Week", icon: "calendar", color: Theme.Brand.primary)
            statCell(value: "\(Int(trackingService.thisMonthPercent))%", label: "This Month", icon: "calendar.badge.clock", color: Theme.Brand.primary)
            statCell(value: "\(Int(trackingService.onTimeRate))%", label: "On-Time Rate", icon: "checkmark.circle", color: Theme.Colors.success)
            statCell(value: "\(trackingService.totalPrayersLogged)", label: "Total Logged", icon: "number", color: .blue)
        }
        .padding(Theme.Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.lg)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    private func statCell(value: String, label: String, icon: String, color: Color) -> some View {
        VStack(spacing: Theme.Spacing.xs) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(color)

            Text(value)
                .font(.title3.weight(.bold))
                .foregroundStyle(.primary)

            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.sm)
    }

    // MARK: - Weekly Card

    private var weeklyCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Last 7 Days")
                .font(.subheadline.weight(.semibold))

            WeeklyGridView(grid: trackingService.weeklyGrid)
                .frame(maxWidth: .infinity)
        }
        .padding(Theme.Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.lg)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    // MARK: - Breakdown Card

    private var breakdownCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("30-Day Breakdown")
                .font(.subheadline.weight(.semibold))

            if trackingService.perPrayerStats.isEmpty {
                Text("No data yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, Theme.Spacing.lg)
            } else {
                PrayerBreakdownChart(stats: trackingService.perPrayerStats)

                HStack(spacing: Theme.Spacing.lg) {
                    HStack(spacing: Theme.Spacing.xs) {
                        Circle()
                            .fill(Theme.Colors.success)
                            .frame(width: 8, height: 8)
                        Text("On Time")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    HStack(spacing: Theme.Spacing.xs) {
                        Circle()
                            .fill(Theme.Colors.warning)
                            .frame(width: 8, height: 8)
                        Text("Qaza")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(Theme.Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.lg)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }
}
