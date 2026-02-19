//
//  PrayerLogView.swift
//  Groo
//
//  Infinite-scroll timeline for viewing and logging prayer history.
//  Pre-generates lightweight day skeletons, fetches logs lazily per month.
//

import SwiftUI

struct PrayerLogView: View {
    let trackingService: PrayerTrackingService

    @State private var months: [MonthData] = []
    @State private var loadedLogs: [String: [Prayer: PrayerStatus]] = [:]
    @State private var showDatePicker = false
    @State private var jumpDate = Date()
    @State private var scrollTarget: String?

    private let prayers: [Prayer] = Prayer.notifiable
    private let calendar = Calendar.current
    private let startYear = 2015

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private static let monthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMMM yyyy"
        return f
    }()

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE, MMM d"
        return f
    }()

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                    ForEach(months) { month in
                        Section {
                            ForEach(month.days) { day in
                                dayRow(day)
                                    .id(day.dateString)

                                if day.dateString != month.days.last?.dateString {
                                    Divider()
                                        .padding(.horizontal, Theme.Spacing.md)
                                }
                            }
                        } header: {
                            monthHeader(month)
                        }
                        .onAppear {
                            loadLogsForMonth(month)
                        }
                    }
                }
                .padding(.bottom, Theme.Spacing.lg)
            }
            .defaultScrollAnchor(.bottom)
            .background(Color(.systemGroupedBackground))
            .onChange(of: scrollTarget) { _, target in
                if let target {
                    withAnimation {
                        proxy.scrollTo(target, anchor: .center)
                    }
                    scrollTarget = nil
                }
            }
        }
        .navigationTitle("Prayer Log")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showDatePicker = true
                } label: {
                    Image(systemName: "calendar")
                }
            }
        }
        .sheet(isPresented: $showDatePicker) {
            jumpToDateSheet
        }
        .onAppear {
            if months.isEmpty {
                buildAllMonths()
            }
        }
    }

    // MARK: - Month Header

    private func monthHeader(_ month: MonthData) -> some View {
        HStack {
            Text(month.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.sm)
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - Day Row

    private func dayRow(_ day: DayData) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            VStack(alignment: .leading, spacing: 0) {
                Text(day.dayLabel)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(day.isToday ? Theme.Brand.primary : .primary)
            }
            .frame(width: 90, alignment: .leading)

            HStack(spacing: Theme.Spacing.sm) {
                ForEach(prayers) { prayer in
                    prayerIndicator(prayer: prayer, day: day)
                }
            }

            Spacer()
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.sm)
                .fill(day.isToday ? Theme.Brand.primary.opacity(0.05) : .clear)
        )
    }

    // MARK: - Prayer Indicator

    private func prayerIndicator(prayer: Prayer, day: DayData) -> some View {
        let status = loadedLogs[day.dateString]?[prayer]
        let initial = String(prayer.displayName.prefix(1))

        return Menu {
            Button {
                trackingService.logPrayer(dateString: day.dateString, prayer: prayer, status: .onTime)
                reloadLogsForDay(day.dateString)
            } label: {
                Label("On Time", systemImage: "checkmark.circle.fill")
            }

            Button {
                trackingService.logPrayer(dateString: day.dateString, prayer: prayer, status: .late)
                reloadLogsForDay(day.dateString)
            } label: {
                Label("Qaza", systemImage: "clock.arrow.circlepath")
            }

            if status != nil {
                Divider()
                Button(role: .destructive) {
                    trackingService.removePrayerLog(dateString: day.dateString, prayer: prayer)
                    reloadLogsForDay(day.dateString)
                } label: {
                    Label("Clear", systemImage: "xmark.circle")
                }
            }
        } label: {
            Text(initial)
                .font(.caption2.weight(.bold))
                .frame(width: 28, height: 28)
                .foregroundStyle(status != nil ? .white : .secondary)
                .background(
                    Circle()
                        .fill(status?.color ?? Color(.systemGray5))
                )
        }
    }

    // MARK: - Jump to Date

    private var jumpToDateSheet: some View {
        NavigationStack {
            DatePicker("Go to date", selection: $jumpDate, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .padding(Theme.Spacing.lg)
                .navigationTitle("Jump to Date")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showDatePicker = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Go") {
                            showDatePicker = false
                            scrollTarget = Self.dateFormatter.string(from: jumpDate)
                        }
                    }
                }
        }
        .presentationDetents([.medium])
    }

    // MARK: - Data

    private func buildAllMonths() {
        let today = Date()
        let todayString = Self.dateFormatter.string(from: today)
        let currentYear = calendar.component(.year, from: today)
        let currentMonth = calendar.component(.month, from: today)

        var result: [MonthData] = []
        var comps = DateComponents()

        for year in startYear...currentYear {
            let lastMonth = (year == currentYear) ? currentMonth : 12
            for month in 1...lastMonth {
                comps.year = year
                comps.month = month
                comps.day = 1
                guard let startOfMonth = calendar.date(from: comps) else { continue }

                let range = calendar.range(of: .day, in: .month, for: startOfMonth)!
                let title = Self.monthFormatter.string(from: startOfMonth)
                let monthId = String(format: "%04d-%02d", year, month)

                var days: [DayData] = []
                for day in range {
                    comps.day = day
                    guard let date = calendar.date(from: comps) else { continue }
                    let ds = Self.dateFormatter.string(from: date)
                    if ds > todayString { break }

                    days.append(DayData(
                        dateString: ds,
                        dayLabel: Self.dayFormatter.string(from: date),
                        isToday: ds == todayString
                    ))
                }

                if !days.isEmpty {
                    result.append(MonthData(id: monthId, title: title, days: days))
                }
            }
        }

        months = result
    }

    private func loadLogsForMonth(_ month: MonthData) {
        // Skip if already loaded
        guard let first = month.days.first,
              loadedLogs[first.dateString] == nil else { return }

        let components = month.id.split(separator: "-")
        guard components.count == 2,
              let year = Int(components[0]),
              let m = Int(components[1]) else { return }

        let monthLogs = trackingService.logsForMonth(year: year, month: m)
        for (dateString, prayerLogs) in monthLogs {
            loadedLogs[dateString] = prayerLogs
        }
        // Mark empty days as loaded too (empty dict)
        for day in month.days where loadedLogs[day.dateString] == nil {
            loadedLogs[day.dateString] = [:]
        }
    }

    private func reloadLogsForDay(_ dateString: String) {
        let components = dateString.split(separator: "-")
        guard components.count == 3,
              let year = Int(components[0]),
              let month = Int(components[1]) else { return }

        let monthLogs = trackingService.logsForMonth(year: year, month: month)
        // Update all days in the month
        let monthId = String(format: "%04d-%02d", year, month)
        if let monthData = months.first(where: { $0.id == monthId }) {
            for day in monthData.days {
                loadedLogs[day.dateString] = monthLogs[day.dateString] ?? [:]
            }
        }
    }
}

// MARK: - Data Types

private struct MonthData: Identifiable {
    let id: String
    let title: String
    let days: [DayData]
}

private struct DayData: Identifiable {
    let dateString: String
    let dayLabel: String
    let isToday: Bool

    var id: String { dateString }
}
