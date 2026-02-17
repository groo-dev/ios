//
//  RakatBreakdownView.swift
//  Groo
//
//  Visual rakat table with colored dots per category. Tappable rows for scroll-to-group.
//

import SwiftUI

struct RakatBreakdownView: View {
    let rakats: [RakatUnit]
    var onTapGroup: ((RakatUnit) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            ForEach(rakats) { unit in
                Button {
                    onTapGroup?(unit)
                } label: {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: Theme.Spacing.md) {
                            Circle()
                                .fill(unit.category.color)
                                .frame(width: 10, height: 10)

                            Text(unit.category.shortName)
                                .font(.subheadline)
                                .foregroundStyle(unit.isOptional ? .secondary : .primary)

                            Spacer()

                            if !unit.timing.rawValue.isEmpty {
                                Text(unit.timing.rawValue)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Text("\(unit.count)")
                                .font(.subheadline.weight(.semibold).monospacedDigit())
                                .frame(width: 24, alignment: .trailing)

                            if onTapGroup != nil {
                                Image(systemName: "chevron.right")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }

                        if unit.isOptional {
                            Text("Optional")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .padding(.leading, 22)
                        }

                        if let notes = unit.notes {
                            Text(notes)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .padding(.leading, 22)
                        }
                    }
                }
                .buttonStyle(.plain)
            }

            Divider()
                .padding(.vertical, Theme.Spacing.xxs)

            // Total
            HStack {
                Text("Total")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(totalCount) rakats")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
            }
        }
        .animation(.easeInOut(duration: Theme.Animation.normal), value: rakats.map(\.count))
    }

    private var totalCount: Int {
        rakats.reduce(0) { $0 + $1.count }
    }
}
