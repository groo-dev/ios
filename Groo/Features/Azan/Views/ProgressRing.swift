//
//  ProgressRing.swift
//  Groo
//
//  Circular progress indicator for today's prayer completion (X/5).
//

import SwiftUI

struct ProgressRing: View {
    let completed: Int
    let total: Int
    var size: CGFloat = 40
    var lineWidth: CGFloat = 4

    private var progress: Double {
        total > 0 ? Double(completed) / Double(total) : 0
    }

    private var ringColor: Color {
        if completed == total { return Theme.Colors.success }
        if completed > 0 { return Theme.Brand.primary }
        return Color(.systemGray4)
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color(.systemGray5), lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(ringColor, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: Theme.Animation.normal), value: progress)

            Text("\(completed)")
                .font(.system(size: size * 0.32, weight: .bold, design: .rounded))
                .foregroundStyle(completed == total ? Theme.Colors.success : .primary)
        }
        .frame(width: size, height: size)
    }
}
