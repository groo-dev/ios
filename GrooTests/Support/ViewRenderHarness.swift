//
//  ViewRenderHarness.swift
//  GrooTests
//
//  Phase 7 render/snapshot harness. Hosts any SwiftUI view in a
//  UIHostingController inside a fixed-size key window (iPhone 17 Pro logical
//  size), forces a synchronous main-actor layout pass, and draws the
//  hierarchy to a UIImage at scale 1. Determinism: en_US locale forced,
//  animations disabled, light appearance unless a test opts into dark.
//  Snapshot wrapper uses perceptualPrecision 0.98 (absorbs GPU antialiasing
//  noise, catches layout/content drift). Views whose pixels depend on
//  wall-clock now (countdowns, TOTP codes, spinners) use assertRenders —
//  same coverage, no reference image.
//

import SnapshotTesting
import SwiftUI
import Testing
import UIKit

@MainActor
enum ViewRender {
    /// iPhone 17 Pro logical size — the pinned simulator.
    static let deviceSize = CGSize(width: 402, height: 874)

    static func makeWindow(
        hosting view: some View,
        size: CGSize = deviceSize,
        appearance: UIUserInterfaceStyle = .light
    ) -> UIWindow {
        UIView.setAnimationsEnabled(false)
        let host = UIHostingController(rootView: AnyView(
            view
                .environment(\.locale, Locale(identifier: "en_US"))
                .transaction { $0.disablesAnimations = true }
        ))
        let window = UIWindow(frame: CGRect(origin: .zero, size: size))
        window.overrideUserInterfaceStyle = appearance
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.frame = window.bounds
        window.layoutIfNeeded()
        return window
    }

    /// Locates the UINavigationController a SwiftUI `NavigationStack` creates
    /// internally, so a test can assert real UIKit navigation-bar state
    /// (`isNavigationBarHidden`) instead of relying on a pixel diff. A
    /// titleless, back-button-less bar renders identically whether shown or
    /// hidden, so a snapshot alone cannot pin that case — this can.
    static func navigationController(hosting view: some View, size: CGSize = deviceSize) -> UINavigationController? {
        let window = makeWindow(hosting: view, size: size)
        defer { window.isHidden = true; window.rootViewController = nil }
        return findNavigationController(in: window)
    }

    /// Settled variant: a single synchronous frame is not enough to tell
    /// "explicitly hidden" apart from "default, not yet settled" — both
    /// report `isNavigationBarHidden == true` immediately after
    /// `makeWindow`. Yielding first (matching `settledImage`) lets
    /// UIKit's navigation controller finish its own layout pass, so a
    /// screen that never suppressed the bar shows its true (visible)
    /// steady state instead of a coincidentally-hidden transient one.
    static func settledNavigationController(
        hosting view: some View,
        yields: Int = 8,
        size: CGSize = deviceSize
    ) async -> UINavigationController? {
        let window = makeWindow(hosting: view, size: size)
        defer { window.isHidden = true; window.rootViewController = nil }
        for _ in 0..<yields { await Task.yield() }
        window.layoutIfNeeded()
        return findNavigationController(in: window)
    }

    private static func findNavigationController(in window: UIWindow) -> UINavigationController? {
        func find(_ vc: UIViewController) -> UINavigationController? {
            if let nav = vc as? UINavigationController { return nav }
            for child in vc.children {
                if let found = find(child) { return found }
            }
            return nil
        }
        guard let root = window.rootViewController else { return nil }
        return find(root)
    }

    static func draw(_ window: UIWindow) -> UIImage {
        // NB: window.drawHierarchy(afterScreenUpdates:) only captures real
        // pixels for a window the window server actually composites — an
        // ad-hoc UIWindow() with no attached UIWindowScene is never
        // composited (this app declares a scene manifest), so that call
        // produced a byte-identical blank image for every view. Render the
        // hosting controller's CALayer directly instead (the same fallback
        // pointfreeco/swift-snapshot-testing itself uses when not drawing
        // from a real key window) — this needs no window-scene attachment.
        let view = window.rootViewController?.view ?? window
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1   // committed references stay small; layout drift is still pixel-visible
        let image = UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { ctx in
            view.layer.render(in: ctx.cgContext)
        }
        window.isHidden = true
        window.rootViewController = nil
        return image
    }

    /// Host + layout + draw in one main-actor turn (async .task bodies have
    /// NOT run yet — the image shows the view's initial state).
    static func image(
        of view: some View,
        size: CGSize = deviceSize,
        appearance: UIUserInterfaceStyle = .light
    ) -> UIImage {
        draw(makeWindow(hosting: view, size: size, appearance: appearance))
    }

    /// Like image(of:), but yields the main actor a few times first so a
    /// synchronous-on-main .task / onAppear state population (in-memory work
    /// only — NEVER network) completes before drawing. Cooperative
    /// scheduling, not time: no sleeps.
    static func settledImage(
        of view: some View,
        yields: Int = 8,
        size: CGSize = deviceSize,
        appearance: UIUserInterfaceStyle = .light
    ) async -> UIImage {
        let window = makeWindow(hosting: view, size: size, appearance: appearance)
        for _ in 0..<yields { await Task.yield() }
        window.layoutIfNeeded()
        return draw(window)
    }

    /// Render-only assertion: hosting + layout + draw must not crash and must
    /// produce a non-empty bitmap. Used for views whose pixels are
    /// time-varying (a snapshot would be byte-unstable — a spec defect).
    static func assertRenders(
        _ view: some View,
        size: CGSize = deviceSize,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        let image = image(of: view, size: size)
        #expect(image.size.width > 0 && image.size.height > 0,
                "view produced an empty render", sourceLocation: sourceLocation)
    }

    /// Async twin of assertRenders for settled renders.
    static func assertSettledRenders(
        _ view: some View,
        yields: Int = 8,
        size: CGSize = deviceSize,
        sourceLocation: SourceLocation = #_sourceLocation
    ) async {
        let image = await settledImage(of: view, yields: yields, size: size)
        #expect(image.size.width > 0 && image.size.height > 0,
                "view produced an empty render", sourceLocation: sourceLocation)
    }
}

/// Snapshot a view at device size. named: distinguishes fixture states
/// within one test ("locked", "populated", "dark", …).
@MainActor
func assertViewSnapshot(
    of view: some View,
    named name: String,
    size: CGSize = ViewRender.deviceSize,
    appearance: UIUserInterfaceStyle = .light,
    fileID: StaticString = #fileID,
    filePath: StaticString = #filePath,
    testName: String = #function,
    line: UInt = #line,
    column: UInt = #column
) {
    assertSnapshot(
        of: ViewRender.image(of: view, size: size, appearance: appearance),
        as: .image(perceptualPrecision: 0.98),
        named: name,
        fileID: fileID,
        file: filePath,
        testName: testName,
        line: line,
        column: column
    )
}

/// Settled variant (see ViewRender.settledImage).
@MainActor
func assertSettledViewSnapshot(
    of view: some View,
    named name: String,
    yields: Int = 8,
    size: CGSize = ViewRender.deviceSize,
    appearance: UIUserInterfaceStyle = .light,
    fileID: StaticString = #fileID,
    filePath: StaticString = #filePath,
    testName: String = #function,
    line: UInt = #line,
    column: UInt = #column
) async {
    // assertSnapshot's `of:` parameter is a non-async @autoclosure — an
    // `await` cannot be inlined into it. Resolve the image first, then hand
    // the already-computed value through.
    let image = await ViewRender.settledImage(of: view, yields: yields, size: size, appearance: appearance)
    assertSnapshot(
        of: image,
        as: .image(perceptualPrecision: 0.98),
        named: name,
        fileID: fileID,
        file: filePath,
        testName: testName,
        line: line,
        column: column
    )
}

/// Pin UserDefaults.standard keys for the duration of body, restoring the
/// previous values (or absence) afterwards. Callers MUST sit under the
/// NetworkStubbedSuites serialized umbrella (standard defaults are
/// process-global shared state).
@MainActor
func withPinnedDefaults<T>(_ values: [String: Any], _ body: () throws -> T) rethrows -> T {
    let defaults = UserDefaults.standard
    var previous: [String: Any?] = [:]
    for (key, value) in values {
        previous[key] = defaults.object(forKey: key)
        defaults.set(value, forKey: key)
    }
    defer {
        for (key, old) in previous {
            if let old { defaults.set(old, forKey: key) } else { defaults.removeObject(forKey: key) }
        }
    }
    return try body()
}

/// Async twin for bodies that await (settled snapshots).
@MainActor
func withPinnedDefaults<T>(_ values: [String: Any], _ body: () async throws -> T) async rethrows -> T {
    let defaults = UserDefaults.standard
    var previous: [String: Any?] = [:]
    for (key, value) in values {
        previous[key] = defaults.object(forKey: key)
        defaults.set(value, forKey: key)
    }
    defer {
        for (key, old) in previous {
            if let old { defaults.set(old, forKey: key) } else { defaults.removeObject(forKey: key) }
        }
    }
    return try await body()
}
