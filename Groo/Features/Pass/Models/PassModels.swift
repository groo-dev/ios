//
//  PassModels.swift
//  Groo
//
//  Data models for Pass feature - matches pass/web/src/lib/types.ts exactly.
//

import Foundation

// MARK: - API Response Types

/// Vault response from GET /v1/vault
struct PassVaultResponse: Codable {
    let encryptedData: String  // base64 encoded
    let iv: String             // base64 encoded
    let version: Int           // for optimistic locking
    let updatedAt: Int         // Unix timestamp
}

/// Key info response from GET /v1/vault/key-info
struct PassKeyInfo: Codable {
    let keySalt: String        // base64 encoded
    let kdfIterations: Int
}

/// Setup request for POST /v1/vault/setup
struct PassVaultSetupRequest: Codable {
    let keySalt: String        // base64 encoded
    let kdfIterations: Int?
    let encryptedData: String  // base64 encoded
    let iv: String             // base64 encoded
}

/// Update request for PUT /v1/vault
struct PassVaultUpdateRequest: Codable {
    let encryptedData: String  // base64 encoded
    let iv: String             // base64 encoded
    let expectedVersion: Int   // for optimistic locking
}

// MARK: - Vault Structure (decrypted client-side)

/// The complete vault structure (decrypted)
struct PassVault: Codable, Equatable {
    var version: Int
    var items: [PassVaultItem]
    var folders: [PassFolder]
    var lastModified: Int
    var rsaPrivateKey: String?  // JWK format, for sharing (optional)

    static var empty: PassVault {
        PassVault(version: 1, items: [], folders: [], lastModified: Int(Date().timeIntervalSince1970 * 1000))
    }
}

/// Folder for organizing items
struct PassFolder: Codable, Identifiable, Equatable {
    let id: String
    var name: String
    var parentId: String?
}

// MARK: - Vault Item Types

enum PassVaultItemType: String, Codable, CaseIterable {
    case password
    case passkey
    case note
    case card
    case bankAccount = "bank_account"
    case file

    var label: String {
        switch self {
        case .password: "Password"
        case .passkey: "Passkey"
        case .note: "Secure Note"
        case .card: "Card"
        case .bankAccount: "Bank Account"
        case .file: "File"
        }
    }

    var icon: String {
        switch self {
        case .password: "key.fill"
        case .passkey: "person.badge.key"
        case .note: "doc.text.fill"
        case .card: "creditcard.fill"
        case .bankAccount: "building.columns"
        case .file: "doc.fill"
        }
    }
}

/// Union type for all vault items
enum PassVaultItem: Codable, Identifiable, Equatable {
    case password(PassPasswordItem)
    case passkey(PassPasskeyItem)
    case note(PassNoteItem)
    case card(PassCardItem)
    case bankAccount(PassBankAccountItem)
    case file(PassFileItem)

    var id: String {
        switch self {
        case .password(let item): item.id
        case .passkey(let item): item.id
        case .note(let item): item.id
        case .card(let item): item.id
        case .bankAccount(let item): item.id
        case .file(let item): item.id
        }
    }

    var name: String {
        switch self {
        case .password(let item): item.name
        case .passkey(let item): item.name
        case .note(let item): item.name
        case .card(let item): item.name
        case .bankAccount(let item): item.name
        case .file(let item): item.name
        }
    }

    var type: PassVaultItemType {
        switch self {
        case .password: .password
        case .passkey: .passkey
        case .note: .note
        case .card: .card
        case .bankAccount: .bankAccount
        case .file: .file
        }
    }

    var folderId: String? {
        switch self {
        case .password(let item): item.folderId
        case .passkey(let item): item.folderId
        case .note(let item): item.folderId
        case .card(let item): item.folderId
        case .bankAccount(let item): item.folderId
        case .file(let item): item.folderId
        }
    }

    var favorite: Bool {
        switch self {
        case .password(let item): item.favorite ?? false
        case .passkey(let item): item.favorite ?? false
        case .note(let item): item.favorite ?? false
        case .card(let item): item.favorite ?? false
        case .bankAccount(let item): item.favorite ?? false
        case .file(let item): item.favorite ?? false
        }
    }

    var deletedAt: Int? {
        switch self {
        case .password(let item): item.deletedAt
        case .passkey(let item): item.deletedAt
        case .note(let item): item.deletedAt
        case .card(let item): item.deletedAt
        case .bankAccount(let item): item.deletedAt
        case .file(let item): item.deletedAt
        }
    }

    var createdAt: Int {
        switch self {
        case .password(let item): item.createdAt
        case .passkey(let item): item.createdAt
        case .note(let item): item.createdAt
        case .card(let item): item.createdAt
        case .bankAccount(let item): item.createdAt
        case .file(let item): item.createdAt
        }
    }

    var updatedAt: Int {
        switch self {
        case .password(let item): item.updatedAt
        case .passkey(let item): item.updatedAt
        case .note(let item): item.updatedAt
        case .card(let item): item.updatedAt
        case .bankAccount(let item): item.updatedAt
        case .file(let item): item.updatedAt
        }
    }

    var isDeleted: Bool {
        deletedAt != nil
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case type
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(PassVaultItemType.self, forKey: .type)

        switch type {
        case .password:
            self = .password(try PassPasswordItem(from: decoder))
        case .passkey:
            self = .passkey(try PassPasskeyItem(from: decoder))
        case .note:
            self = .note(try PassNoteItem(from: decoder))
        case .card:
            self = .card(try PassCardItem(from: decoder))
        case .bankAccount:
            self = .bankAccount(try PassBankAccountItem(from: decoder))
        case .file:
            self = .file(try PassFileItem(from: decoder))
        }
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case .password(let item): try item.encode(to: encoder)
        case .passkey(let item): try item.encode(to: encoder)
        case .note(let item): try item.encode(to: encoder)
        case .card(let item): try item.encode(to: encoder)
        case .bankAccount(let item): try item.encode(to: encoder)
        case .file(let item): try item.encode(to: encoder)
        }
    }
}

// MARK: - Item Types

/// Base protocol for all items
protocol PassBaseItem: Codable, Identifiable, Equatable {
    var id: String { get }
    static var itemType: PassVaultItemType { get }
    var name: String { get set }
    var folderId: String? { get set }
    var favorite: Bool? { get set }
    var createdAt: Int { get }
    var updatedAt: Int { get set }
    var deletedAt: Int? { get set }
}

extension PassBaseItem {
    var type: PassVaultItemType { Self.itemType }
}

/// Password / Login item
struct PassPasswordItem: PassBaseItem {
    let id: String
    var name: String
    var username: String
    var password: String
    var urls: [String]
    var notes: String?
    var totp: PassTotpConfig?
    var folderId: String?
    var favorite: Bool?
    var createdAt: Int
    var updatedAt: Int
    var deletedAt: Int?

    static var itemType: PassVaultItemType { .password }

    static func create(
        name: String,
        username: String = "",
        password: String = "",
        urls: [String] = [],
        notes: String? = nil,
        totp: PassTotpConfig? = nil,
        folderId: String? = nil
    ) -> PassPasswordItem {
        let now = Int(Date().timeIntervalSince1970 * 1000)
        return PassPasswordItem(
            id: UUID().uuidString.lowercased(),
            name: name,
            username: username,
            password: password,
            urls: urls,
            notes: notes,
            totp: totp,
            folderId: folderId,
            favorite: false,
            createdAt: now,
            updatedAt: now
        )
    }
}

/// TOTP configuration for 2FA
struct PassTotpConfig: Codable, Equatable {
    let secret: String
    let algorithm: PassTotpAlgorithm
    let digits: Int  // 6 or 8
    let period: Int  // usually 30

    enum PassTotpAlgorithm: String, Codable {
        case sha1 = "SHA1"
        case sha256 = "SHA256"
        case sha512 = "SHA512"
    }
}

/// Passkey / WebAuthn item
struct PassPasskeyItem: PassBaseItem {
    let id: String
    var name: String
    var rpId: String
    var rpName: String
    var credentialId: String
    var publicKey: String
    var privateKey: String
    var userHandle: String
    var userName: String
    var signCount: Int
    var folderId: String?
    var favorite: Bool?
    var createdAt: Int
    var updatedAt: Int
    var deletedAt: Int?

    static var itemType: PassVaultItemType { .passkey }
}

/// Secure Note item
struct PassNoteItem: PassBaseItem {
    let id: String
    var name: String
    var content: String
    var folderId: String?
    var favorite: Bool?
    var createdAt: Int
    var updatedAt: Int
    var deletedAt: Int?

    static var itemType: PassVaultItemType { .note }

    static func create(name: String, content: String = "", folderId: String? = nil) -> PassNoteItem {
        let now = Int(Date().timeIntervalSince1970 * 1000)
        return PassNoteItem(
            id: UUID().uuidString.lowercased(),
            name: name,
            content: content,
            folderId: folderId,
            favorite: false,
            createdAt: now,
            updatedAt: now
        )
    }
}

/// Credit/Debit Card item
struct PassCardItem: PassBaseItem {
    let id: String
    var name: String
    var cardholderName: String
    var number: String
    var expMonth: String
    var expYear: String
    var cvv: String
    var brand: String?
    var notes: String?
    var folderId: String?
    var favorite: Bool?
    var createdAt: Int
    var updatedAt: Int
    var deletedAt: Int?

    static var itemType: PassVaultItemType { .card }

    static func create(
        name: String,
        cardholderName: String = "",
        number: String = "",
        expMonth: String = "",
        expYear: String = "",
        cvv: String = "",
        brand: String? = nil,
        notes: String? = nil,
        folderId: String? = nil
    ) -> PassCardItem {
        let now = Int(Date().timeIntervalSince1970 * 1000)
        return PassCardItem(
            id: UUID().uuidString.lowercased(),
            name: name,
            cardholderName: cardholderName,
            number: number,
            expMonth: expMonth,
            expYear: expYear,
            cvv: cvv,
            brand: brand,
            notes: notes,
            folderId: folderId,
            favorite: false,
            createdAt: now,
            updatedAt: now
        )
    }
}

/// Bank Account item
struct PassBankAccountItem: PassBaseItem {
    let id: String
    var name: String
    var bankName: String
    var accountType: PassBankAccountType
    var accountNumber: String
    var routingNumber: String?
    var iban: String?
    var swiftBic: String?
    var notes: String?
    var folderId: String?
    var favorite: Bool?
    var createdAt: Int
    var updatedAt: Int
    var deletedAt: Int?

    static var itemType: PassVaultItemType { .bankAccount }

    enum PassBankAccountType: String, Codable {
        case checking
        case savings
        case other
    }
}

/// Encrypted File item (metadata only, file stored in R2)
struct PassFileItem: PassBaseItem {
    let id: String
    var name: String
    var fileName: String
    var fileSize: Int
    var mimeType: String
    var r2Key: String
    var encryptionIv: String
    var notes: String?
    var folderId: String?
    var favorite: Bool?
    var createdAt: Int
    var updatedAt: Int
    var deletedAt: Int?

    static var itemType: PassVaultItemType { .file }
}

// MARK: - Audit Types

enum PassAuditAction: String, Codable {
    case vaultUnlock = "vault_unlock"
    case vaultLock = "vault_lock"
    case vaultExport = "vault_export"
    case itemView = "item_view"
    case itemCreate = "item_create"
    case itemUpdate = "item_update"
    case itemDelete = "item_delete"
    case itemCopy = "item_copy"
    case itemRestore = "item_restore"
    case itemPermanentDelete = "item_permanent_delete"
    case trashEmptied = "trash_emptied"
}

struct PassAuditLogRequest: Codable {
    let action: PassAuditAction
    let itemId: String?
    let itemName: String?
    let itemType: String?
}
