//
//  LocationProviding.swift
//  Groo
//
//  Phase 7 seam over CLLocationManager. CLLocationManager conforms as-is.
//

import CoreLocation

protocol LocationProviding: AnyObject {
    var delegate: CLLocationManagerDelegate? { get set }
    var desiredAccuracy: CLLocationAccuracy { get set }
    var authorizationStatus: CLAuthorizationStatus { get }
    func requestWhenInUseAuthorization()
    func requestLocation()
}

extension CLLocationManager: LocationProviding {}
