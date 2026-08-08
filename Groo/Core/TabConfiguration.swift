//
//  TabConfiguration.swift
//  Groo
//
//  The iPhone tab bar's composition: an ordered list of features plus a Home
//  toggle. The first `barSlots` entries render as tabs, slot five is More, and
//  everything past the cut falls into More's list.
//
//  The initializer sanitizes, so an invalid configuration is unrepresentable
//  and no consumer needs to defend against one. Home is pinned first (or
//  absent) and is never a member of `order`; Settings is not part of this
//  model at all — it is always the last row of More.
//

import Foundation

struct TabConfiguration: Equatable, Codable, Sendable {
    /// Tab-bar slots available to features. The fifth slot is always More.
    static let barSlots = 4

    /// Features the user can drag, in their default order.
    static let reorderable: [TabID] = [.azan, .pass, .pad, .stocks, .crypto, .drive, .scratchpad]

    static let `default` = TabConfiguration(order: reorderable, showsHome: true)

    private(set) var order: [TabID]
    private(set) var showsHome: Bool

    init(order: [TabID], showsHome: Bool) {
        var seen = Set<TabID>()
        // Keep only draggable features, first occurrence wins…
        var sanitized = order.filter { Self.reorderable.contains($0) && seen.insert($0).inserted }
        // …then refill anything absent, in default order.
        sanitized += Self.reorderable.filter { !seen.contains($0) }
        self.order = sanitized
        self.showsHome = showsHome
    }

    /// Every feature the user can reach through the bar or More, in order.
    var allTabs: [TabID] {
        showsHome ? [.home] + order : order
    }

    /// The features rendered as tab-bar items.
    var barTabs: [TabID] {
        Array(allTabs.prefix(Self.barSlots))
    }

    /// The features that fall past the cut into More. Settings is appended by
    /// the More screen itself and is deliberately not part of this list.
    var moreTabs: [TabID] {
        Array(allTabs.dropFirst(Self.barSlots))
    }

    mutating func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        // Array.move(fromOffsets:toOffset:) is a SwiftUI extension, and this
        // is a plain data model — reproduce its semantics with Foundation
        // only: lift the moved elements out, then reinsert them at the
        // destination adjusted for whatever shifted left of it.
        var next = order
        let itemsToMove = source.map { next[$0] }
        for offset in source.sorted(by: >) {
            next.remove(at: offset)
        }
        let adjustedDestination = destination - source.filter { $0 < destination }.count
        next.insert(contentsOf: itemsToMove, at: adjustedDestination)
        self = TabConfiguration(order: next, showsHome: showsHome)
    }

    mutating func setShowsHome(_ value: Bool) {
        self = TabConfiguration(order: order, showsHome: value)
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey { case order, showsHome }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let raw = (try? container.decode([String].self, forKey: .order)) ?? []
        let showsHome = (try? container.decode(Bool.self, forKey: .showsHome)) ?? true
        self.init(order: raw.compactMap(TabID.init(rawValue:)), showsHome: showsHome)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(order.map(\.rawValue), forKey: .order)
        try container.encode(showsHome, forKey: .showsHome)
    }
}
