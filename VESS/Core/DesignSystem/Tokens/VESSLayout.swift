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
    /// Vertical gap between top-level sections of a screen (Today uses 36).
    static let section: CGFloat = xxl
}

/// Corner radii. All shapes use the continuous curve.
enum VESSRadius {
    /// Tags.
    static let tag: CGFloat = 5
    /// Legend chips and small elements.
    static let small: CGFloat = 8
    /// Thumbnails, impact rows, quick-add tiles.
    static let thumbnail: CGFloat = 12
    /// Inputs.
    static let control: CGFloat = 16
    /// Insight cards, featured recipe, embedded cards.
    static let large: CGFloat = 16
    /// Sheet top corners.
    static let sheet: CGFloat = 32
}

/// Fixed component sizes from the design (402 pt wide screen).
enum VESSSize {
    static let heroRing: CGFloat = 248
    static let stripRing: CGFloat = 52
    /// MetricRow and StatusRow.
    static let rowHeight: CGFloat = 56
    static let iconButton: CGFloat = 40
    static let addButton: CGFloat = 62
    static let rowIcon: CGFloat = 20
}

/// Ring geometry. The stroke is 9.5 % of the radius, flat caps, starting at
/// 12 o'clock: 11.8 pt on the 248 pt hero ring.
enum VESSRing {
    static func lineWidth(diameter: CGFloat, innerRadiusRatio: CGFloat = 0.905) -> CGFloat {
        diameter / 2 * (1 - innerRadiusRatio)
    }
}

/// Motion tokens (`Redesign/docs/MOTION.md`). Callers pass `nil` instead
/// when Reduce Motion is on.
enum VESSMotion {
    static let ringSweep = Animation.easeOut(duration: 0.8)
    static let rowStagger: Double = 0.04
    static let rowAppear = Animation.easeOut(duration: 0.35)
    static let chart = Animation.easeOut(duration: 0.6)
    static let selection = Animation.snappy(duration: 0.25)
    static let sheet = Animation.spring(response: 0.38, dampingFraction: 0.86)
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
