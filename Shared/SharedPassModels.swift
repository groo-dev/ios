//
//  SharedPassModels.swift
//  Groo
//
//  Shared Pass models for app and extensions.
//  Minimal subset needed for AutoFill credential provider.
//

import Foundation

// MARK: - Base64URL Helpers

extension Data {
    /// Initialize from a Base64URL-encoded string (used by WebAuthn for credentialId, userHandle)
    init?(base64URLEncoded string: String) {
        var base64 = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder > 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }
        self.init(base64Encoded: base64)
    }

    /// Encode to Base64URL string (no padding, URL-safe characters)
    var base64URLEncodedString: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

// MARK: - Vault Structure

/// The complete vault structure (decrypted)
struct SharedPassVault: Codable {
    let version: Int
    let items: [SharedPassVaultItem]
    let folders: [SharedPassFolder]
    let lastModified: Int
}

struct SharedPassFolder: Codable, Identifiable {
    let id: String
    var name: String
}

// MARK: - Item Type

enum SharedPassVaultItemType: String, Codable {
    case password
    case passkey
    case note
    case card
    case bankAccount = "bank_account"
    case file
    case cryptoWallet = "crypto_wallet"
}

// MARK: - Vault Item

/// Union type for vault items - we care about password and passkey items for AutoFill
enum SharedPassVaultItem: Codable, Identifiable {
    case password(SharedPassPasswordItem)
    case passkey(SharedPassPasskeyItem)
    case other // All other types we don't need for AutoFill

    var id: String {
        switch self {
        case .password(let item): return item.id
        case .passkey(let item): return item.id
        case .other: return UUID().uuidString
        }
    }

    var passwordItem: SharedPassPasswordItem? {
        if case .password(let item) = self {
            return item
        }
        return nil
    }

    var passkeyItem: SharedPassPasskeyItem? {
        if case .passkey(let item) = self {
            return item
        }
        return nil
    }

    enum CodingKeys: String, CodingKey {
        case type, id
        case username, password, urls
        case rpId, credentialId
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // Try to decode type, or infer it
        let itemType: SharedPassVaultItemType
        if let type = try? container.decode(SharedPassVaultItemType.self, forKey: .type) {
            itemType = type
        } else if container.contains(.rpId) && container.contains(.credentialId) {
            itemType = .passkey
        } else if container.contains(.username) || container.contains(.password) {
            itemType = .password
        } else {
            itemType = .note // Default fallback
        }

        switch itemType {
        case .password:
            self = .password(try SharedPassPasswordItem(from: decoder))
        case .passkey:
            self = .passkey(try SharedPassPasskeyItem(from: decoder))
        default:
            self = .other
        }
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case .password(let item):
            try item.encode(to: encoder)
        case .passkey(let item):
            try item.encode(to: encoder)
        case .other:
            break
        }
    }
}

// MARK: - Password Item

struct SharedPassPasswordItem: Codable, Identifiable {
    let id: String
    let type: SharedPassVaultItemType
    var name: String
    var username: String
    var password: String
    var urls: [String]
    var deletedAt: Int?

    var isDeleted: Bool {
        deletedAt != nil
    }

    /// Get the primary domain for matching
    var primaryDomain: String? {
        guard let urlString = urls.first,
              let url = URL(string: urlString),
              let host = url.host else {
            return nil
        }
        return host.lowercased().replacingOccurrences(of: "www.", with: "")
    }

    /// Get domains from all URLs for matching
    var domains: [String] {
        urls.compactMap { urlString -> String? in
            let str = urlString.hasPrefix("http") ? urlString : "https://\(urlString)"
            guard let url = URL(string: str), let host = url.host else { return nil }
            return host.lowercased().replacingOccurrences(of: "www.", with: "")
        }
    }

    enum CodingKeys: String, CodingKey {
        case id, type, name, username, password, urls, deletedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        type = try container.decodeIfPresent(SharedPassVaultItemType.self, forKey: .type) ?? .password
        name = try container.decode(String.self, forKey: .name)
        username = try container.decode(String.self, forKey: .username)
        password = try container.decode(String.self, forKey: .password)
        urls = try container.decode([String].self, forKey: .urls)
        deletedAt = try container.decodeIfPresent(Int.self, forKey: .deletedAt)
    }
}

// MARK: - Passkey Item

struct SharedPassPasskeyItem: Codable, Identifiable {
    let id: String
    let type: SharedPassVaultItemType
    var name: String
    var rpId: String
    var rpName: String
    var credentialId: String   // base64url encoded
    var publicKey: String      // base64 encoded SPKI format
    var privateKey: String     // base64 encoded PKCS8 format
    var userHandle: String     // base64url encoded
    var userName: String
    var signCount: Int
    var deletedAt: Int?

    var isDeleted: Bool {
        deletedAt != nil
    }

    enum CodingKeys: String, CodingKey {
        case id, type, name, rpId, rpName, credentialId, publicKey, privateKey, userHandle, userName, signCount, deletedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        type = try container.decodeIfPresent(SharedPassVaultItemType.self, forKey: .type) ?? .passkey
        name = try container.decode(String.self, forKey: .name)
        rpId = try container.decode(String.self, forKey: .rpId)
        rpName = try container.decode(String.self, forKey: .rpName)
        credentialId = try container.decode(String.self, forKey: .credentialId)
        publicKey = try container.decode(String.self, forKey: .publicKey)
        privateKey = try container.decode(String.self, forKey: .privateKey)
        userHandle = try container.decode(String.self, forKey: .userHandle)
        userName = try container.decode(String.self, forKey: .userName)
        signCount = try container.decode(Int.self, forKey: .signCount)
        deletedAt = try container.decodeIfPresent(Int.self, forKey: .deletedAt)
    }
}
