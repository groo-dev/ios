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
