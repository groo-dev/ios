//
//  LocalStockTransaction.swift
//  Groo
//
//  SwiftData model for individual stock transactions (buy/sell).
//

import Foundation
import SwiftData

@Model
final class LocalStockTransaction {
    @Attribute(.unique) var id: String
    var type: String          // "buy" or "sell"
    var shares: Double
    var totalCost: Double     // total amount paid/received
    var date: Date
    var holding: LocalStockHolding?

    init(
        id: String = UUID().uuidString,
        type: String = "buy",
        shares: Double,
        totalCost: Double,
        date: Date = Date(),
        holding: LocalStockHolding? = nil
    ) {
        self.id = id
        self.type = type
        self.shares = shares
        self.totalCost = totalCost
        self.date = date
        self.holding = holding
    }
}
