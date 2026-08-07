//
//  SharedRecordModels.swift
//  Groo
//
//  Wire types for the per-item vault record API, shared by the app and the
//  AutoFill extension. Mirrors pass/apps/api/src/types.ts.
//

import Foundation

/// What a record holds. The server cannot read this — it lives inside the
/// encrypted envelope, so the server genuinely cannot tell an item from a folder.
enum SharedRecordKind: String, Codable {
    case item
    case folder
}

/// One row as the server returns it. The four content fields are nil for a
/// tombstone (a permanently deleted record, retained so other devices learn of
/// the deletion instead of resurrecting the item on their next sync).
struct SharedServerRecord: Codable, Equatable {
    let id: String
    let encryptedData: String?
    let iv: String?
    let wrappedRecordKey: String?
    let wrapIv: String?
    let version: Int
    let seq: Int
    let isDeleted: Bool
    let createdAt: Int
    let updatedAt: Int
}

struct SharedRecordsResponse: Codable {
    let records: [SharedServerRecord]
    let nextSeq: Int
    let hasMore: Bool
    let formatVersion: Int
}

/// A record write. `expectedVersion` is omitted on create and required on
/// update, where it is the per-record optimistic lock.
struct SharedRecordWriteRequest: Codable, Equatable {
    let id: String
    let encryptedData: String
    let iv: String
    let wrappedRecordKey: String
    let wrapIv: String
    var expectedVersion: Int?

    init(
        id: String,
        encryptedData: String,
        iv: String,
        wrappedRecordKey: String,
        wrapIv: String,
        expectedVersion: Int? = nil
    ) {
        self.id = id
        self.encryptedData = encryptedData
        self.iv = iv
        self.wrappedRecordKey = wrappedRecordKey
        self.wrapIv = wrapIv
        self.expectedVersion = expectedVersion
    }
}

/// `GET /v1/vault/private-key`. The RSA private key for sharing, encrypted
/// under the vault key. Stored in its own column rather than as a record: it
/// must never be shareable, trashable, or carried by the sync cursor.
struct SharedPrivateKeyResponse: Codable {
    let encryptedPrivateKey: String
    let privateKeyIv: String
}

/// Response to a single-record create or update.
struct SharedRecordWriteResponse: Codable {
    let id: String
    let seq: Int
    let version: Int
}

/// Response to a record delete. No `version`: the row is a tombstone now.
struct SharedRecordDeleteResponse: Codable {
    let id: String
    let seq: Int
}

/// Just the format flag from `GET /v1/vault/key-info`.
///
/// Decoded instead of `PassKeyInfo` because that type lives in the app target,
/// which extensions cannot see. Optional so an older server, which omits the
/// field, reads as format 1.
struct SharedFormatProbe: Decodable {
    let formatVersion: Int?
}
