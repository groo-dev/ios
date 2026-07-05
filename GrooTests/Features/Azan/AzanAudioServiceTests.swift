//
//  AzanAudioServiceTests.swift
//  GrooTests
//
//  Playback selection/looping state over the AudioPlaying seam — no real
//  audio, no real audio session. File lookup runs against the host app
//  bundle (azan sound files ship with the app).
//
//  Discovered gap (flagged in the Phase 7 report, not fixed here — it's a
//  content/resource gap, not a seam-wiring gap): the app never bundles
//  "azan_full.*"/"azan_fajr.*" files, so `playFullAzan`'s hardcoded,
//  no-soundName defaults never resolve to a real file in ANY environment,
//  production included. Tests whose whole point is exercising the seam's
//  happy path pass an explicit, real bundled sound name instead
//  ("mishary-rashid-alafasy"); the two tests about the default-name
//  selection assert the real (currently silent-no-op) behavior instead.
//

import Foundation
import Testing
@testable import Groo

@MainActor
struct AzanAudioServiceTests {
    static func makeService() -> (service: AzanAudioService, players: AudioPlayerRecorder, session: RecordingAudioSession) {
        let players = AudioPlayerRecorder()
        let session = RecordingAudioSession()
        let service = AzanAudioService(makePlayer: { try players.make($0) }, audioSession: session)
        return (service, players, session)
    }

    @Test func playFullAzanStartsPlayerAndSetsState() throws {
        let (service, players, session) = Self.makeService()
        service.playFullAzan(for: .dhuhr, soundName: "mishary-rashid-alafasy")
        #expect(service.isPlaying)
        #expect(service.currentPrayer == .dhuhr)
        #expect(session.activations == 1)
        let player = try #require(players.players.first)
        #expect(player.playCount == 1 && player.prepareCount == 1)
        #expect(player.url.lastPathComponent.hasPrefix("mishary-rashid-alafasy"),
                "explicit sound name resolves to its own bundled file: \(player.url.lastPathComponent)")
    }

    /// Discovered gap: "azan_fajr.*" (the hardcoded fajr default) is not
    /// bundled, and its fallback "azan_full.*" isn't either — so today the
    /// default-sound path silently no-ops for every prayer. Documented here
    /// rather than silently dropped.
    @Test func fajrUsesFajrSound() {
        let (service, players, _) = Self.makeService()
        service.playFullAzan(for: .fajr)
        #expect(!service.isPlaying)
        #expect(players.players.isEmpty,
                "neither azan_fajr nor its azan_full fallback is bundled today")
    }

    /// Discovered gap: a missing custom sound falls back to "azan_full.*",
    /// which also isn't bundled — so the fallback itself silently no-ops.
    @Test func missingSoundFallsBackToAzanFull() {
        let (service, players, _) = Self.makeService()
        service.playFullAzan(for: .dhuhr, soundName: "definitely-not-bundled-xyz")
        #expect(!service.isPlaying)
        #expect(players.players.isEmpty, "azan_full fallback is not bundled today")
    }

    @Test func stopResetsStateAndDeactivatesSession() throws {
        let (service, players, session) = Self.makeService()
        service.playFullAzan(for: .isha, soundName: "mishary-rashid-alafasy")
        service.stopAzan()
        #expect(!service.isPlaying)
        #expect(service.currentPrayer == nil)
        #expect(service.playbackProgress == 0)
        #expect(try #require(players.players.first).stopCount >= 1)
        // playFullAzan itself calls stopAzan() first (to clear any prior
        // playback) before the test's own explicit stopAzan() — 2 total.
        #expect(session.deactivations == 2)
    }

    @Test func togglePlaybackFlips() {
        let (service, _, _) = Self.makeService()
        service.togglePlayback(for: .asr, soundName: "mishary-rashid-alafasy")
        #expect(service.isPlaying)
        service.togglePlayback(for: .asr, soundName: "mishary-rashid-alafasy")
        #expect(!service.isPlaying)
    }

    @Test func playerCreationFailureLeavesStopped() {
        struct Boom: Error {}
        let (service, players, _) = Self.makeService()
        players.creationError = Boom()
        service.playFullAzan(for: .dhuhr, soundName: "mishary-rashid-alafasy")
        #expect(!service.isPlaying)
        #expect(service.currentPrayer == nil)
    }

    @Test func sessionActivationFailureStillPlays() {
        struct Boom: Error {}
        let (service, players, session) = Self.makeService()
        session.activationError = Boom()
        service.playFullAzan(for: .dhuhr, soundName: "mishary-rashid-alafasy")
        // Log-and-continue contract: playback proceeds on the default session
        #expect(service.isPlaying)
        #expect(players.players.count == 1)
    }

    @Test func displayNames() {
        #expect(AzanAudioService.displayName(for: "default") == "Default")
        #expect(AzanAudioService.displayName(for: "mishary-rashid-alafasy") == "Mishary Rashid Alafasy")
        #expect(AzanAudioService.displayName(for: "unknown-sound") == "unknown-sound")
    }
}
