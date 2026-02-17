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
                Text("Ramadan is automatically detected. Suhoor reminders fire before Fajr during Ramadan.")
            }

            // Sound
            Section {
                HStack {
                    Text("Notification Sound")
                    Spacer()
                    Text(preferences.azanSound == "default" ? "Default" : preferences.azanSound)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("Fajr Sound")
                    Spacer()
                    Text(preferences.fajrAzanSound == "default" ? "Default" : preferences.fajrAzanSound)
                        .foregroundStyle(.secondary)
                }

                Toggle("Play Full Azan on Tap", isOn: $preferences.playFullAzanOnTap)
            } header: {
                Text("Sound")
            } footer: {
                Text("Add custom .caf or .m4a files to the app bundle to enable custom sounds.")
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
    }

    private func adjustmentRow(_ label: String, value: Binding<Int>) -> some View {
        Stepper(
            "\(label): \(value.wrappedValue > 0 ? "+" : "")\(value.wrappedValue) min",
            value: value,
            in: -30...30
        )
    }
}
