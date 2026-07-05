//
//  SystemServiceFakes.swift
//  GrooTests
//
//  Phase 7 fakes for the system-service seams: notification center, audio
//  player/session, location manager. Lock-guarded like InMemoryKeychain so
//  the sync protocol requirements are satisfiable off the main actor.
//

import AVFoundation
import CoreLocation
import Foundation
import UserNotifications
@testable import Groo

final class FakeNotificationCenter: NotificationScheduling, @unchecked Sendable {
    private let lock = NSLock()
    var authorizationResult: Result<Bool, any Error> = .success(true)
    var status: UNAuthorizationStatus = .authorized

    private var _added: [UNNotificationRequest] = []
    private var _pending: [UNNotificationRequest] = []
    private var _removedIdentifiers: [[String]] = []
    private var _categories: [Set<UNNotificationCategory>] = []

    var added: [UNNotificationRequest] { lock.withLock { _added } }
    var pending: [UNNotificationRequest] { lock.withLock { _pending } }
    var removedIdentifiers: [[String]] { lock.withLock { _removedIdentifiers } }
    var categories: [Set<UNNotificationCategory>] { lock.withLock { _categories } }

    func seedPending(_ requests: [UNNotificationRequest]) {
        lock.withLock { _pending.append(contentsOf: requests) }
    }

    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        try authorizationResult.get()
    }

    func authorizationStatus() async -> UNAuthorizationStatus { status }

    func setNotificationCategories(_ categories: Set<UNNotificationCategory>) {
        lock.withLock { _categories.append(categories) }
    }

    func add(_ request: UNNotificationRequest) async throws {
        lock.withLock { _added.append(request); _pending.append(request) }
    }

    func pendingNotificationRequests() async -> [UNNotificationRequest] {
        lock.withLock { _pending }
    }

    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
        lock.withLock {
            _removedIdentifiers.append(identifiers)
            _pending.removeAll { identifiers.contains($0.identifier) }
        }
    }
}

final class FakeAudioPlayer: AudioPlaying {
    let url: URL
    var stubbedIsPlaying = true
    var duration: TimeInterval = 100
    var currentTime: TimeInterval = 25
    weak var delegate: AVAudioPlayerDelegate?
    private(set) var prepareCount = 0
    private(set) var playCount = 0
    private(set) var stopCount = 0

    init(url: URL) { self.url = url }

    var isPlaying: Bool { stubbedIsPlaying }

    @discardableResult func prepareToPlay() -> Bool { prepareCount += 1; return true }
    @discardableResult func play() -> Bool { playCount += 1; return true }
    func stop() { stopCount += 1; stubbedIsPlaying = false }
}

@MainActor
final class AudioPlayerRecorder {
    private(set) var players: [FakeAudioPlayer] = []
    var creationError: (any Error)?

    func make(_ url: URL) throws -> any AudioPlaying {
        if let creationError { throw creationError }
        let player = FakeAudioPlayer(url: url)
        players.append(player)
        return player
    }
}

final class RecordingAudioSession: AudioSessionControlling, @unchecked Sendable {
    private let lock = NSLock()
    private var _activations = 0
    private var _deactivations = 0
    var activationError: (any Error)?
    var activations: Int { lock.withLock { _activations } }
    var deactivations: Int { lock.withLock { _deactivations } }

    func activatePlayback() throws {
        lock.withLock { _activations += 1 }
        if let activationError { throw activationError }
    }

    func deactivate() { lock.withLock { _deactivations += 1 } }
}

final class FakeLocationManager: LocationProviding {
    weak var delegate: CLLocationManagerDelegate?
    var desiredAccuracy: CLLocationAccuracy = 0
    var authorizationStatus: CLAuthorizationStatus = .authorizedWhenInUse
    private(set) var didRequestAuthorization = false
    private(set) var didRequestLocation = false
    /// Test hook: invoked synchronously from requestLocation so the test can
    /// drive the delegate callbacks (success or failure).
    var onRequestLocation: () -> Void = {}

    func requestWhenInUseAuthorization() { didRequestAuthorization = true }
    func requestLocation() { didRequestLocation = true; onRequestLocation() }
}
