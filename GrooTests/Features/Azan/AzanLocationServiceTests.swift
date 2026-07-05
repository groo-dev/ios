//
//  AzanLocationServiceTests.swift
//  GrooTests
//
//  Authorization flow + coordinate handoff over the LocationProviding seam.
//  Delegate callbacks are driven with a throwaway CLLocationManager (its
//  construction is side-effect free). The notDetermined branch (production
//  1s sleep) is deliberately untested — no-sleeps rule.
//

import CoreLocation
import Foundation
import Testing
@testable import Groo

@MainActor
struct AzanLocationServiceTests {
    @Test func initConfiguresManagerAndReadsStatus() {
        let manager = FakeLocationManager()
        manager.authorizationStatus = .denied
        let service = AzanLocationService(manager: manager, geocodeName: { _ in nil })
        #expect(service.authorizationStatus == .denied)
        #expect(manager.delegate === service)
        #expect(manager.desiredAccuracy == kCLLocationAccuracyKilometer)
        #expect(!service.hasLocation)
    }

    @Test func requestLocationSuccessSetsCoordinatesAndGeocodedName() async {
        let manager = FakeLocationManager()
        let service = AzanLocationService(manager: manager, geocodeName: { _ in "Dubai, United Arab Emirates" })
        manager.onRequestLocation = { [weak manager] in
            manager?.delegate?.locationManager?(
                CLLocationManager(), didUpdateLocations: [CLLocation(latitude: 25.2048, longitude: 55.2708)])
        }

        await service.requestLocation()

        #expect(service.latitude == 25.2048)
        #expect(service.longitude == 55.2708)
        #expect(service.locationName == "Dubai, United Arab Emirates")
        #expect(service.error == nil)
        #expect(!service.isLoading)
        #expect(manager.didRequestLocation)
        #expect(!manager.didRequestAuthorization, "already authorized — no auth prompt")
    }

    @Test func requestLocationDeniedSetsSettingsError() async {
        let manager = FakeLocationManager()
        manager.authorizationStatus = .denied
        let service = AzanLocationService(manager: manager, geocodeName: { _ in nil })

        await service.requestLocation()

        #expect(service.error == "Location access denied — enable in Settings")
        #expect(!manager.didRequestLocation)
    }

    @Test func clNetworkErrorMapsToFriendlyMessage() async {
        let manager = FakeLocationManager()
        let service = AzanLocationService(manager: manager, geocodeName: { _ in nil })
        manager.onRequestLocation = { [weak manager] in
            manager?.delegate?.locationManager?(
                CLLocationManager(), didFailWithError: CLError(.network))
        }

        await service.requestLocation()

        #expect(service.error == "Network error while getting location — check your connection")
        #expect(!service.hasLocation)
    }

    @Test func geocodeFailureFallsBackToCoordinateString() async {
        struct Boom: Error {}
        let manager = FakeLocationManager()
        let service = AzanLocationService(manager: manager, geocodeName: { _ in throw Boom() })
        manager.onRequestLocation = { [weak manager] in
            manager?.delegate?.locationManager?(
                CLLocationManager(), didUpdateLocations: [CLLocation(latitude: 25.2048, longitude: 55.2708)])
        }

        await service.requestLocation()

        #expect(service.locationName == "25.20, 55.27")
    }

    @Test func setManualLocationClearsError() {
        let service = AzanLocationService(manager: FakeLocationManager(), geocodeName: { _ in nil })
        service.setManualLocation(latitude: 51.5074, longitude: -0.1278, name: "London")
        #expect(service.latitude == 51.5074)
        #expect(service.locationName == "London")
        #expect(service.error == nil)
        #expect(service.hasLocation)
    }

    @Test func authorizationChangeCallbackUpdatesStatus() async {
        let manager = FakeLocationManager()
        let service = AzanLocationService(manager: manager, geocodeName: { _ in nil })
        // The delegate hop reads the REAL manager's status — a fresh
        // CLLocationManager reports .notDetermined on a clean simulator.
        service.locationManagerDidChangeAuthorization(CLLocationManager())
        for _ in 0..<4 { await Task.yield() }
        #expect(service.authorizationStatus == CLLocationManager().authorizationStatus)
    }
}
