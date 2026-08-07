//
//  PasskeyPublisher.swift
//  Groo
//
//  Pushes a newly registered passkey to the server during the AutoFill
//  registration ceremony, so it is durable before the relying party is told the
//  credential exists.
//
//  Lives in Shared/ rather than GrooAutoFill/ because GrooTests cannot compile
//  extension-target sources; the file in GrooAutoFill/ is construction only.
//

import CryptoKit
import Foundation
import os

/// Seams so the publisher is testable without a network or an App Group.
protocol PasskeyRecordPushing: Sendable {
    func createRecord(_ request: SharedRecordWriteRequest) async throws -> SharedRecordWriteResponse
    func formatVersion() async throws -> Int
}

enum PasskeyPublishOutcome: Equatable {
    /// Pushed to the server. Still queued until the app merges it.
    case published
    /// Left queued for the app to drain. Never an error the ceremony sees.
    case queued(reason: String)
}

/// Publishes one passkey as a single record.
///
/// The record id is brand new, so **no conflict is possible**: there is no
/// version to guess, no 409 path, no retry, and no base vault to fetch first.
/// That is the whole reason this is possible at all — under the blob format the
/// extension would have had to read, decode, mutate and re-encode the entire
/// vault through models that silently drop item types.
struct PasskeyPublisher {
    let pusher: any PasskeyRecordPushing
    let vaultKey: SymmetricKey
    /// Epoch milliseconds. Injected so the payload's timestamps are assertable.
    var now: @Sendable () -> Int = { Int(Date().timeIntervalSince1970 * 1000) }

    /// Build the record payload.
    ///
    /// `SharedPassPasskeyItem` does NOT model `createdAt`/`updatedAt` — encoding
    /// it directly produces a record that every real client fails to decode
    /// ("Key 'createdAt' not found"), because `PassPasskeyItem` requires both.
    /// The payload must match that encoded shape exactly, so it is built here
    /// rather than delegated to the lossy model.
    ///
    /// This is the one place the extension AUTHORS an item. Per-item records
    /// remove the risk of a client corrupting items it merely rewrites; they do
    /// not remove it here.
    func payload(for item: SharedPassPasskeyItem) throws -> Data {
        let timestamp = now()
        var object: [String: Any] = [
            "id": item.id,
            // The stored discriminator other clients switch on.
            "type": "passkey",
            "name": item.name,
            "rpId": item.rpId,
            "rpName": item.rpName,
            "credentialId": item.credentialId,
            "publicKey": item.publicKey,
            "privateKey": item.privateKey,
            "userHandle": item.userHandle,
            "userName": item.userName,
            "signCount": item.signCount,
            "createdAt": timestamp,
            "updatedAt": timestamp,
        ]
        // Optional fields are omitted rather than sent null, matching how the
        // web app encodes an item that has none.
        if let deletedAt = item.deletedAt { object["deletedAt"] = deletedAt }
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    /// Push the passkey to the server.
    ///
    /// Never throws: the caller must complete the registration ceremony
    /// regardless. Every failure path leaves the passkey queued for the
    /// app-side drain and is logged at `.error` — silent failures are what made
    /// the two preceding AutoFill bugs undiagnosable.
    func publish(_ item: SharedPassPasskeyItem) async -> PasskeyPublishOutcome {
        do {
            // The push only exists once records are authoritative. At format 1
            // the passkey simply stays queued and the app drains it, exactly as
            // it does today.
            let format = try await pusher.formatVersion()
            guard format == 2 else {
                Log.autofill.info("Vault is not on per-item records; leaving passkey queued")
                return .queued(reason: "format \(format)")
            }

            let request = try SharedRecordCrypto.encryptRecord(
                id: item.id, kind: .item, payload: try payload(for: item), vaultKey: vaultKey
            )

            _ = try await pusher.createRecord(request)

            // Deliberately NOT removed from the pending queue.
            //
            // AutoFill builds its passkey list from the App Group vault cache
            // PLUS the pending queue, and only the main app's sync refreshes
            // that cache. Dropping the item here left it in neither, so the very
            // next assertion failed with credentialIdentityNotFound until the
            // user opened the app.
            //
            // The queue means "not yet in the cache the extension reads", so it
            // is the app that clears it — after merging AND refreshing the
            // cache. Its merge dedupes on credentialId, so an item already
            // pushed here is skipped rather than duplicated.

            Log.autofill.info("Pushed passkey \(item.credentialId, privacy: .public) to the server")
            return .published
        } catch {
            Log.autofill.error(
                "Passkey push failed, leaving it queued: \(String(describing: error), privacy: .public)"
            )
            return .queued(reason: String(describing: error))
        }
    }
}

// MARK: - Concrete adapters

/// Backs `PasskeyRecordPushing` with the real Pass API.
struct APIPasskeyPusher: PasskeyRecordPushing {
    let api: PassAPIClient

    /// Only the format flag is needed here, so this decodes a minimal shape
    /// rather than `PassKeyInfo` — that type lives in the app target, which
    /// extensions cannot see.
    private struct FormatProbe: Decodable {
        let formatVersion: Int?
    }

    func formatVersion() async throws -> Int {
        let probe: FormatProbe = try await api.get(PassAPIClient.Endpoint.keyInfo)
        return probe.formatVersion ?? 1
    }

    func createRecord(_ request: SharedRecordWriteRequest) async throws -> SharedRecordWriteResponse {
        try await api.post(PassAPIClient.Endpoint.records, body: request)
    }
}

