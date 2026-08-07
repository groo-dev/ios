//
//  SharedRecordCrypto.swift
//  Groo
//
//  Envelope crypto for per-item vault records, shared by the app and the
//  AutoFill extension.
//
//  Byte-identical to `encryptRecord`/`decryptRecord` in @pass/crypto
//  (pass/packages/crypto/src/records.ts). Two framing details are load-bearing;
//  getting either wrong still passes every Swift test while making real vaults
//  unopenable, so both are pinned by the committed record-vector.json:
//
//  1. The record key is wrapped as the base64 STRING of its raw bytes,
//     encrypted as UTF-8 — not the raw bytes. That is what
//     `CryptoService.wrapKey` already does, so this reuses that framing rather
//     than reimplementing it. A correct `wrappedRecordKey` is 80 base64 chars.
//  2. `iv` and `ciphertext+tag` are SEPARATE base64 fields. This is the
//     `EncryptedPayload` layout, not the combined IV+ciphertext+tag layout that
//     `CryptoService.encryptData` uses for file blobs.
//

import CryptoKit
import Foundation

enum SharedRecordCryptoError: Error {
    case invalidBase64
    case encryptionFailed
    case decryptionFailed
    case malformedEnvelope
    case unknownKind(String)
}

enum SharedRecordCrypto {
    private static let ivLength = 12
    private static let keyLength = 32

    // MARK: - Primitives (framing shared with CryptoService)

    /// AES-GCM encrypt, returning base64 (ciphertext+tag) and base64 iv as
    /// separate values — the web `encrypt()` layout.
    private static func seal(
        _ plaintext: Data,
        using key: SymmetricKey
    ) throws -> (ciphertext: String, iv: String) {
        let nonce = AES.GCM.Nonce()
        let box = try AES.GCM.seal(plaintext, using: key, nonce: nonce)
        guard let combined = box.combined else {
            throw SharedRecordCryptoError.encryptionFailed
        }
        // Drop the nonce; it travels in its own field.
        return (
            ciphertext: combined.dropFirst(ivLength).base64EncodedString(),
            iv: Data(nonce).base64EncodedString()
        )
    }

    private static func open(
        ciphertext: String,
        iv: String,
        using key: SymmetricKey
    ) throws -> Data {
        guard
            let ivData = Data(base64Encoded: iv),
            let ctData = Data(base64Encoded: ciphertext)
        else {
            throw SharedRecordCryptoError.invalidBase64
        }
        var combined = Data(ivData)
        combined.append(ctData)
        let box = try AES.GCM.SealedBox(combined: combined)
        return try AES.GCM.open(box, using: key)
    }

    // MARK: - Records

    /// Encrypt one record. `payload` is the item or folder JSON, embedded into
    /// the envelope verbatim so unknown fields survive untouched.
    static func encryptRecord(
        id: String,
        kind: SharedRecordKind,
        payload: Data,
        vaultKey: SymmetricKey
    ) throws -> SharedRecordWriteRequest {
        // Build {"kind":…,"data":…} without decoding `payload`: re-encoding it
        // through a typed model is what would silently drop fields.
        var envelope = Data(#"{"kind":"#.utf8)
        envelope.append(Data("\"\(kind.rawValue)\",\"data\":".utf8))
        envelope.append(payload)
        envelope.append(Data("}".utf8))

        let recordKey = SymmetricKey(size: .bits256)
        let sealed = try seal(envelope, using: recordKey)

        // Wrap the base64 string of the key bytes, as UTF-8. See the file header.
        let rawKeyBase64 = recordKey.withUnsafeBytes { Data($0) }.base64EncodedString()
        let wrapped = try seal(Data(rawKeyBase64.utf8), using: vaultKey)

        return SharedRecordWriteRequest(
            id: id,
            encryptedData: sealed.ciphertext,
            iv: sealed.iv,
            wrappedRecordKey: wrapped.ciphertext,
            wrapIv: wrapped.iv
        )
    }

    /// Decrypt one record, returning the `data` JSON bytes untouched so the
    /// caller can decode losslessly (see `PassRawJSON`).
    static func decryptRecord(
        encryptedData: String,
        iv: String,
        wrappedRecordKey: String,
        wrapIv: String,
        vaultKey: SymmetricKey
    ) throws -> (kind: SharedRecordKind, data: Data) {
        let rawKeyBase64 = try open(
            ciphertext: wrappedRecordKey, iv: wrapIv, using: vaultKey
        )
        guard
            let keyString = String(data: rawKeyBase64, encoding: .utf8),
            let keyData = Data(base64Encoded: keyString),
            keyData.count == keyLength
        else {
            throw SharedRecordCryptoError.decryptionFailed
        }
        let recordKey = SymmetricKey(data: keyData)

        let envelope = try open(ciphertext: encryptedData, iv: iv, using: recordKey)

        guard
            let object = try JSONSerialization.jsonObject(with: envelope) as? [String: Any],
            let kindString = object["kind"] as? String
        else {
            throw SharedRecordCryptoError.malformedEnvelope
        }
        guard let kind = SharedRecordKind(rawValue: kindString) else {
            throw SharedRecordCryptoError.unknownKind(kindString)
        }
        guard object["data"] != nil else {
            throw SharedRecordCryptoError.malformedEnvelope
        }

        // Re-serialise just the `data` subtree. JSONSerialization is used rather
        // than a typed model precisely so unmodelled fields pass through.
        let data = try JSONSerialization.data(
            withJSONObject: object["data"] as Any,
            options: [.fragmentsAllowed]
        )
        return (kind, data)
    }

    /// Convenience for a record straight off the wire. Returns nil for a
    /// tombstone, which carries no content.
    static func decryptRecord(
        _ record: SharedServerRecord,
        vaultKey: SymmetricKey
    ) throws -> (kind: SharedRecordKind, data: Data)? {
        guard
            !record.isDeleted,
            let encryptedData = record.encryptedData,
            let iv = record.iv,
            let wrappedRecordKey = record.wrappedRecordKey,
            let wrapIv = record.wrapIv
        else {
            return nil
        }
        return try decryptRecord(
            encryptedData: encryptedData,
            iv: iv,
            wrappedRecordKey: wrappedRecordKey,
            wrapIv: wrapIv,
            vaultKey: vaultKey
        )
    }
}
