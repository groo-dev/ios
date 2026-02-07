//
//  SparklineView.swift
//  Groo
//
//  Minimal Swift Charts sparkline for dashboard cards.
//

import Charts
import SwiftUI

struct SparklineView: View {
    let data: [Double]
    let color: Color

    var body: some View {
        Chart {
            ForEach(Array(data.enumerated()), id: \.offset) { index, value in
                LineMark(
                    x: .value("", index),
                    y: .value("", value)
                )
                .interpolationMethod(.catmullRom)

                AreaMark(
                    x: .value("", index),
                    y: .value("", value)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(
                    LinearGradient(
                        colors: [color.opacity(0.3), color.opacity(0.0)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .foregroundStyle(color)
    }
}
