//
//  PrayerBreakdownChart.swift
//  Groo
//
//  Per-prayer horizontal bars showing on-time vs qaza rates over 30 days.
//

import SwiftUI

struct PrayerBreakdownChart: View {
    let stats: [PrayerStat]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            ForEach(stats) { stat in
                HStack(spacing: Theme.Spacing.md) {
                    Text(stat.prayer.displayName)
                        .font(.caption.weight(.medium))
                        .frame(width: 55, alignment: .leading)

                    GeometryReader { geometry in
                        HStack(spacing: 0) {
                            // On-time segment (green)
                            if stat.onTimePercent > 0 {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Theme.Colors.success)
                                    .frame(width: max(geometry.size.width * stat.onTimePercent, 2))
                            }

                            // Qaza segment (orange)
                            if stat.latePercent > 0 {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Theme.Colors.warning)
                                    .frame(width: max(geometry.size.width * stat.latePercent, 2))
                            }

                            Spacer(minLength: 0)
                        }
                    }
                    .frame(height: 12)
                    .background(
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color(.systemGray6))
                    )

                    Text("\(Int((stat.onTimePercent + stat.latePercent) * 100))%")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 32, alignment: .trailing)
                }
            }
        }
    }
}
