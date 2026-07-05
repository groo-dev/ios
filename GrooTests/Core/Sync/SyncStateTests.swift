//
//  SyncStateTests.swift
//  GrooTests
//
//  Status transitions driven by isOnline — documents that going offline
//  overwrites any current status, and coming online only restores .idle
//  from .offline.
//

import Foundation
import Testing
@testable import Groo

@MainActor
struct SyncStateTests {
    @Test func goingOfflineSetsOfflineStatus() {
        let state = SyncState()
        state.isOnline = false
        #expect(state.status == .offline)
    }

    @Test func comingBackOnlineRestoresIdleFromOffline() {
        let state = SyncState()
        state.isOnline = false
        state.isOnline = true
        #expect(state.status == .idle)
    }

    @Test func comingOnlineLeavesNonOfflineStatusAlone() {
        let state = SyncState()
        state.status = .error("boom")
        state.isOnline = true   // already online; didSet still runs
        #expect(state.status == .error("boom"))
    }

    @Test func goingOfflineOverwritesErrorStatus() {
        let state = SyncState()
        state.status = .error("boom")
        state.isOnline = false

        #expect(state.status == .offline)   // documents: the error is lost when offline flips
        #expect(state.errorMessage == nil)
    }

    @Test func statusConvenienceAccessors() {
        let state = SyncState()

        state.status = .syncing
        #expect(state.isSyncing)
        #expect(!state.hasError)

        state.status = .error("boom")
        #expect(state.hasError)
        #expect(state.errorMessage == "boom")
        #expect(!state.isSyncing)

        state.status = .idle
        #expect(!state.hasError)
        #expect(state.errorMessage == nil)
    }
}
