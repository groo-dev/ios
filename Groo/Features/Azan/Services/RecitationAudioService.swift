//
//  RecitationAudioService.swift
//  Groo
//
//  AVAudioPlayer service for playing bundled recitation and surah audio files.
//

import AVFoundation
import Foundation

@MainActor
@Observable
class RecitationAudioService {
    static let shared = RecitationAudioService()

    private(set) var isPlaying = false
    private(set) var currentFile: String?

    private var audioPlayer: AVAudioPlayer?
    private var playbackDelegate: PlaybackDelegate?

    private init() {}

    // MARK: - Playback

    func play(_ fileName: String) {
        // If same file is playing, stop it (toggle)
        if isPlaying && currentFile == fileName {
            stop()
            return
        }

        stop()

        guard let url = Bundle.main.url(forResource: fileName, withExtension: "mp3") else {
            print("[RecitationAudio] File not found: \(fileName).mp3")
            return
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setActive(true)

            audioPlayer = try AVAudioPlayer(contentsOf: url)
            playbackDelegate = PlaybackDelegate { [weak self] in
                Task { @MainActor in self?.stop() }
            }
            audioPlayer?.delegate = playbackDelegate
            audioPlayer?.prepareToPlay()
            audioPlayer?.play()
            isPlaying = true
            currentFile = fileName
        } catch {
            print("[RecitationAudio] Playback failed: \(error)")
            isPlaying = false
        }
    }

    func stop() {
        audioPlayer?.stop()
        audioPlayer = nil
        playbackDelegate = nil
        isPlaying = false
        currentFile = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func isCurrentlyPlaying(_ fileName: String) -> Bool {
        isPlaying && currentFile == fileName
    }
}

// MARK: - Delegate for auto-stop on finish

private class PlaybackDelegate: NSObject, AVAudioPlayerDelegate {
    let onFinish: () -> Void

    init(onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        onFinish()
    }
}
