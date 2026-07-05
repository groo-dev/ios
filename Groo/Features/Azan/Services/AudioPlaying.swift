//
//  AudioPlaying.swift
//  Groo
//
//  Phase 7 seams over AVAudioPlayer instances and the shared
//  AVAudioSession activate/deactivate pair. AVAudioPlayer conforms as-is.
//

import AVFoundation

protocol AudioPlaying: AnyObject {
    var isPlaying: Bool { get }
    var duration: TimeInterval { get }
    var currentTime: TimeInterval { get }
    var delegate: AVAudioPlayerDelegate? { get set }
    @discardableResult func prepareToPlay() -> Bool
    @discardableResult func play() -> Bool
    func stop()
}

extension AVAudioPlayer: AudioPlaying {}

protocol AudioSessionControlling {
    func activatePlayback() throws
    func deactivate()
}

struct SystemAudioSession: AudioSessionControlling {
    func activatePlayback() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default, options: [])
        try session.setActive(true)
    }

    func deactivate() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
