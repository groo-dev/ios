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

    enum CodingKeys: String, CodingKey {
        case version, items, folders, lastModified, rsaPrivateKey
    }

    init(version: Int, items: [PassVaultItem], folders: [PassFolder], lastModified: Int, rsaPrivateKey: String? = nil) {
        self.version = version
        self.items = items
        self.folders = folders
        self.lastModified = lastModified
        self.rsaPrivateKey = rsaPrivateKey
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        version = try container.decode(Int.self, forKey: .version)
        folders = try container.decode([PassFolder].self, forKey: .folders)
        lastModified = try container.decode(Int.self, forKey: .lastModified)
        rsaPrivateKey = try container.decodeIfPresent(String.self, forKey: .rsaPrivateKey)

        // PassVaultItem now handles errors gracefully and returns .corrupted for bad items
        items = try container.decode([PassVaultItem].self, forKey: .items)
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
    case cryptoWallet = "crypto_wallet"

    var label: String {
        switch self {
        case .password: "Password"
        case .passkey: "Passkey"
        case .note: "Secure Note"
        case .card: "Card"
        case .bankAccount: "Bank Account"
        case .file: "File"
        case .cryptoWallet: "Crypto Wallet"
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
        case .cryptoWallet: "bitcoinsign.circle"
        }
    }
}

/// Corrupted item data (for items that failed to decode)
struct PassCorruptedItem: Codable, Equatable {
    let id: String
    let rawJson: String
    let error: String

    // Try to extract id from raw JSON, or generate a unique one
    static func from(json: Data, error: Error) -> PassCorruptedItem {
        let rawJson = String(data: json, encoding: .utf8) ?? "{}"

        // Try to extract id from the raw JSON
        var extractedId = UUID().uuidString.lowercased()
        if let dict = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
           let id = dict["id"] as? String {
            extractedId = id
        }

        return PassCorruptedItem(
            id: extractedId,
            rawJson: rawJson,
            error: error.localizedDescription
        )
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
    case cryptoWallet(PassCryptoWalletItem)
    case corrupted(PassCorruptedItem)

    var id: String {
        switch self {
        case .password(let item): item.id
        case .passkey(let item): item.id
        case .note(let item): item.id
        case .card(let item): item.id
        case .bankAccount(let item): item.id
        case .file(let item): item.id
        case .cryptoWallet(let item): item.id
        case .corrupted(let item): item.id
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
        case .cryptoWallet(let item): item.name
        case .corrupted: "⚠️ Corrupted Item"
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
        case .cryptoWallet: .cryptoWallet
        case .corrupted: .password  // Default, won't be used
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
        case .cryptoWallet(let item): item.folderId
        case .corrupted: nil
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
        case .cryptoWallet(let item): item.favorite ?? false
        case .corrupted: false
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
        case .cryptoWallet(let item): item.deletedAt
        case .corrupted: nil
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
        case .cryptoWallet(let item): item.createdAt
        case .corrupted: 0
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
        case .cryptoWallet(let item): item.updatedAt
        case .corrupted: 0
        }
    }

    var isDeleted: Bool {
        deletedAt != nil
    }

    var isCorrupted: Bool {
        if case .corrupted = self { return true }
        return false
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case type, id
        // Fields for type inference when type is missing
        case username, password, urls  // password item
        case number, cvv, cardholderName  // card item
        case bankName, accountNumber  // bank account item
        case content  // note item
        case rpId, credentialId  // passkey item
        case fileName, r2Key  // file item
        case address, seedPhrase  // crypto wallet item
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // Try to decode type, or infer it from fields if missing
        let itemType: PassVaultItemType
        if let type = try? container.decode(PassVaultItemType.self, forKey: .type) {
            itemType = type
        } else {
            // Infer type from present fields
            itemType = Self.inferType(from: container)
        }

        // Try to decode the appropriate item type
        do {
            switch itemType {
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
            case .cryptoWallet:
                self = .cryptoWallet(try PassCryptoWalletItem(from: decoder))
            }
        } catch {
            // If decoding fails, create a corrupted item
            let id = (try? container.decode(String.self, forKey: .id)) ?? UUID().uuidString.lowercased()
            self = .corrupted(PassCorruptedItem(
                id: id,
                rawJson: "Decode failed for type: \(itemType.rawValue)",
                error: error.localizedDescription
            ))
        }
    }

    /// Infer item type from available fields when type field is missing
    private static func inferType(from container: KeyedDecodingContainer<CodingKeys>) -> PassVaultItemType {
        // Check for passkey-specific fields first (most unique)
        if container.contains(.rpId) && container.contains(.credentialId) {
            return .passkey
        }
        // Check for file-specific fields
        if container.contains(.fileName) && container.contains(.r2Key) {
            return .file
        }
        // Check for crypto wallet-specific fields
        if container.contains(.address) && (container.contains(.seedPhrase) || container.contains(.password)) {
            return .cryptoWallet
        }
        // Check for card-specific fields
        if container.contains(.cvv) || (container.contains(.number) && container.contains(.cardholderName)) {
            return .card
        }
        // Check for bank account-specific fields
        if container.contains(.bankName) && container.contains(.accountNumber) {
            return .bankAccount
        }
        // Check for note-specific fields (content without password fields)
        if container.contains(.content) && !container.contains(.password) {
            return .note
        }
        // Default to password (most common type)
        return .password
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case .password(let item): try item.encode(to: encoder)
        case .passkey(let item): try item.encode(to: encoder)
        case .note(let item): try item.encode(to: encoder)
        case .card(let item): try item.encode(to: encoder)
        case .bankAccount(let item): try item.encode(to: encoder)
        case .file(let item): try item.encode(to: encoder)
        case .cryptoWallet(let item): try item.encode(to: encoder)
        case .corrupted(let item): try item.encode(to: encoder)
        }
    }
}

// MARK: - Item Types

/// Base protocol for all items
protocol PassBaseItem: Codable, Identifiable, Equatable {
    var id: String { get }
    var type: PassVaultItemType { get }
    var name: String { get set }
    var folderId: String? { get set }
    var favorite: Bool? { get set }
    var createdAt: Int { get }
    var updatedAt: Int { get set }
    var deletedAt: Int? { get set }
}

/// Password / Login item
struct PassPasswordItem: PassBaseItem {
    let id: String
    let type: PassVaultItemType
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

    enum CodingKeys: String, CodingKey {
        case id, type, name, username, password, urls, notes, totp, folderId, favorite, createdAt, updatedAt, deletedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        type = try container.decodeIfPresent(PassVaultItemType.self, forKey: .type) ?? .password
        name = try container.decode(String.self, forKey: .name)
        username = try container.decode(String.self, forKey: .username)
        password = try container.decode(String.self, forKey: .password)
        urls = try container.decode([String].self, forKey: .urls)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        totp = try container.decodeIfPresent(PassTotpConfig.self, forKey: .totp)
        folderId = try container.decodeIfPresent(String.self, forKey: .folderId)
        favorite = try container.decodeIfPresent(Bool.self, forKey: .favorite)
        createdAt = try container.decode(Int.self, forKey: .createdAt)
        updatedAt = try container.decode(Int.self, forKey: .updatedAt)
        deletedAt = try container.decodeIfPresent(Int.self, forKey: .deletedAt)
    }

    init(id: String, type: PassVaultItemType, name: String, username: String, password: String, urls: [String], notes: String?, totp: PassTotpConfig?, folderId: String?, favorite: Bool?, createdAt: Int, updatedAt: Int, deletedAt: Int? = nil) {
        self.id = id
        self.type = type
        self.name = name
        self.username = username
        self.password = password
        self.urls = urls
        self.notes = notes
        self.totp = totp
        self.folderId = folderId
        self.favorite = favorite
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }

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
            type: .password,
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
    let type: PassVaultItemType
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

    enum CodingKeys: String, CodingKey {
        case id, type, name, rpId, rpName, credentialId, publicKey, privateKey, userHandle, userName, signCount, folderId, favorite, createdAt, updatedAt, deletedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        type = try container.decodeIfPresent(PassVaultItemType.self, forKey: .type) ?? .passkey
        name = try container.decode(String.self, forKey: .name)
        rpId = try container.decode(String.self, forKey: .rpId)
        rpName = try container.decode(String.self, forKey: .rpName)
        credentialId = try container.decode(String.self, forKey: .credentialId)
        publicKey = try container.decode(String.self, forKey: .publicKey)
        privateKey = try container.decode(String.self, forKey: .privateKey)
        userHandle = try container.decode(String.self, forKey: .userHandle)
        userName = try container.decode(String.self, forKey: .userName)
        signCount = try container.decode(Int.self, forKey: .signCount)
        folderId = try container.decodeIfPresent(String.self, forKey: .folderId)
        favorite = try container.decodeIfPresent(Bool.self, forKey: .favorite)
        createdAt = try container.decode(Int.self, forKey: .createdAt)
        updatedAt = try container.decode(Int.self, forKey: .updatedAt)
        deletedAt = try container.decodeIfPresent(Int.self, forKey: .deletedAt)
    }
}

/// Secure Note item
struct PassNoteItem: PassBaseItem {
    let id: String
    let type: PassVaultItemType
    var name: String
    var content: String
    var folderId: String?
    var favorite: Bool?
    var createdAt: Int
    var updatedAt: Int
    var deletedAt: Int?

    enum CodingKeys: String, CodingKey {
        case id, type, name, content, folderId, favorite, createdAt, updatedAt, deletedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        type = try container.decodeIfPresent(PassVaultItemType.self, forKey: .type) ?? .note
        name = try container.decode(String.self, forKey: .name)
        content = try container.decode(String.self, forKey: .content)
        folderId = try container.decodeIfPresent(String.self, forKey: .folderId)
        favorite = try container.decodeIfPresent(Bool.self, forKey: .favorite)
        createdAt = try container.decode(Int.self, forKey: .createdAt)
        updatedAt = try container.decode(Int.self, forKey: .updatedAt)
        deletedAt = try container.decodeIfPresent(Int.self, forKey: .deletedAt)
    }

    init(id: String, type: PassVaultItemType, name: String, content: String, folderId: String?, favorite: Bool?, createdAt: Int, updatedAt: Int, deletedAt: Int? = nil) {
        self.id = id
        self.type = type
        self.name = name
        self.content = content
        self.folderId = folderId
        self.favorite = favorite
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }

    static func create(name: String, content: String = "", folderId: String? = nil) -> PassNoteItem {
        let now = Int(Date().timeIntervalSince1970 * 1000)
        return PassNoteItem(
            id: UUID().uuidString.lowercased(),
            type: .note,
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
    let type: PassVaultItemType
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

    enum CodingKeys: String, CodingKey {
        case id, type, name, cardholderName, number, expMonth, expYear, cvv, brand, notes, folderId, favorite, createdAt, updatedAt, deletedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        type = try container.decodeIfPresent(PassVaultItemType.self, forKey: .type) ?? .card
        name = try container.decode(String.self, forKey: .name)
        cardholderName = try container.decode(String.self, forKey: .cardholderName)
        number = try container.decode(String.self, forKey: .number)
        expMonth = try container.decode(String.self, forKey: .expMonth)
        expYear = try container.decode(String.self, forKey: .expYear)
        cvv = try container.decode(String.self, forKey: .cvv)
        brand = try container.decodeIfPresent(String.self, forKey: .brand)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        folderId = try container.decodeIfPresent(String.self, forKey: .folderId)
        favorite = try container.decodeIfPresent(Bool.self, forKey: .favorite)
        createdAt = try container.decode(Int.self, forKey: .createdAt)
        updatedAt = try container.decode(Int.self, forKey: .updatedAt)
        deletedAt = try container.decodeIfPresent(Int.self, forKey: .deletedAt)
    }

    init(id: String, type: PassVaultItemType, name: String, cardholderName: String, number: String, expMonth: String, expYear: String, cvv: String, brand: String?, notes: String?, folderId: String?, favorite: Bool?, createdAt: Int, updatedAt: Int, deletedAt: Int? = nil) {
        self.id = id
        self.type = type
        self.name = name
        self.cardholderName = cardholderName
        self.number = number
        self.expMonth = expMonth
        self.expYear = expYear
        self.cvv = cvv
        self.brand = brand
        self.notes = notes
        self.folderId = folderId
        self.favorite = favorite
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }

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
            type: .card,
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
    let type: PassVaultItemType
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

    enum PassBankAccountType: String, Codable {
        case checking
        case savings
        case other
    }

    enum CodingKeys: String, CodingKey {
        case id, type, name, bankName, accountType, accountNumber, routingNumber, iban, swiftBic, notes, folderId, favorite, createdAt, updatedAt, deletedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        type = try container.decodeIfPresent(PassVaultItemType.self, forKey: .type) ?? .bankAccount
        name = try container.decode(String.self, forKey: .name)
        bankName = try container.decode(String.self, forKey: .bankName)
        accountType = try container.decode(PassBankAccountType.self, forKey: .accountType)
        accountNumber = try container.decode(String.self, forKey: .accountNumber)
        routingNumber = try container.decodeIfPresent(String.self, forKey: .routingNumber)
        iban = try container.decodeIfPresent(String.self, forKey: .iban)
        swiftBic = try container.decodeIfPresent(String.self, forKey: .swiftBic)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        folderId = try container.decodeIfPresent(String.self, forKey: .folderId)
        favorite = try container.decodeIfPresent(Bool.self, forKey: .favorite)
        createdAt = try container.decode(Int.self, forKey: .createdAt)
        updatedAt = try container.decode(Int.self, forKey: .updatedAt)
        deletedAt = try container.decodeIfPresent(Int.self, forKey: .deletedAt)
    }

    init(id: String, type: PassVaultItemType, name: String, bankName: String, accountType: PassBankAccountType, accountNumber: String, routingNumber: String?, iban: String?, swiftBic: String?, notes: String?, folderId: String?, favorite: Bool?, createdAt: Int, updatedAt: Int, deletedAt: Int? = nil) {
        self.id = id
        self.type = type
        self.name = name
        self.bankName = bankName
        self.accountType = accountType
        self.accountNumber = accountNumber
        self.routingNumber = routingNumber
        self.iban = iban
        self.swiftBic = swiftBic
        self.notes = notes
        self.folderId = folderId
        self.favorite = favorite
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }
}

/// Encrypted File item (metadata only, file stored in R2)
struct PassFileItem: PassBaseItem {
    let id: String
    let type: PassVaultItemType
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

    enum CodingKeys: String, CodingKey {
        case id, type, name, fileName, fileSize, mimeType, r2Key, encryptionIv, notes, folderId, favorite, createdAt, updatedAt, deletedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        type = try container.decodeIfPresent(PassVaultItemType.self, forKey: .type) ?? .file
        name = try container.decode(String.self, forKey: .name)
        fileName = try container.decode(String.self, forKey: .fileName)
        fileSize = try container.decode(Int.self, forKey: .fileSize)
        mimeType = try container.decode(String.self, forKey: .mimeType)
        r2Key = try container.decode(String.self, forKey: .r2Key)
        encryptionIv = try container.decode(String.self, forKey: .encryptionIv)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        folderId = try container.decodeIfPresent(String.self, forKey: .folderId)
        favorite = try container.decodeIfPresent(Bool.self, forKey: .favorite)
        createdAt = try container.decode(Int.self, forKey: .createdAt)
        updatedAt = try container.decode(Int.self, forKey: .updatedAt)
        deletedAt = try container.decodeIfPresent(Int.self, forKey: .deletedAt)
    }
}

/// Crypto Wallet item
struct PassCryptoWalletItem: PassBaseItem {
    let id: String
    let type: PassVaultItemType
    var name: String
    var address: String
    var seedPhrase: String?
    var privateKey: String?
    var publicKey: String?
    var derivationPath: String?
    var notes: String?
    var folderId: String?
    var favorite: Bool?
    var createdAt: Int
    var updatedAt: Int
    var deletedAt: Int?

    enum CodingKeys: String, CodingKey {
        case id, type, name, address, seedPhrase, privateKey, publicKey, derivationPath, notes, folderId, favorite, createdAt, updatedAt, deletedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        type = try container.decodeIfPresent(PassVaultItemType.self, forKey: .type) ?? .cryptoWallet
        name = try container.decode(String.self, forKey: .name)
        address = try container.decode(String.self, forKey: .address)
        seedPhrase = try container.decodeIfPresent(String.self, forKey: .seedPhrase)
        privateKey = try container.decodeIfPresent(String.self, forKey: .privateKey)
        publicKey = try container.decodeIfPresent(String.self, forKey: .publicKey)
        derivationPath = try container.decodeIfPresent(String.self, forKey: .derivationPath)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        folderId = try container.decodeIfPresent(String.self, forKey: .folderId)
        favorite = try container.decodeIfPresent(Bool.self, forKey: .favorite)
        createdAt = try container.decode(Int.self, forKey: .createdAt)
        updatedAt = try container.decode(Int.self, forKey: .updatedAt)
        deletedAt = try container.decodeIfPresent(Int.self, forKey: .deletedAt)
    }

    init(id: String, type: PassVaultItemType, name: String, address: String, seedPhrase: String?, privateKey: String?, publicKey: String?, derivationPath: String?, notes: String?, folderId: String?, favorite: Bool?, createdAt: Int, updatedAt: Int, deletedAt: Int? = nil) {
        self.id = id
        self.type = type
        self.name = name
        self.address = address
        self.seedPhrase = seedPhrase
        self.privateKey = privateKey
        self.publicKey = publicKey
        self.derivationPath = derivationPath
        self.notes = notes
        self.folderId = folderId
        self.favorite = favorite
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }

    static func create(
        name: String,
        address: String,
        seedPhrase: String? = nil,
        privateKey: String? = nil,
        publicKey: String? = nil,
        derivationPath: String? = "m/44'/60'/0'/0/0",
        notes: String? = nil,
        folderId: String? = nil
    ) -> PassCryptoWalletItem {
        let now = Int(Date().timeIntervalSince1970 * 1000)
        return PassCryptoWalletItem(
            id: UUID().uuidString.lowercased(),
            type: .cryptoWallet,
            name: name,
            address: address,
            seedPhrase: seedPhrase,
            privateKey: privateKey,
            publicKey: publicKey,
            derivationPath: derivationPath,
            notes: notes,
            folderId: folderId,
            favorite: false,
            createdAt: now,
            updatedAt: now
        )
    }
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
