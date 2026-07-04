//
//  AzanAudioService.swift
//  Groo
//
//  AVAudioPlayer for full Azan playback after notification tap.
//  Uses .playback audio session for background audio.
//

import AVFoundation
import Foundation
import os

@MainActor
@Observable
class AzanAudioService {
    private(set) var isPlaying = false
    private(set) var currentPrayer: Prayer?
    private(set) var playbackProgress: Double = 0

    private var audioPlayer: AVAudioPlayer?
    private var progressTimer: Timer?

    // MARK: - Playback

    func playFullAzan(for prayer: Prayer = .dhuhr, soundName: String? = nil) {
        stopAzan()

        // Configure audio session for playback
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setActive(true)
        } catch {
            // Playback may still work with the default session — log and continue
            Log.azan.error("[AzanAudio] Failed to configure audio session: \(String(describing: error), privacy: .public)")
        }

        // Try to load the specified sound file or fallback
        let fileName = soundName ?? (prayer == .fajr ? "azan_fajr" : "azan_full")
        var audioURL = findAudioFile(named: fileName)
        if audioURL == nil, fileName != "azan_full" {
            Log.azan.error("[AzanAudio] Audio file missing for '\(fileName, privacy: .public)' — falling back to 'azan_full'")
            audioURL = findAudioFile(named: "azan_full")
        }
        guard let url = audioURL else {
            Log.azan.error("[AzanAudio] No audio file found for '\(fileName, privacy: .public)' and no fallback available — cannot play azan")
            return
        }

        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.prepareToPlay()
            audioPlayer?.play()
            isPlaying = true
            currentPrayer = prayer
            playbackProgress = 0
            startProgressTimer()
        } catch {
            Log.azan.error("[AzanAudio] Playback failed for \(url.lastPathComponent, privacy: .public): \(String(describing: error), privacy: .public)")
            isPlaying = false
        }
    }

    func stopAzan() {
        progressTimer?.invalidate()
        progressTimer = nil
        audioPlayer?.stop()
        audioPlayer = nil
        isPlaying = false
        currentPrayer = nil
        playbackProgress = 0

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

    private static let soundLabels: [String: String] = [
        "ahmad-al-nafees": "Ahmad al-Nafees",
        "hafiz-mustafa-ozcan": "Hafiz Mustafa Özcan (Turkey)",
        "karl-jenkins": "Karl Jenkins - Mass for Peace",
        "mishary-rashid-one-tv": "Mishary Rashid Alafasy (One TV Dubai)",
        "mishary-rashid-alafasy": "Mishary Rashid Alafasy",
        "mishary-rashid-alafasy-2": "Mishary Rashid Alafasy (2)",
        "mansour-al-zahrani": "Mansour Al-Zahrani",
    ]

    var availableSounds: [String] {
        var sounds = ["default"]
        if let urls = Bundle.main.urls(forResourcesWithExtension: "m4a", subdirectory: nil) {
            sounds.append(contentsOf: urls.map { $0.deletingPathExtension().lastPathComponent }.sorted())
        }
        return sounds
    }

    static func displayName(for sound: String) -> String {
        if sound == "default" { return "Default" }
        return soundLabels[sound] ?? sound
    }

    // MARK: - Private

    private func findAudioFile(named name: String) -> URL? {
        let extensions = ["m4a", "caf", "mp3", "aiff"]
        for ext in extensions {
            if let url = Bundle.main.url(forResource: name, withExtension: ext) {
                return url
            }
        }
        return nil
    }

    private func startProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateProgress()
            }
        }
    }

    private func updateProgress() {
        guard let player = audioPlayer, player.isPlaying else {
            if isPlaying {
                stopAzan()
            }
            return
        }
        playbackProgress = player.currentTime / max(player.duration, 1)
    }
}
