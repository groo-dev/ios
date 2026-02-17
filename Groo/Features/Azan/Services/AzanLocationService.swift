//
//  AzanLocationService.swift
//  Groo
//
//  CoreLocation wrapper for prayer time location.
//  Uses When In Use authorization with one-shot location request.
//

import CoreLocation
import Foundation

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

    private let locationManager = CLLocationManager()
    private let geocoder = CLGeocoder()
    private var locationContinuation: CheckedContinuation<CLLocation, Error>?

    override init() {
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
            error = "Location permission denied"
            return
        }

        do {
            let location = try await requestOneShot()
            latitude = location.coordinate.latitude
            longitude = location.coordinate.longitude
            await reverseGeocode(location)
        } catch {
            self.error = "Failed to get location"
        }
    }

    func setManualLocation(latitude: Double, longitude: Double, name: String) {
        self.latitude = latitude
        self.longitude = longitude
        self.locationName = name
        self.error = nil
    }

    // MARK: - Private

    private func requestOneShot() async throws -> CLLocation {
        try await withCheckedThrowingContinuation { continuation in
            locationContinuation = continuation
            locationManager.requestLocation()
        }
    }

    private func reverseGeocode(_ location: CLLocation) async {
        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(location)
            if let placemark = placemarks.first {
                let city = placemark.locality ?? ""
                let country = placemark.country ?? ""
                if !city.isEmpty && !country.isEmpty {
                    locationName = "\(city), \(country)"
                } else {
                    locationName = city.isEmpty ? country : city
                }
            }
        } catch {
            locationName = String(format: "%.2f, %.2f", location.coordinate.latitude, location.coordinate.longitude)
        }
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
