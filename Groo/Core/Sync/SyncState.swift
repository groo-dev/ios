//
//  SyncState.swift
//  Groo
//
//  Observable sync status for UI display.
//

import Foundation

enum SyncStatus: Equatable {
    case idle
    case syncing
    case error(String)
    case offline
}

@MainActor
@Observable
class SyncState {
    var status: SyncStatus = .idle
    var lastSyncedAt: Date?
    var pendingOperationsCount: Int = 0

    var isOnline: Bool = true {
        didSet {
            if !isOnline {
                status = .offline
            } else if status == .offline {
                status = .idle
            }
        }
    }

    var isSyncing: Bool {
        status == .syncing
    }

    var hasError: Bool {
        if case .error = status { return true }
        return false
    }

    var errorMessage: String? {
        if case .error(let message) = status {
            return message
        }
        return nil
    }
}
