//
//  PassRecordSync.swift
//  Groo
//
//  Delta sync over per-item vault records.
//
//  Kept out of PassService.swift, which already carries the service itself; the
//  cursor logic is also where an off-by-one silently drops a record, so it is
//  worth isolating and testing on its own.
//

import CryptoKit
import Foundation
import os

/// One record after decryption. `data` stays as raw JSON bytes so the item is
/// decoded exactly once, by `PassVault`'s existing decoder, preserving both
/// unknown fields and the `.corrupted` fallback.
struct PassDecodedRecord: Equatable {
    let id: String
    let kind: SharedRecordKind
    let data: Data
    let version: Int
    let seq: Int
}

/// Local view of the server's records plus the cursor they were synced to.
struct PassRecordState: Equatable {
    var records: [String: PassDecodedRecord] = [:]
    var cursor: Int = 0

    static let empty = PassRecordState()
}

enum PassRecordSyncError: Error {
    /// The server reported the cursor as too old even on a full resync, which
    /// would otherwise loop forever.
    case cursorRejectedOnFullSync
    case didNotTerminate
}

enum PassRecordSync {

    /// Apply one page to local state.
    ///
    /// The cursor never moves backwards: a stale response must not rewind a
    /// cursor that has already advanced, or the next delta would replay records
    /// already applied.
    static func apply(
        _ state: PassRecordState,
        page: SharedRecordsResponse,
        vaultKey: SymmetricKey
    ) throws -> PassRecordState {
        var next = state
        for record in page.records {
            if record.isDeleted {
                next.records.removeValue(forKey: record.id)
                continue
            }
            guard let decoded = try? SharedRecordCrypto.decryptRecord(record, vaultKey: vaultKey) else {
                // A record this build cannot open (unknown envelope kind, or a
                // key rotation we have not caught up with) is skipped rather
                // than fatal: one bad row must not make the whole vault
                // unopenable.
                Log.pass.error("Skipping undecryptable record \(record.id, privacy: .public)")
                continue
            }
            next.records[record.id] = PassDecodedRecord(
                id: record.id,
                kind: decoded.kind,
                data: decoded.data,
                version: record.version,
                seq: record.seq
            )
        }
        next.cursor = max(next.cursor, page.nextSeq)
        return next
    }

    /// Pull every page from the cursor forward.
    ///
    /// Loops on `hasMore` rather than on a short page: the server may return
    /// fewer rows than requested when its size budget is reached, and treating
    /// that as "done" would silently truncate the vault.
    static func pull(
        from state: PassRecordState,
        vaultKey: SymmetricKey,
        fetch: (Int) async throws -> SharedRecordsResponse
    ) async throws -> PassRecordState {
        var current = state
        var iterations = 0

        while true {
            let page: SharedRecordsResponse
            do {
                page = try await fetch(current.cursor)
            } catch APIError.httpError(_, let code) where code == "CURSOR_TOO_OLD" {
                // Our cursor predates the tombstone purge horizon, so the server
                // can no longer tell us what was deleted. Anything held locally
                // may already be gone — discard it and take a full snapshot
                // rather than merging into stale data and resurrecting deleted
                // records.
                guard current.cursor != 0 else {
                    throw PassRecordSyncError.cursorRejectedOnFullSync
                }
                current = .empty
                continue
            }

            current = try apply(current, page: page, vaultKey: vaultKey)

            if !page.hasMore { return current }

            iterations += 1
            if iterations > 10_000 { throw PassRecordSyncError.didNotTerminate }
        }
    }

    /// Assemble a `PassVault` from decoded records.
    ///
    /// Builds the vault's JSON and hands it to the existing decoder rather than
    /// constructing `PassVaultItem` values directly. That reuses the lossless
    /// decoding and `.corrupted` fallback already proven for the blob format,
    /// instead of adding a second, subtly different decoding path.
    static func buildVault(
        from state: PassRecordState,
        rsaPrivateKey: String? = nil
    ) throws -> PassVault {
        let sorted = state.records.values.sorted { $0.seq < $1.seq }
        let items = sorted.filter { $0.kind == .item }.map(\.data)
        let folders = sorted.filter { $0.kind == .folder }.map(\.data)

        var json = Data(#"{"version":1,"items":["#.utf8)
        json.append(joined(items))
        json.append(Data(#"],"folders":["#.utf8))
        json.append(joined(folders))
        json.append(Data("],\"lastModified\":\(lastModified(sorted))".utf8))
        if let rsaPrivateKey,
           let encoded = try? JSONEncoder().encode([rsaPrivateKey]),
           let element = String(data: encoded.dropFirst().dropLast(), encoding: .utf8) {
            json.append(Data(",\"rsaPrivateKey\":\(element)".utf8))
        }
        json.append(Data("}".utf8))

        return try JSONDecoder().decode(PassVault.self, from: json)
    }

    private static func joined(_ elements: [Data]) -> Data {
        var out = Data()
        for (index, element) in elements.enumerated() {
            if index > 0 { out.append(Data(",".utf8)) }
            out.append(element)
        }
        return out
    }

    private static func lastModified(_ records: [PassDecodedRecord]) -> Int {
        records.compactMap { record -> Int? in
            guard
                let object = try? JSONSerialization.jsonObject(with: record.data) as? [String: Any]
            else { return nil }
            return object["updatedAt"] as? Int
        }.max() ?? 0
    }
}
