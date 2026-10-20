import SwiftUI

/// VESS type scale, built on SF Pro and Dynamic Type so every style scales
/// with the user's preferred size, including accessibility sizes.
///
/// The editorial feel comes from hierarchy and restraint: one regular-weight
/// Day Word, large light numerals, and quiet secondary text.
enum VESSTextStyle {
    /// The Day Word, such as "On track". Also onboarding questions.
    case dayWord
    /// Today's headline: the Day Word set larger than any other text, so
    /// the screen reads statement first, numbers second.
    case heroTitle
    /// Detail and sheet titles, such as a food name.
    case detailTitle
    /// Section headings, such as "Meals".
    case sectionTitle
    /// Emphasized row titles, such as "Breakfast".
    case rowTitle
    /// Default reading text.
    case body
    /// Supporting text.
    case secondary
    /// Small labels: card labels, dates, group headers.
    case label
    /// Badge text inside a tinted capsule.
    case badge
    /// The most important number on a screen, such as calories eaten.
    case metricHero
    /// A day's main total on secondary screens, such as Nutrition's calories.
    case metricLarge
    /// Card-level numbers, such as "1.4 L".
    case metric
    /// Inline numbers, such as "108 / 140 g".
    case metricInline
}

extension View {
    /// Applies a VESS text style: font, default color and digit spacing.
    func vessTextStyle(_ style: VESSTextStyle) -> some View {
        modifier(VESSTextStyleModifier(style: style))
    }
}

private struct VESSTextStyleModifier: ViewModifier {
    let style: VESSTextStyle

    /// `Font.system(size:)` does not scale on its own, so the hero metric is
    /// scaled relative to `.largeTitle`.
    @ScaledMetric(relativeTo: .largeTitle) private var metricHeroSize: CGFloat = 64
    @ScaledMetric(relativeTo: .largeTitle) private var metricLargeSize: CGFloat = 40
    @ScaledMetric(relativeTo: .largeTitle) private var heroTitleSize: CGFloat = 40

    func body(content: Content) -> some View {
        content
            .font(font)
            .tracking(style == .heroTitle ? -0.5 : 0)
            .foregroundStyle(color)
    }

    private var font: Font {
        switch style {
        case .dayWord: .largeTitle
        case .heroTitle: .system(size: heroTitleSize, weight: .regular)
        case .detailTitle: .title2.weight(.semibold)
        case .sectionTitle: .headline
        case .rowTitle: .body.weight(.semibold)
        case .body: .body
        case .secondary: .subheadline
        case .label: .footnote
        case .badge: .caption.weight(.semibold)
        case .metricHero: .system(size: metricHeroSize, weight: .light).monospacedDigit()
        case .metricLarge: .system(size: metricLargeSize, weight: .light).monospacedDigit()
        case .metric: .title.monospacedDigit()
        case .metricInline: .callout.monospacedDigit()
        }
    }

    private var color: Color {
        switch style {
        case .secondary, .label: VESSColor.secondaryText
        default: VESSColor.text
        }
    }
}
