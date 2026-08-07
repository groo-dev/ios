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

protocol PendingPasskeyRemoving: Sendable {
    func remove(credentialId: String, key: SymmetricKey) throws
}

enum PasskeyPublishOutcome: Equatable {
    /// Pushed and removed from the queue.
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
    let queue: any PendingPasskeyRemoving
    let vaultKey: SymmetricKey

    /// Push, then remove from the queue.
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

            let payload = try JSONEncoder().encode(item)
            let request = try SharedRecordCrypto.encryptRecord(
                id: item.id, kind: .item, payload: payload, vaultKey: vaultKey
            )

            _ = try await pusher.createRecord(request)

            // Remove only this credential: another passkey may be queued
            // alongside it, holding a private key that exists nowhere else.
            do {
                try queue.remove(credentialId: item.credentialId, key: vaultKey)
            } catch {
                // Harmless — the app's merge dedupes on credentialId, so a
                // failed removal produces a no-op rather than a duplicate.
                Log.autofill.error(
                    "Pushed passkey but could not remove it from the queue: \(String(describing: error), privacy: .public)"
                )
            }

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
