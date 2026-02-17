//
//  AzanAudioService.swift
//  Groo
//
//  AVAudioPlayer for full Azan playback after notification tap.
//  Uses .playback audio session for background audio.
//

import AVFoundation
import Foundation

@MainActor
@Observable
class AzanAudioService {
    private(set) var isPlaying = false
    private(set) var currentPrayer: Prayer?

    private var audioPlayer: AVAudioPlayer?

    // MARK: - Playback

    func playFullAzan(for prayer: Prayer = .dhuhr, soundName: String? = nil) {
        stopAzan()

        // Configure audio session for playback
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setActive(true)
        } catch {
            print("[AzanAudio] Failed to configure audio session: \(error)")
        }

        // Try to load the specified sound file or fallback
        let fileName = soundName ?? (prayer == .fajr ? "azan_fajr" : "azan_full")
        guard let url = findAudioFile(named: fileName) else {
            print("[AzanAudio] No audio file found for '\(fileName)'")
            return
        }

        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.prepareToPlay()
            audioPlayer?.play()
            isPlaying = true
            currentPrayer = prayer
        } catch {
            print("[AzanAudio] Playback failed: \(error)")
            isPlaying = false
        }
    }

    func stopAzan() {
        audioPlayer?.stop()
        audioPlayer = nil
        isPlaying = false
        currentPrayer = nil

        // Deactivate audio session
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func togglePlayback(for prayer: Prayer, soundName: String? = nil) {
        if isPlaying {
            stopAzan()
        } else {
            playFullAzan(for: prayer, soundName: soundName)
        }
    }

    // MARK: - Available Sounds

    var availableSounds: [String] {
        var sounds = ["default"]
        let extensions = ["caf", "m4a", "mp3", "aiff"]

        for ext in extensions {
            if let urls = Bundle.main.urls(forResourcesWithExtension: ext, subdirectory: "Sounds") {
                sounds.append(contentsOf: urls.map { $0.deletingPathExtension().lastPathComponent })
            }
        }

        return sounds
    }

    // MARK: - Private

    private func findAudioFile(named name: String) -> URL? {
        let extensions = ["m4a", "caf", "mp3", "aiff"]
        for ext in extensions {
            // Check Sounds subdirectory first
            if let url = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "Sounds") {
                return url
            }
            // Check bundle root
            if let url = Bundle.main.url(forResource: name, withExtension: ext) {
                return url
            }
        }
        return nil
    }
}
