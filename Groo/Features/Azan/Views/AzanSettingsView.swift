//
//  AzanSettingsView.swift
//  Groo
//
//  Settings for prayer time calculation, notifications, and audio.
//

import SwiftUI

struct AzanSettingsView: View {
    @State var preferences: LocalAzanPreferences
    let locationService: AzanLocationService
    let onSave: (LocalAzanPreferences) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var selectedMethod: AzanCalculationMethod
    @State private var selectedMadhab: AzanMadhab
    @State private var showLocationSearch = false
    @State private var showSoundPicker: SoundPickerType?
    @State private var audioService = AzanAudioService()

    enum SoundPickerType: Identifiable {
        case notification, fajr
        var id: Self { self }
    }

    init(preferences: LocalAzanPreferences, locationService: AzanLocationService, onSave: @escaping (LocalAzanPreferences) -> Void) {
        self.preferences = preferences
        self.locationService = locationService
        self.onSave = onSave
        self._selectedMethod = State(initialValue: preferences.parsedCalculationMethod)
        self._selectedMadhab = State(initialValue: preferences.parsedMadhab)
    }

    var body: some View {
        List {
            // Location
            Section {
                Toggle("Use Device Location", isOn: $preferences.useDeviceLocation)
                    .onChange(of: preferences.useDeviceLocation) { _, useDevice in
                        if useDevice {
                            Task { await locationService.requestLocation() }
                        }
                    }

                if !preferences.useDeviceLocation {
                    Button {
                        showLocationSearch = true
                    } label: {
                        HStack {
                            Label("Search Location", systemImage: "magnifyingglass")
                            Spacer()
                            if !preferences.locationName.isEmpty {
                                Text(preferences.locationName)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Image(systemName: "chevron.right")
                                .font(.caption.bold())
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                }

                if preferences.useDeviceLocation && locationService.hasLocation {
                    LabeledContent("Current Location", value: locationService.locationName)
                } else if !preferences.useDeviceLocation && preferences.locationName.isEmpty {
                    Text("No location selected")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Location")
            }

            // Display
            Section {
                Toggle("Show Sunrise", isOn: $preferences.showSunrise)
                Toggle("Show Sunset", isOn: $preferences.showSunset)
            } header: {
                Text("Display")
            } footer: {
                Text("Sunrise and sunset are informational rows, not prayer times.")
            }

            // Calculation Method
            Section {
                Picker("Method", selection: $selectedMethod) {
                    ForEach(AzanCalculationMethod.allCases) { method in
                        Text(method.displayName).tag(method)
                    }
                }
                .onChange(of: selectedMethod) { _, newValue in
                    preferences.calculationMethod = newValue.rawValue
                }

                Picker("Madhab (Asr)", selection: $selectedMadhab) {
                    ForEach(AzanMadhab.allCases) { madhab in
                        VStack(alignment: .leading) {
                            Text(madhab.displayName)
                            Text(madhab.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .tag(madhab)
                    }
                }
                .onChange(of: selectedMadhab) { _, newValue in
                    preferences.madhab = newValue.rawValue
                }
            } header: {
                Text("Calculation")
            }

            // Per-Prayer Notifications
            Section {
                Toggle("Fajr", isOn: $preferences.fajrNotification)
                Toggle("Dhuhr", isOn: $preferences.dhuhrNotification)
                Toggle("Asr", isOn: $preferences.asrNotification)
                Toggle("Maghrib", isOn: $preferences.maghribNotification)
                Toggle("Isha", isOn: $preferences.ishaNotification)
            } header: {
                Text("Notifications")
            } footer: {
                Text("Notifications are delivered as Time Sensitive to break through Focus modes.")
            }

            // Jumu'ah
            Section {
                Toggle("Early Reminder", isOn: $preferences.jumuahReminderEnabled)

                if preferences.jumuahReminderEnabled {
                    Stepper(
                        "\(preferences.jumuahReminderMinutes) min before Dhuhr",
                        value: $preferences.jumuahReminderMinutes,
                        in: 15...120,
                        step: 15
                    )
                }
            } header: {
                Text("Jumu'ah (Friday)")
            } footer: {
                Text("Get an early reminder before Friday prayer.")
            }

            // Ramadan
            Section {
                Stepper(
                    "Hijri Date: \(preferences.hijriDateAdjustment > 0 ? "+" : "")\(preferences.hijriDateAdjustment) \(abs(preferences.hijriDateAdjustment) == 1 ? "day" : "days")",
                    value: $preferences.hijriDateAdjustment,
                    in: -2...2
                )

                Toggle("Suhoor Reminder", isOn: $preferences.suhoorReminderEnabled)

                if preferences.suhoorReminderEnabled {
                    Stepper(
                        "\(preferences.suhoorReminderMinutes) min before Fajr",
                        value: $preferences.suhoorReminderMinutes,
                        in: 10...90,
                        step: 5
                    )
                }
            } header: {
                Text("Ramadan")
            } footer: {
                Text("Adjust if Ramadan start doesn't match your local moon sighting. Suhoor reminders fire before Fajr during Ramadan.")
            }

            // Sound
            Section {
                Button {
                    showSoundPicker = .notification
                } label: {
                    HStack {
                        Text("Notification Sound")
                            .foregroundStyle(.primary)
                        Spacer()
                        Text(AzanAudioService.displayName(for: preferences.azanSound))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Image(systemName: "chevron.right")
                            .font(.caption.bold())
                            .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)

                Button {
                    showSoundPicker = .fajr
                } label: {
                    HStack {
                        Text("Fajr Sound")
                            .foregroundStyle(.primary)
                        Spacer()
                        Text(AzanAudioService.displayName(for: preferences.fajrAzanSound))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Image(systemName: "chevron.right")
                            .font(.caption.bold())
                            .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)

                Toggle("Play Full Azan on Tap", isOn: $preferences.playFullAzanOnTap)
            } header: {
                Text("Sound")
            }

            // Time Adjustments
            Section {
                adjustmentRow("Fajr", value: $preferences.fajrAdjustment)
                adjustmentRow("Dhuhr", value: $preferences.dhuhrAdjustment)
                adjustmentRow("Asr", value: $preferences.asrAdjustment)
                adjustmentRow("Maghrib", value: $preferences.maghribAdjustment)
                adjustmentRow("Isha", value: $preferences.ishaAdjustment)
            } header: {
                Text("Time Adjustments")
            } footer: {
                Text("Fine-tune prayer times in minutes. Positive values delay, negative values advance.")
            }
        }
        .navigationTitle("Prayer Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Save") {
                    onSave(preferences)
                    dismiss()
                }
                .fontWeight(.semibold)
            }
        }
        .sheet(isPresented: $showLocationSearch) {
            NavigationStack {
                LocationSearchView { lat, lon, name in
                    preferences.latitude = lat
                    preferences.longitude = lon
                    preferences.locationName = name
                }
            }
        }
        .sheet(item: $showSoundPicker) { type in
            NavigationStack {
                SoundPickerSheet(
                    selection: type == .notification ? $preferences.azanSound : $preferences.fajrAzanSound,
                    title: type == .notification ? "Notification Sound" : "Fajr Sound",
                    audioService: audioService
                )
            }
            .presentationDetents([.medium, .large])
        }
    }

    private func adjustmentRow(_ label: String, value: Binding<Int>) -> some View {
        Stepper(
            "\(label): \(value.wrappedValue > 0 ? "+" : "")\(value.wrappedValue) min",
            value: value,
            in: -30...30
        )
    }
}

// MARK: - Sound Picker Sheet

private struct SoundPickerSheet: View {
    @Binding var selection: String
    let title: String
    let audioService: AzanAudioService

    @Environment(\.dismiss) private var dismiss
    @State private var playingSound: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                // Default option
                DefaultSoundRow(
                    isSelected: selection == "default",
                    onSelect: { selection = "default" }
                )

                // Audio cards
                ForEach(audioService.availableSounds.filter { $0 != "default" }, id: \.self) { sound in
                    SoundCard(
                        sound: sound,
                        isSelected: selection == sound,
                        isPlaying: playingSound == sound,
                        progress: playingSound == sound ? audioService.playbackProgress : 0,
                        onSelect: { selection = sound },
                        onTogglePlay: { togglePreview(sound) }
                    )
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") {
                    audioService.stopAzan()
                    dismiss()
                }
                .fontWeight(.semibold)
            }
        }
        .onDisappear {
            audioService.stopAzan()
        }
    }

    private func togglePreview(_ sound: String) {
        if playingSound == sound {
            audioService.stopAzan()
            playingSound = nil
        } else {
            audioService.stopAzan()
            audioService.playFullAzan(soundName: sound)
            playingSound = sound
        }
    }
}

// MARK: - Default Sound Row

private struct DefaultSoundRow: View {
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    .font(.title3)
                Text("Default")
                    .foregroundStyle(.primary)
                    .fontWeight(isSelected ? .semibold : .regular)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Sound Card with Waveform

private struct SoundCard: View {
    let sound: String
    let isSelected: Bool
    let isPlaying: Bool
    let progress: Double
    let onSelect: () -> Void
    let onTogglePlay: () -> Void

    private var samples: [Float] {
        WaveformData.samples[sound] ?? Array(repeating: Float(0.2), count: 60)
    }

    var body: some View {
        Button(action: onSelect) {
            ZStack(alignment: .leading) {
                // Waveform background
                GeometryReader { geo in
                    waveformBars(in: geo.size)

                    // Playhead line
                    if isPlaying && progress > 0 {
                        Rectangle()
                            .fill(Color.accentColor)
                            .frame(width: 2)
                            .offset(x: geo.size.width * progress)
                    }
                }

                // Label overlay
                VStack(alignment: .leading) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(AzanAudioService.displayName(for: sound))
                                .font(.subheadline.weight(isSelected ? .semibold : .medium))
                                .foregroundStyle(.primary)
                        }

                        Spacer()

                        // Play/stop button
                        Button(action: onTogglePlay) {
                            Image(systemName: isPlaying ? "stop.fill" : "play.fill")
                                .font(.caption)
                                .foregroundStyle(.white)
                                .frame(width: 28, height: 28)
                                .background(isPlaying ? Color.red : Color.accentColor, in: Circle())
                        }
                        .buttonStyle(.plain)
                    }

                    Spacer()

                    // Selection indicator
                    if isSelected {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark")
                                .font(.caption2.weight(.bold))
                            Text("Selected")
                                .font(.caption2.weight(.semibold))
                        }
                        .foregroundStyle(Color.accentColor)
                    }
                }
                .padding(12)
            }
            .frame(height: 80)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }

    private func waveformBars(in size: CGSize) -> some View {
        let barSpacing: CGFloat = 2.5
        let barWidth = max(1, (size.width - barSpacing * CGFloat(samples.count - 1)) / CGFloat(samples.count))

        return HStack(spacing: barSpacing) {
            ForEach(0..<samples.count, id: \.self) { index in
                let fraction = samples.count > 1 ? Double(index) / Double(samples.count - 1) : 0
                let isPlayed = isPlaying && fraction <= progress
                RoundedRectangle(cornerRadius: barWidth / 2)
                    .fill(isPlayed ? Color.accentColor.opacity(0.5) : Color.secondary.opacity(0.12))
                    .frame(width: barWidth, height: max(3, size.height * CGFloat(samples[index]) * 0.85))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}

// MARK: - Waveform Data

private enum WaveformData {
    static let samples: [String: [Float]] = [
        "ahmad-al-nafees": [0.05, 0.05, 0.07, 0.45, 0.60, 0.54, 0.38, 0.21, 0.85, 0.65, 0.67, 0.57, 0.15, 0.51, 0.71, 0.60, 0.60, 0.18, 0.65, 0.74, 0.51, 0.51, 0.15, 0.57, 0.64, 0.74, 0.63, 0.24, 0.54, 0.44, 0.46, 0.13, 0.70, 0.63, 0.59, 0.25, 0.40, 0.51, 0.91, 0.57, 0.16, 0.72, 0.67, 0.50, 0.38, 0.80, 1.00, 0.66, 0.14, 0.85, 0.69, 0.66, 0.40, 0.45, 0.85, 0.68, 0.39, 0.27, 0.11, 0.05],
        "hafiz-mustafa-ozcan": [0.44, 0.05, 0.73, 0.70, 0.72, 0.05, 0.05, 0.62, 0.76, 0.05, 0.41, 0.62, 0.80, 0.10, 0.13, 0.57, 0.82, 0.18, 0.14, 0.57, 0.64, 0.78, 0.82, 0.07, 0.05, 0.21, 0.77, 0.44, 0.05, 0.05, 0.56, 0.87, 0.79, 0.80, 0.77, 0.12, 0.05, 0.17, 0.78, 1.00, 0.20, 0.05, 0.19, 0.83, 0.77, 0.86, 0.79, 0.76, 0.75, 0.68, 0.05, 0.24, 0.74, 0.87, 0.31, 0.63, 0.65, 0.50, 0.05, 0.05],
        "karl-jenkins": [0.30, 0.59, 0.59, 0.56, 0.42, 0.31, 0.61, 0.89, 0.81, 0.49, 0.06, 0.53, 0.84, 0.85, 0.24, 0.44, 0.88, 0.63, 0.53, 0.27, 0.16, 0.49, 0.79, 0.88, 0.41, 0.20, 0.58, 0.66, 0.55, 0.41, 0.28, 0.62, 0.67, 0.28, 0.32, 0.95, 0.68, 0.54, 0.32, 0.25, 0.63, 0.68, 0.17, 0.57, 0.91, 0.64, 0.50, 0.12, 0.75, 1.00, 0.75, 0.42, 0.13, 0.88, 0.70, 0.63, 0.26, 0.05, 0.05, 0.05],
        "mansour-al-zahrani": [0.80, 1.00, 0.67, 0.70, 0.67, 0.33, 0.44, 0.86, 0.50, 0.49, 0.49, 0.28, 0.25, 0.69, 0.62, 0.50, 0.51, 0.26, 0.40, 0.41, 0.35, 0.32, 0.31, 0.37, 0.42, 0.48, 0.29, 0.30, 0.32, 0.36, 0.32, 0.40, 0.51, 0.47, 0.41, 0.29, 0.49, 0.42, 0.43, 0.32, 0.23, 0.47, 0.50, 0.46, 0.37, 0.41, 0.47, 0.48, 0.40, 0.32, 0.31, 0.60, 0.45, 0.51, 0.29, 0.51, 0.46, 0.36, 0.40, 0.27],
        "mishary-rashid-alafasy": [0.05, 0.63, 0.72, 0.67, 0.71, 0.15, 0.84, 0.85, 0.81, 0.52, 0.16, 0.74, 0.60, 0.65, 0.77, 0.33, 0.52, 0.84, 0.83, 0.66, 0.48, 0.58, 0.78, 0.77, 0.63, 0.28, 0.49, 0.60, 0.79, 0.85, 0.67, 0.21, 0.68, 0.89, 0.83, 0.65, 0.29, 0.93, 0.84, 0.70, 0.42, 0.37, 1.00, 0.74, 0.62, 0.96, 0.89, 0.71, 0.43, 0.39, 0.67, 0.83, 0.73, 0.72, 0.38, 0.85, 0.80, 0.78, 0.65, 0.05],
        "mishary-rashid-alafasy-2": [0.32, 0.37, 0.41, 0.35, 0.19, 0.43, 0.40, 0.36, 0.31, 0.17, 0.45, 0.36, 0.34, 0.34, 0.16, 0.40, 0.39, 0.29, 0.19, 0.23, 0.25, 0.36, 0.35, 0.18, 0.25, 0.27, 0.37, 0.36, 0.14, 0.57, 0.53, 0.38, 0.26, 0.38, 0.48, 0.40, 0.34, 0.13, 0.48, 0.57, 0.43, 0.34, 0.16, 0.39, 0.36, 0.17, 0.31, 0.42, 0.43, 0.39, 0.23, 0.32, 0.24, 0.22, 0.05, 1.00, 0.54, 0.69, 0.73, 0.05],
        "mishary-rashid-one-tv": [0.77, 0.46, 0.87, 0.98, 0.88, 0.79, 0.26, 0.88, 0.84, 0.93, 0.39, 0.87, 0.87, 0.76, 0.90, 0.47, 0.50, 0.95, 0.64, 0.53, 0.87, 0.90, 0.91, 0.91, 0.90, 0.08, 0.90, 0.81, 0.35, 0.84, 0.82, 0.88, 0.80, 0.90, 0.95, 0.06, 0.83, 0.86, 0.45, 0.63, 0.86, 0.95, 0.84, 0.89, 0.95, 0.23, 0.82, 0.63, 0.82, 0.82, 0.94, 0.45, 0.63, 0.54, 0.74, 0.48, 1.00, 0.48, 0.76, 0.05],
    ]
}
