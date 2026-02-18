//
//  AzanView.swift
//  Groo
//
//  Main Azan tab: next prayer hero card, today's prayer times list,
//  Ramadan mode with fasting info.
//

import SwiftUI
import WidgetKit

struct AzanView: View {
    @State private var prayerService = PrayerTimeService()
    @State private var locationService = AzanLocationService()
    @State private var notificationService = AzanNotificationService()
    @State private var audioService = AzanAudioService()
    @State private var preferences: LocalAzanPreferences?
    @State private var showSettings = false
    @State private var selectedPrayer: Prayer?
    @State private var showRecitations = false
    @State private var showSurahs = false
    @State private var showDuas = false

    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Spacing.lg) {
                    // Next prayer hero
                    if let countdown = prayerService.nextPrayer {
                        nextPrayerCard(countdown)
                    }

                    // Ramadan banner
                    if let ramadan = prayerService.ramadanInfo {
                        ramadanCard(ramadan)
                    }

                    // Today's prayer times
                    prayerTimesCard

                    // Prayer reference
                    referenceCard

                    // Audio playback (shown when playing)
                    if audioService.isPlaying {
                        audioCard
                    }

                    // Location info
                    if !locationService.locationName.isEmpty {
                        locationCard
                    }
                }
                .padding(Theme.Spacing.lg)
            }
            .background(Color(.systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Azan")
                        .font(.headline)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gear")
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                NavigationStack {
                    AzanSettingsView(
                        preferences: preferences ?? LocalAzanPreferences(),
                        locationService: locationService,
                        onSave: { updatedPrefs in
                            savePreferences(updatedPrefs)
                        }
                    )
                }
            }
            .sheet(item: $selectedPrayer) { prayer in
                PrayerDetailView(prayer: prayer)
            }
            .sheet(isPresented: $showRecitations) {
                EssentialRecitationsSheet()
            }
            .sheet(isPresented: $showSurahs) {
                ShortSurahsSheet()
            }
            .sheet(isPresented: $showDuas) {
                DailyDuasSheet()
            }
        }
        .onAppear { loadAndConfigure() }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                prayerService.recalculate()
                Task { await rescheduleNotifications() }
            }
        }
    }

    // MARK: - Next Prayer Hero

    private func nextPrayerCard(_ countdown: PrayerCountdown) -> some View {
        VStack(spacing: Theme.Spacing.md) {
            // Show "Time until Iftar" during Ramadan fasting hours
            if let ramadan = prayerService.ramadanInfo, ramadan.isRamadan, countdown.prayer == .maghrib {
                Text("Time until Iftar")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text("Next Prayer")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Text(countdown.displayName)
                .font(.title2.bold())

            Text(countdown.formattedCountdown)
                .font(.system(size: 48, weight: .bold, design: .monospaced))
                .foregroundStyle(Theme.Brand.primary)

            Text(countdown.formattedTime)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            // Qaza countdown
            if let deadline = prayerService.currentPrayerDeadline, deadline.remaining > 0 {
                Divider()
                    .padding(.horizontal, Theme.Spacing.lg)

                HStack(spacing: Theme.Spacing.xs) {
                    Image(systemName: deadline.urgency == .plenty
                          ? "exclamationmark.circle"
                          : "exclamationmark.circle.fill")
                        .font(.caption2)
                    Text("\(deadline.prayer.displayName) ends in \(deadline.formattedRemaining)")
                        .font(.subheadline)
                }
                .foregroundStyle(deadline.urgency.color)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(Theme.Spacing.xl)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.lg)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    // MARK: - Ramadan Card

    private func ramadanCard(_ ramadan: RamadanInfo) -> some View {
        VStack(spacing: Theme.Spacing.sm) {
            HStack {
                Image(systemName: "moon.stars.fill")
                    .foregroundStyle(Theme.Brand.primary)
                Text(ramadan.dayLabel)
                    .font(.headline)
                Spacer()
            }

            if let duration = ramadan.formattedFastingDuration {
                HStack {
                    Text("Fasting Duration")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(duration)
                        .font(.subheadline.bold())
                }
            }

            HStack {
                if let suhoor = ramadan.suhoorTime {
                    VStack(alignment: .leading) {
                        Text("Suhoor ends")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(formatTime(suhoor))
                            .font(.subheadline.bold())
                    }
                }
                Spacer()
                if let iftar = ramadan.iftarTime {
                    VStack(alignment: .trailing) {
                        Text("Iftar")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(formatTime(iftar))
                            .font(.subheadline.bold())
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

    // MARK: - Prayer Times List

    private var prayerTimesCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Today")
                    .font(.headline)
                Spacer()
                Text(Date(), style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)

            Divider()

            let prayers = prayerService.todayPrayers
            ForEach(prayers) { entry in
                PrayerTimeRow(entry: entry, onToggleNotification: { prayer in
                    toggleNotification(for: prayer)
                }, onTapPrayer: { prayer in
                    selectedPrayer = prayer
                })

                if entry.id != prayers.last?.id {
                    Divider()
                        .padding(.horizontal, Theme.Spacing.md)
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.lg)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    // MARK: - Reference Card

    private var referenceCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            referenceRow(icon: "text.book.closed", title: "Essential Recitations", subtitle: "Full texts you need to memorize") {
                showRecitations = true
            }

            Divider()
                .padding(.leading, Theme.Spacing.lg + 24 + Theme.Spacing.md)

            referenceRow(icon: "book.pages", title: "Short Surahs", subtitle: "For recitation after al-Fatihah") {
                showSurahs = true
            }

            Divider()
                .padding(.leading, Theme.Spacing.lg + 24 + Theme.Spacing.md)

            referenceRow(icon: "hands.and.sparkles.fill", title: "Daily Duas", subtitle: "Supplications for everyday moments") {
                showDuas = true
            }
        }
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.lg)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    // MARK: - Reference Row

    private func referenceRow(icon: String, title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.md) {
                Image(systemName: icon)
                    .font(.subheadline)
                    .foregroundStyle(Theme.Brand.primary)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                    Text(title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.vertical, Theme.Spacing.md)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Audio Card

    private var audioCard: some View {
        HStack {
            Image(systemName: "speaker.wave.3.fill")
                .foregroundStyle(Theme.Brand.primary)

            Text("Playing \(audioService.currentPrayer?.displayName ?? "Azan")")
                .font(.subheadline)

            Spacer()

            Button {
                audioService.stopAzan()
            } label: {
                Image(systemName: "stop.fill")
                    .foregroundStyle(.primary)
                    .frame(width: Theme.Size.iconButtonSize, height: Theme.Size.iconButtonSize)
            }
        }
        .padding(Theme.Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.lg)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    // MARK: - Location Card

    private var locationCard: some View {
        HStack {
            Image(systemName: "location.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(locationService.locationName)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, Theme.Spacing.md)
    }

    // MARK: - Actions

    private func loadAndConfigure() {
        let store = LocalStore.shared
        preferences = store.getAzanPreferences()

        if preferences == nil {
            let newPrefs = LocalAzanPreferences()
            store.saveAzanPreferences(newPrefs)
            preferences = newPrefs
        }

        guard let prefs = preferences else { return }

        prefs.syncToAppGroup()

        if prefs.useDeviceLocation {
            Task {
                await locationService.requestLocation()
                if locationService.hasLocation {
                    prayerService.configure(
                        latitude: locationService.latitude,
                        longitude: locationService.longitude,
                        preferences: prefs
                    )
                    // Save location back to preferences
                    prefs.latitude = locationService.latitude
                    prefs.longitude = locationService.longitude
                    prefs.locationName = locationService.locationName
                    store.saveAzanChanges()
                    prefs.syncToAppGroup()

                    await rescheduleNotifications()
                }
            }
        } else if prefs.latitude != 0 || prefs.longitude != 0 {
            locationService.setManualLocation(
                latitude: prefs.latitude,
                longitude: prefs.longitude,
                name: prefs.locationName
            )
            prayerService.configure(
                latitude: prefs.latitude,
                longitude: prefs.longitude,
                preferences: prefs
            )
            Task { await rescheduleNotifications() }
        }
    }

    private func toggleNotification(for prayer: Prayer) {
        guard let prefs = preferences else { return }

        switch prayer {
        case .fajr: prefs.fajrNotification.toggle()
        case .sunrise: prefs.sunriseNotification.toggle()
        case .dhuhr: prefs.dhuhrNotification.toggle()
        case .asr: prefs.asrNotification.toggle()
        case .sunset: prefs.sunsetNotification.toggle()
        case .maghrib: prefs.maghribNotification.toggle()
        case .isha: prefs.ishaNotification.toggle()
        }

        LocalStore.shared.saveAzanChanges()
        prayerService.recalculate()
        Task { await rescheduleNotifications() }
    }

    private func savePreferences(_ updatedPrefs: LocalAzanPreferences) {
        preferences = updatedPrefs
        LocalStore.shared.saveAzanPreferences(updatedPrefs)

        let lat = updatedPrefs.useDeviceLocation ? locationService.latitude : updatedPrefs.latitude
        let lon = updatedPrefs.useDeviceLocation ? locationService.longitude : updatedPrefs.longitude

        prayerService.configure(latitude: lat, longitude: lon, preferences: updatedPrefs)
        updatedPrefs.syncToAppGroup()
        WidgetCenter.shared.reloadTimelines(ofKind: "AzanWidget")
        Task { await rescheduleNotifications() }
    }

    private func rescheduleNotifications() async {
        guard let prefs = preferences else { return }
        await notificationService.scheduleNotifications(prayerService: prayerService, preferences: prefs)
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }
}
