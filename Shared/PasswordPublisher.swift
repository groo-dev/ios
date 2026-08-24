//
//  PasswordPublisher.swift
//  Groo
//
//  Pushes a login created in the AutoFill sheet to the server as one new
//  per-item record.
//
//  Lives in Shared/ rather than GrooAutoFill/ because GrooTests cannot compile
//  extension-target sources. Mirrors PasskeyPublisher deliberately.
//

import CryptoKit
import Foundation
import os

/// Seam so the publisher is testable without a network or an App Group.
protocol PasswordRecordPushing: Sendable {
    func createRecord(_ request: SharedRecordWriteRequest) async throws -> SharedRecordWriteResponse
    func formatVersion() async throws -> Int
}

enum PasswordPublishOutcome: Equatable {
    /// Pushed to the server. Still queued until the app merges it.
    case published
    /// Left queued for the app to drain. Never an error the user sees.
    case queued(reason: String)
}

/// Publishes one login as a single record.
///
/// The record id is brand new, so no conflict is possible: no version to guess,
/// no 409 path, no retry, and no base vault to fetch first.
struct PasswordPublisher {
    let pusher: any PasswordRecordPushing
    let vaultKey: SymmetricKey

    /// Build the record payload.
    ///
    /// Built by hand rather than encoded from `SharedPassPasswordItem`: that
    /// model carries no `createdAt`/`updatedAt`, both of which
    /// `PassPasswordItem.init(from:)` decodes non-optionally and the web
    /// `BaseItem` declares. Encoding the model directly produces a record every
    /// real client fails to decode. Timestamps come from the envelope so the
    /// app's later drain reproduces this payload byte for byte.
    func payload(for pending: SharedPendingPasswordItem) throws -> Data {
        let item = pending.item
        var object: [String: Any] = [
            "id": item.id,
            // The stored discriminator other clients switch on.
            "type": "password",
            "name": item.name,
            "username": item.username,
            "password": item.password,
            "urls": item.urls,
            "createdAt": pending.createdAt,
            "updatedAt": pending.updatedAt,
        ]
        // Optional fields are omitted rather than sent null, matching how the
        // web app encodes an item that has none. `notes`, `totp`, `folderId`
        // and `favorite` are never set by this flow.
        if let deletedAt = item.deletedAt { object["deletedAt"] = deletedAt }
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    /// Push the login to the server.
    ///
    /// Never throws: the sheet must fill the field regardless. Every failure
    /// path leaves the login queued for the app-side drain and is logged.
    func publish(_ pending: SharedPendingPasswordItem) async -> PasswordPublishOutcome {
        do {
            // At format 1 the blob is authoritative and app-owned, so there is
            // nothing safe for the extension to write.
            let format = try await pusher.formatVersion()
            guard format == 2 else {
                Log.autofill.info("Vault is not on per-item records; leaving login queued")
                return .queued(reason: "format \(format)")
            }

            let request = try SharedRecordCrypto.encryptRecord(
                id: pending.item.id, kind: .item, payload: try payload(for: pending), vaultKey: vaultKey
            )

            _ = try await pusher.createRecord(request)

            // Deliberately NOT removed from the pending queue. The queue means
            // "not yet in the cache the extension reads", and only the main app
            // refreshes that cache — so the app clears it, after merging AND
            // refreshing. Its merge dedupes on item id, so an item already
            // pushed here is skipped rather than duplicated.
            Log.autofill.info("Pushed login \(pending.item.id, privacy: .public) to the server")
            return .published
        } catch {
            Log.autofill.error(
                "Login push failed, leaving it queued: \(String(describing: error), privacy: .public)"
            )
            return .queued(reason: String(describing: error))
        }
    }
}

// MARK: - Concrete adapters

/// Backs `PasswordRecordPushing` with the real Pass API.
struct APIPasswordPusher: PasswordRecordPushing {
    let api: PassAPIClient

    func formatVersion() async throws -> Int {
        let probe: SharedFormatProbe = try await api.get(PassAPIClient.Endpoint.keyInfo)
        return probe.formatVersion ?? 1
    }

    func createRecord(_ request: SharedRecordWriteRequest) async throws -> SharedRecordWriteResponse {
        try await api.post(PassAPIClient.Endpoint.records, body: request)
    }
}
