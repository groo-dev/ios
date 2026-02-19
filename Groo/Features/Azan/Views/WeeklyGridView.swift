//
//  WeeklyGridView.swift
//  Groo
//
//  7-day circle grid showing daily prayer completion.
//

import SwiftUI

struct WeeklyGridView: View {
    let grid: [DaySummary]

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private static let shortDayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE"
        return f
    }()

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            ForEach(grid) { day in
                VStack(spacing: Theme.Spacing.xs) {
                    ZStack {
                        Circle()
                            .fill(dayColor(day).opacity(0.15))
                            .frame(width: 36, height: 36)

                        Circle()
                            .trim(from: 0, to: Double(day.completedCount) / Double(day.totalRequired))
                            .stroke(dayColor(day), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                            .frame(width: 36, height: 36)
                            .rotationEffect(.degrees(-90))

                        Text("\(day.completedCount)")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(dayColor(day))
                    }

                    Text(dayLabel(day))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func dayColor(_ day: DaySummary) -> Color {
        if day.completedCount == day.totalRequired { return Theme.Colors.success }
        if day.completedCount > 0 { return Theme.Colors.warning }
        return Color(.systemGray4)
    }

    private func dayLabel(_ day: DaySummary) -> String {
        guard let date = Self.dayFormatter.date(from: day.dateString) else { return "" }
        return Self.shortDayFormatter.string(from: date)
    }
}
