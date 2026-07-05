//
//  RootPilotSnapshotTests.swift
//  GrooTests
//
//  Phase 7 pilot: proves the record→assert snapshot workflow end-to-end on
//  the three dependency-free views (Drive placeholder + two root views)
//  before the per-feature fan-out. Pure fixtures — no umbrella needed.
//

import SnapshotTesting
import SwiftUI
import Testing
@testable import Groo

@MainActor
@Suite(.snapshots(record: .missing))
struct RootPilotSnapshotTests {
    @Test func drivePlaceholder() {
        assertViewSnapshot(of: DrivePlaceholderView(), named: "default")
    }

    @Test func drivePlaceholderDark() {
        assertViewSnapshot(of: DrivePlaceholderView(), named: "dark", appearance: .dark)
    }

    @Test func sparklineVariants() {
        let up: [Double] = [1, 2, 1.5, 3, 2.5, 4]
        let down: [Double] = [4, 3.5, 3, 2, 2.5, 1]
        assertViewSnapshot(
            of: SparklineView(data: up, color: .green).frame(width: 120, height: 40).padding(),
            named: "up", size: CGSize(width: 160, height: 80))
        assertViewSnapshot(
            of: SparklineView(data: down, color: .red).frame(width: 120, height: 40).padding(),
            named: "down", size: CGSize(width: 160, height: 80))
        assertViewSnapshot(
            of: SparklineView(data: [], color: .green).frame(width: 120, height: 40).padding(),
            named: "empty", size: CGSize(width: 160, height: 80))
    }

    @Test func customizeTabs() {
        assertViewSnapshot(of: NavigationStack { CustomizeTabsView() }, named: "default")
    }
}
