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
    /// The canvas fade behind the floating tab bar, from the bar's top up.
    static let tabBarFade: CGFloat = 120
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
/// Timings from Redesign/docs/MOTION.md. With Reduce Motion, every one of
/// them becomes an instant change or `reducedCrossfade`.
enum VESSMotion {
    /// Rings sweep from 0, and hero numbers count up with them.
    static let ringSweep = Animation.easeOut(duration: 0.8)
    /// Metric and status rows fade and rise `rowRise`, 40 ms apart.
    static let rowStagger: Double = 0.04
    static let rowAppear = Animation.easeOut(duration: 0.35)
    static let rowRise: CGFloat = 6
    /// Lines draw left to right; bars grow from the baseline, 20 ms apart.
    static let chart = Animation.easeOut(duration: 0.6)
    static let barStagger: Double = 0.02
    /// The insight card's border brightens once, 0.9 s after it appears.
    static let insightBrighten = Animation.easeInOut(duration: 0.6).delay(0.9)
    /// Segmented pills, tabs, chips and switches.
    static let selection = Animation.snappy(duration: 0.25)
    /// The Undo toast after logging.
    static let toast = Animation.spring(response: 0.38, dampingFraction: 0.86)
    /// What replaces movement under Reduce Motion.
    static let reducedCrossfade = Animation.easeInOut(duration: 0.2)
    /// Add sheet (21): content swaps when the carousel settles, sliding
    /// `addSwapOffset` from the swipe side; Reduce Motion crossfades only.
    static let addSwap = Animation.easeOut(duration: 0.28)
    static let addSwapReduced = Animation.easeInOut(duration: 0.15)
    /// The outgoing content of a swap leaves faster than the new one arrives.
    static let addSwapOut = Animation.easeIn(duration: 0.14)
    static let addSwapOffset: CGFloat = 24
    /// A tapped tile springs to the centre.
    static let addTileScroll = Animation.spring(response: 0.35, dampingFraction: 0.85)
    /// The type name under the carousel crossfades to the new name and colour.
    static let addLabel = Animation.easeInOut(duration: 0.2)
}

extension View {
    /// MOTION.md row stagger: fades in and rises 6 pt on first appear, 40 ms
    /// after the row before it. Instant with Reduce Motion.
    func vessRowAppear(index: Int) -> some View {
        modifier(VESSRowAppearModifier(index: index))
    }
}

extension View {
    /// MOTION.md chart bars: grow from the baseline over 0.6 s, 20 ms after
    /// the bar before. Set `isGrown` to true on appear, without animation;
    /// with Reduce Motion the bars appear at full height at once.
    func vessBarGrow(index: Int, isGrown: Bool) -> some View {
        modifier(VESSBarGrowModifier(index: index, isGrown: isGrown))
    }
}

private struct VESSBarGrowModifier: ViewModifier {
    let index: Int
    let isGrown: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.animation(
            reduceMotion ? nil : VESSMotion.chart.delay(Double(index) * VESSMotion.barStagger),
            value: isGrown
        )
    }
}

private struct VESSRowAppearModifier: ViewModifier {
    let index: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown || reduceMotion ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : VESSMotion.rowRise)
            .onAppear {
                guard !shown, !reduceMotion else { return }
                withAnimation(VESSMotion.rowAppear.delay(Double(index) * VESSMotion.rowStagger)) { shown = true }
            }
    }
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
