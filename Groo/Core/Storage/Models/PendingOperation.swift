//
//  PendingOperation.swift
//  Groo
//
//  SwiftData model for queued operations when offline.
//  Operations are processed when connectivity is restored.
//

import Foundation
import SwiftData

enum OperationType: String, Codable {
    case create
    case delete
}

@Model
final class PendingOperation {
    @Attribute(.unique) var id: String
    var type: String  // "create" or "delete"
    var itemId: String
    var createdAt: Date

    // For create operations, store the encrypted payload as JSON
    var payloadJSON: Data?

    init(type: OperationType, itemId: String, payload: Data? = nil) {
        self.id = UUID().uuidString
        self.type = type.rawValue
        self.itemId = itemId
        self.createdAt = Date()
        self.payloadJSON = payload
    }

    var operationType: OperationType {
        OperationType(rawValue: type) ?? .create
    }
}

// MARK: - Create Payload

struct CreateItemPayload: Codable {
    let item: PadListItem
}

extension PendingOperation {
    /// Create a pending create operation
    static func createItem(_ item: PadListItem) -> PendingOperation {
        let payload = CreateItemPayload(item: item)
        let payloadData = try? JSONEncoder().encode(payload)
        return PendingOperation(type: .create, itemId: item.id, payload: payloadData)
    }

    /// Create a pending delete operation
    static func deleteItem(id: String) -> PendingOperation {
        PendingOperation(type: .delete, itemId: id)
    }

    /// Get the create payload if this is a create operation
    func getCreatePayload() -> PadListItem? {
        guard operationType == .create, let data = payloadJSON else { return nil }
        return try? JSONDecoder().decode(CreateItemPayload.self, from: data).item
    }
}
