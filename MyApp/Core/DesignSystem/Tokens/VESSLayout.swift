import SwiftUI

/// Spacing scale. Use these values for all padding and stack spacing.
enum VESSSpacing {
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 8
    static let sm: CGFloat = 12
    static let md: CGFloat = 16
    static let lg: CGFloat = 20
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
    static let xxxl: CGFloat = 40
    static let huge: CGFloat = 48

    /// Horizontal inset for screen content.
    static let screenInset: CGFloat = lg
    /// Vertical gap between top-level sections of a screen.
    static let section: CGFloat = xxxl
}

/// Corner radii. All shapes use the continuous curve.
enum VESSRadius {
    /// Badges and small elements.
    static let small: CGFloat = 8
    /// Row thumbnails.
    static let thumbnail: CGFloat = 12
    /// Buttons, inputs and icon buttons.
    static let control: CGFloat = 16
    /// Cards and grouped rows.
    static let large: CGFloat = 22
}

/// Minimum interactive sizes, per Apple's Human Interface Guidelines.
enum VESSHitTarget {
    static let minimum: CGFloat = 44
    /// Height of full-width buttons and text fields.
    static let control: CGFloat = 52
}

extension View {
    /// Applies the one VESS elevation: a very soft shadow in light mode and
    /// none in dark mode, where surfaces are separated by tone instead.
    func vessElevation() -> some View {
        modifier(VESSElevationModifier())
    }
}

private struct VESSElevationModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content.shadow(
            color: .black.opacity(colorScheme == .dark ? 0 : 0.03),
            radius: 12,
            x: 0,
            y: 4
        )
    }
}
