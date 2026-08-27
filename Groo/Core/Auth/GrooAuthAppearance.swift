import GrooAuthUI
import SwiftUI

extension GrooAuthTheme {
    /// Groo's brand, applied to the components from `GrooAuthUI`.
    ///
    /// The library's default palette is its own — deliberately, so an adopter who
    /// configures nothing still gets a screen that looks finished. This is the
    /// other half of that contract: the app states its brand once and the
    /// components follow it.
    ///
    /// Only `accent` is Groo's colour. Everything else maps to the system
    /// semantic colours the rest of this app already uses, so the sign-in screen
    /// is not a differently-shaded island in front of it — and it tracks light
    /// and dark for free, which is the same reason the library's own defaults
    /// are adaptive.
    static let grooApp = GrooAuthTheme(
        accent: Theme.Brand.primary,
        onAccent: .white,
        canvas: Color(.systemBackground),
        surface: Color(.secondarySystemBackground),
        ink: Color(.label),
        muted: Color(.secondaryLabel),
        line: Color(.separator),
        danger: Color(.systemRed),
        cornerRadius: Theme.Radius.md
    )
}
