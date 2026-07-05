//
//  AzanLocationService.swift
//  Groo
//
//  CoreLocation wrapper for prayer time location.
//  Uses When In Use authorization with one-shot location request.
//

import CoreLocation
import Foundation
import os

@MainActor
@Observable
class AzanLocationService: NSObject {
    private(set) var latitude: Double = 0
    private(set) var longitude: Double = 0
    private(set) var locationName: String = ""
    private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined
    private(set) var isLoading = false
    private(set) var error: String?

    var hasLocation: Bool { latitude != 0 || longitude != 0 }

    private let locationManager: any LocationProviding
    private let geocodeName: (CLLocation) async throws -> String?
    private var locationContinuation: CheckedContinuation<CLLocation, Error>?

    /// Phase 7 seams: production uses the real CLLocationManager and
    /// CLGeocoder; tests inject a fake manager + geocode closure.
    init(
        manager: any LocationProviding = CLLocationManager(),
        geocodeName: @escaping (CLLocation) async throws -> String? = AzanLocationService.systemGeocodeName
    ) {
        self.locationManager = manager
        self.geocodeName = geocodeName
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyKilometer
        authorizationStatus = locationManager.authorizationStatus
    }

    // MARK: - Public

    func requestLocation() async {
        isLoading = true
        error = nil
        defer { isLoading = false }

        // Request authorization if needed
        if authorizationStatus == .notDetermined {
            locationManager.requestWhenInUseAuthorization()
            // Wait briefly for authorization callback
            try? await Task.sleep(for: .seconds(1))
        }

        guard authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways else {
            error = "Location access denied — enable in Settings"
            return
        }

        do {
            let location = try await requestOneShot()
            latitude = location.coordinate.latitude
            longitude = location.coordinate.longitude
            await reverseGeocode(location)
        } catch {
            Log.azan.error("[AzanLocation] Location request failed: \(String(describing: error), privacy: .public)")
            self.error = errorMessage(for: error)
        }
    }

    func setManualLocation(latitude: Double, longitude: Double, name: String) {
        self.latitude = latitude
        self.longitude = longitude
        self.locationName = name
        self.error = nil
    }

    // MARK: - Private

    private func errorMessage(for error: Error) -> String {
        guard let clError = error as? CLError else {
            return "Couldn't get location: \(error.localizedDescription)"
        }
        switch clError.code {
        case .denied:
            return "Location access denied — enable in Settings"
        case .network:
            return "Network error while getting location — check your connection"
        case .locationUnknown:
            return "Couldn't determine your location — try again"
        default:
            return "Couldn't get location: \(clError.localizedDescription)"
        }
    }

    private func requestOneShot() async throws -> CLLocation {
        try await withCheckedThrowingContinuation { continuation in
            locationContinuation = continuation
            locationManager.requestLocation()
        }
    }

    private func reverseGeocode(_ location: CLLocation) async {
        do {
            if let name = try await geocodeName(location) {
                locationName = name
            }
        } catch {
            locationName = String(format: "%.2f, %.2f",
                                  location.coordinate.latitude, location.coordinate.longitude)
        }
    }

    /// Production geocode: CLGeocoder → "City, Country". Returns nil when
    /// the placemark has neither (leaves the previous name untouched —
    /// matching the old behavior for the no-placemark case).
    static func systemGeocodeName(_ location: CLLocation) async throws -> String? {
        let placemarks = try await CLGeocoder().reverseGeocodeLocation(location)
        guard let placemark = placemarks.first else { return nil }
        let city = placemark.locality ?? ""
        let country = placemark.country ?? ""
        if !city.isEmpty && !country.isEmpty { return "\(city), \(country)" }
        let single = city.isEmpty ? country : city
        return single.isEmpty ? nil : single
    }
}

// MARK: - CLLocationManagerDelegate

extension AzanLocationService: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            locationContinuation?.resume(returning: location)
            locationContinuation = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            locationContinuation?.resume(throwing: error)
            locationContinuation = nil
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            authorizationStatus = manager.authorizationStatus
        }
    }
}
