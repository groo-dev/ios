//
//  SharedRecordDecoder.swift
//  Groo
//
//  Turns cached per-item records into the credential shapes AutoFill displays.
//
//  This lives in Shared/ rather than in GrooAutoFill so it is reachable from
//  GrooTests: the test bundle hosts the app, not the extension, so anything
//  declared inside the extension target cannot be exercised by a unit test.
//

import CryptoKit
import Foundation

enum SharedRecordDecoder {
    /// Decode records for display only. The lossy `SharedPassVaultItem` is safe
    /// here precisely because AutoFill never writes these back.
    static func decodeItems(
        _ records: [SharedServerRecord],
        key: SymmetricKey
    ) -> (passwords: [SharedPassPasswordItem], passkeys: [SharedPassPasskeyItem]) {
        var passwords: [SharedPassPasswordItem] = []
        var passkeys: [SharedPassPasskeyItem] = []

        for record in records {
            guard
                let decrypted = try? SharedRecordCrypto.decryptRecord(record, vaultKey: key),
                decrypted.kind == .item,
                let item = try? JSONDecoder().decode(SharedPassVaultItem.self, from: decrypted.data)
            else {
                // One unreadable row must not cost the user every other credential.
                continue
            }
            if let password = item.passwordItem, !password.isDeleted { passwords.append(password) }
            if let passkey = item.passkeyItem, !passkey.isDeleted { passkeys.append(passkey) }
        }
        return (passwords, passkeys)
    }
}
