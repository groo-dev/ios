//
//  SharedRecordCryptoTests.swift
//  GrooTests
//

import CryptoKit
import Foundation
import Testing
@testable import Groo

struct SharedRecordCryptoTests {

    // MARK: - Format vector
    //
    // The vector is produced by @pass/crypto itself
    // (pass/packages/crypto/scripts/generate-record-vector.mjs). These are the
    // only tests here that can catch byte-format drift between this
    // implementation and the web app / browser extension; a Swift-only round
    // trip agrees with whatever this file happens to do.

    private struct RecordVector: Decodable {
        struct Case: Decodable {
            struct Record: Decodable {
                let id: String
                let encryptedData: String
                let iv: String
                let wrappedRecordKey: String
                let wrapIv: String
            }
            let record: Record
            let expectedKind: String
        }
        let vaultKeyRaw: String
        let item: Case
        let folder: Case
    }

    private func loadVector() throws -> RecordVector {
        let bundle = Bundle(for: RecordVectorBundleToken.self)
        let url = try #require(
            bundle.url(forResource: "record-vector", withExtension: "json"),
            "record-vector.json is not a member of the GrooTests target"
        )
        return try JSONDecoder().decode(RecordVector.self, from: Data(contentsOf: url))
    }

    private func vaultKey(_ vector: RecordVector) throws -> SymmetricKey {
        let raw = try #require(Data(base64Encoded: vector.vaultKeyRaw))
        return SymmetricKey(data: raw)
    }

    @Test("decrypts the committed item vector produced by @pass/crypto")
    func itemVector() throws {
        let vector = try loadVector()
        let out = try SharedRecordCrypto.decryptRecord(
            encryptedData: vector.item.record.encryptedData,
            iv: vector.item.record.iv,
            wrappedRecordKey: vector.item.record.wrappedRecordKey,
            wrapIv: vector.item.record.wrapIv,
            vaultKey: try vaultKey(vector)
        )

        #expect(out.kind == .item)
        let payload = try #require(
            try JSONSerialization.jsonObject(with: out.data) as? [String: Any]
        )
        #expect(payload["id"] as? String == "vector-item")
        #expect(payload["type"] as? String == "password")
        #expect(payload["password"] as? String == "s3cr3t-p@ssw0rd")
    }

    @Test("preserves the vector's unknown future field")
    func unknownFieldsSurvive() throws {
        let vector = try loadVector()
        let out = try SharedRecordCrypto.decryptRecord(
            encryptedData: vector.item.record.encryptedData,
            iv: vector.item.record.iv,
            wrappedRecordKey: vector.item.record.wrappedRecordKey,
            wrapIv: vector.item.record.wrapIv,
            vaultKey: try vaultKey(vector)
        )

        let payload = try #require(
            try JSONSerialization.jsonObject(with: out.data) as? [String: Any]
        )
        // A field no Swift model knows about must still reach the caller, or a
        // future item type loses data whenever an older client touches it.
        let future = try #require(payload["futureField"] as? [String: Any])
        #expect(future["nested"] as? [Int] == [1, 2, 3])
        #expect(future["flag"] as? Bool == true)
    }

    @Test("decrypts the committed folder vector")
    func folderVector() throws {
        let vector = try loadVector()
        let out = try SharedRecordCrypto.decryptRecord(
            encryptedData: vector.folder.record.encryptedData,
            iv: vector.folder.record.iv,
            wrappedRecordKey: vector.folder.record.wrappedRecordKey,
            wrapIv: vector.folder.record.wrapIv,
            vaultKey: try vaultKey(vector)
        )

        #expect(out.kind == .folder)
        let payload = try #require(
            try JSONSerialization.jsonObject(with: out.data) as? [String: Any]
        )
        #expect(payload["name"] as? String == "Work")
    }

    @Test("this implementation reproduces the vector's wrap framing")
    func wrapFraming() throws {
        let vector = try loadVector()
        let produced = try SharedRecordCrypto.encryptRecord(
            id: "x", kind: .item, payload: Data("{}".utf8), vaultKey: try vaultKey(vector)
        )
        // 32 key bytes -> 44-char base64 -> 44 UTF-8 bytes + 16-byte GCM tag
        // = 60 bytes -> 80 base64 chars. A different length means the wrap
        // framing drifted (e.g. wrapping raw bytes), which silently breaks
        // every other client.
        #expect(produced.wrappedRecordKey.count == 80)
        #expect(produced.wrappedRecordKey.count == vector.item.record.wrappedRecordKey.count)
        #expect(produced.wrapIv.count == vector.item.record.wrapIv.count)
    }

    // MARK: - Round trip

    @Test("round-trips an item payload byte-for-byte")
    func roundTrip() throws {
        let vaultKey = SymmetricKey(size: .bits256)
        let payload = Data(#"{"id":"a","type":"note","content":"hi","extra":{"n":[1,2]}}"#.utf8)

        let enc = try SharedRecordCrypto.encryptRecord(
            id: "a", kind: .item, payload: payload, vaultKey: vaultKey
        )
        let out = try SharedRecordCrypto.decryptRecord(
            encryptedData: enc.encryptedData,
            iv: enc.iv,
            wrappedRecordKey: enc.wrappedRecordKey,
            wrapIv: enc.wrapIv,
            vaultKey: vaultKey
        )

        #expect(out.kind == .item)
        let a = try JSONSerialization.jsonObject(with: out.data) as? [String: Any]
        let b = try JSONSerialization.jsonObject(with: payload) as? [String: Any]
        #expect(NSDictionary(dictionary: a ?? [:]) == NSDictionary(dictionary: b ?? [:]))
    }

    @Test("uses a distinct record key per record")
    func distinctKeys() throws {
        let vaultKey = SymmetricKey(size: .bits256)
        let a = try SharedRecordCrypto.encryptRecord(
            id: "a", kind: .item, payload: Data("{}".utf8), vaultKey: vaultKey
        )
        let b = try SharedRecordCrypto.encryptRecord(
            id: "b", kind: .item, payload: Data("{}".utf8), vaultKey: vaultKey
        )
        #expect(a.wrappedRecordKey != b.wrappedRecordKey)
    }

    @Test("fails under a different vault key")
    func wrongVaultKey() throws {
        let enc = try SharedRecordCrypto.encryptRecord(
            id: "a", kind: .item, payload: Data("{}".utf8), vaultKey: SymmetricKey(size: .bits256)
        )
        #expect(throws: (any Error).self) {
            try SharedRecordCrypto.decryptRecord(
                encryptedData: enc.encryptedData,
                iv: enc.iv,
                wrappedRecordKey: enc.wrappedRecordKey,
                wrapIv: enc.wrapIv,
                vaultKey: SymmetricKey(size: .bits256)
            )
        }
    }

    @Test("returns nil for a tombstone rather than throwing")
    func tombstone() throws {
        let record = SharedServerRecord(
            id: "gone",
            encryptedData: nil, iv: nil, wrappedRecordKey: nil, wrapIv: nil,
            version: 2, seq: 9, isDeleted: true, createdAt: 1, updatedAt: 1
        )
        let out = try SharedRecordCrypto.decryptRecord(
            record, vaultKey: SymmetricKey(size: .bits256)
        )
        #expect(out == nil)
    }
}

/// Locates the test bundle so the committed vector can be read. `CryptoServiceWrapTests`
/// declares its own file-private token for the same purpose.
private final class RecordVectorBundleToken {}
