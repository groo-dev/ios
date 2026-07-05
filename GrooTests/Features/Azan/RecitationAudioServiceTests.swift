//
//  RecitationAudioServiceTests.swift
//  GrooTests
//
//  Toggle/stop/error state over the AudioPlaying seam, on isolated
//  instances (the production singleton keeps its real defaults).
//

import AVFoundation
import Foundation
import Testing
@testable import Groo

@MainActor
struct RecitationAudioServiceTests {
    /// A file name guaranteed bundled: the first short surah's audio.
    static func bundledFileName() throws -> String {
        try #require(PrayerGuideDataProvider.shortSurahs().first).audioFileName
    }

    static func makeService() -> (service: RecitationAudioService, players: AudioPlayerRecorder, session: RecordingAudioSession) {
        let players = AudioPlayerRecorder()
        let session = RecordingAudioSession()
        let service = RecitationAudioService(makePlayer: { try players.make($0) }, audioSession: session)
        return (service, players, session)
    }

    @Test func playSetsStateAndCreatesPlayer() throws {
        let (service, players, session) = Self.makeService()
        let file = try Self.bundledFileName()
        service.play(file)
        #expect(service.isPlaying)
        #expect(service.currentFile == file)
        #expect(service.isCurrentlyPlaying(file))
        #expect(service.lastError == nil)
        #expect(session.activations == 1)
        #expect(players.players.count == 1)
    }

    @Test func playSameFileTogglesOff() throws {
        let (service, _, _) = Self.makeService()
        let file = try Self.bundledFileName()
        service.play(file)
        service.play(file)
        #expect(!service.isPlaying)
        #expect(service.currentFile == nil)
    }

    @Test func missingFileSetsLastError() {
        let (service, players, _) = Self.makeService()
        service.play("definitely-not-bundled-xyz")
        #expect(!service.isPlaying)
        #expect(service.lastError == "Audio unavailable for this recitation")
        #expect(players.players.isEmpty)
    }

    @Test func delegateFinishAutoStops() async throws {
        let (service, players, _) = Self.makeService()
        let file = try Self.bundledFileName()
        service.play(file)
        let player = try #require(players.players.first)
        let delegate = try #require(player.delegate)
        // The delegate's onFinish hops to the main actor via Task — yield for it.
        let url = try #require(Bundle.main.url(forResource: file, withExtension: "mp3"))
        let dummyPlayer = try AVAudioPlayer(contentsOf: url)
        delegate.audioPlayerDidFinishPlaying?(dummyPlayer, successfully: true)
        for _ in 0..<4 { await Task.yield() }
        #expect(!service.isPlaying)
        #expect(service.currentFile == nil)
    }

    @Test func creationFailureSetsError() throws {
        struct Boom: Error {}
        let (service, players, _) = Self.makeService()
        players.creationError = Boom()
        service.play(try Self.bundledFileName())
        #expect(!service.isPlaying)
        #expect(service.lastError == "Couldn't play audio")
    }
}
