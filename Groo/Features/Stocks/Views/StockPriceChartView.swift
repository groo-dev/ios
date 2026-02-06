//
//  StockPriceChartView.swift
//  Groo
//
//  Stock price chart using Swift Charts with gradient fill and touch-to-scrub.
//

import SwiftUI
import Charts

struct StockPriceChartView: View {
    let data: [StockPricePoint]
    let isLoading: Bool
    let isPositive: Bool
    var errorMessage: String? = nil
    var currencyCode: String = "USD"
    var timeframe: StockChartTimeframe = .day
    var tradingPeriod: TradingPeriod? = nil

    @State private var selectedPoint: StockPricePoint?

    private var chartColor: Color {
        isPositive ? .green : .red
    }

    private var minPrice: Double {
        data.map(\.price).min() ?? 0
    }

    private var maxPrice: Double {
        data.map(\.price).max() ?? 0
    }

    var body: some View {
        ZStack {
            if isLoading && data.isEmpty {
                ProgressView()
            } else if !isLoading && data.isEmpty {
                VStack(spacing: 4) {
                    Text("No chart data")
                        .font(.caption)
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption2)
                    }
                }
                .foregroundStyle(.secondary)
            } else {
                chart
                    .chartOverlay { proxy in
                        GeometryReader { geometry in
                            Rectangle()
                                .fill(.clear)
                                .contentShape(Rectangle())
                                .gesture(
                                    DragGesture(minimumDistance: 0)
                                        .onChanged { value in
                                            let x = value.location.x
                                            if let date: Date = proxy.value(atX: x) {
                                                selectedPoint = data.min(by: {
                                                    abs($0.timestamp.timeIntervalSince(date)) < abs($1.timestamp.timeIntervalSince(date))
                                                })
                                            }
                                        }
                                        .onEnded { _ in
                                            selectedPoint = nil
                                        }
                                )
                        }
                    }
            }

            // Loading overlay (when refreshing with existing chart)
            if isLoading && !data.isEmpty {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(Theme.Spacing.sm)
            }

            // Scrub overlay
            if let point = selectedPoint {
                VStack(spacing: 2) {
                    Text(formatPrice(point.price))
                        .font(.caption.bold())
                    Text(formatDate(point.timestamp))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, Theme.Spacing.sm)
                .padding(.vertical, Theme.Spacing.xs)
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.leading, Theme.Spacing.sm)
            }
        }
    }

    private var chart: some View {
        Chart(data) { point in
            LineMark(
                x: .value("Time", point.timestamp),
                y: .value("Price", point.price)
            )
            .foregroundStyle(chartColor)
            .interpolationMethod(.catmullRom)

            AreaMark(
                x: .value("Time", point.timestamp),
                yStart: .value("Min", minPrice),
                yEnd: .value("Price", point.price)
            )
            .foregroundStyle(
                LinearGradient(
                    gradient: Gradient(colors: [
                        chartColor.opacity(0.3),
                        chartColor.opacity(0.0)
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .interpolationMethod(.catmullRom)

            if let selected = selectedPoint {
                RuleMark(x: .value("Selected", selected.timestamp))
                    .foregroundStyle(chartColor.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))

                PointMark(
                    x: .value("Selected", selected.timestamp),
                    y: .value("Price", selected.price)
                )
                .symbol(Circle())
                .symbolSize(36)
                .foregroundStyle(chartColor)
            }

            if let tp = tradingPeriod {
                RuleMark(x: .value("Open", tp.open))
                    .foregroundStyle(.secondary.opacity(0.4))
                    .lineStyle(StrokeStyle(lineWidth: 0.5, dash: [3, 4]))
                    .annotation(position: .topLeading, spacing: 2) {
                        Text("Open")
                            .font(.system(size: 8))
                            .foregroundStyle(.secondary)
                    }

                RuleMark(x: .value("Close", tp.close))
                    .foregroundStyle(.secondary.opacity(0.4))
                    .lineStyle(StrokeStyle(lineWidth: 0.5, dash: [3, 4]))
                    .annotation(position: .topTrailing, spacing: 2) {
                        Text("Close")
                            .font(.system(size: 8))
                            .foregroundStyle(.secondary)
                    }
            }
        }
        .chartXAxis {
            switch timeframe {
            case .day:
                AxisMarks(values: .stride(by: .hour, count: 4)) { _ in
                    AxisValueLabel(format: .dateTime.hour(.defaultDigits(amPM: .abbreviated)))
                }
            case .week:
                AxisMarks(values: .stride(by: .day)) { _ in
                    AxisValueLabel(format: .dateTime.weekday(.abbreviated))
                }
            case .month:
                AxisMarks(values: .stride(by: .day, count: 7)) { _ in
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                }
            case .sixMonth:
                AxisMarks(values: .stride(by: .month)) { _ in
                    AxisValueLabel(format: .dateTime.month(.abbreviated))
                }
            case .year:
                AxisMarks(values: .stride(by: .month, count: 3)) { _ in
                    AxisValueLabel(format: .dateTime.month(.abbreviated))
                }
            }
        }
        .chartYAxis(.hidden)
        .chartYScale(domain: minPrice * 0.999 ... maxPrice * 1.001)
        .animation(.easeInOut(duration: 0.3), value: data.map(\.price))
    }

    // MARK: - Formatting

    private func formatPrice(_ price: Double) -> String {
        CurrencyFormatter.format(price, currencyCode: currencyCode)
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
