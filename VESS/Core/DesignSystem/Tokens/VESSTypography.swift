import SwiftUI

/// VESS type scale. SF Pro everywhere, monospaced digits for numbers, and the
/// system serif (New York) for editorial lines, at most one per screen.
///
/// Every style scales with Dynamic Type relative to a system text style, up
/// to AX5. Tracking is a percentage of the font size, as in the design.
enum VESSTextStyle: CaseIterable {
    // MARK: Redesign scale

    /// Hero ring value, such as "78".
    case displayHero
    /// Large values, such as "312" on Food detail.
    case displayL
    /// Medium values, such as "1,840" on Today's intake.
    case displayM
    /// Greetings and sheet titles, such as "Good evening, Mark".
    case titleL
    /// Values in metric rows, such as "108 g".
    case numberRow
    /// Small values, such as "620" kcal or strip ring values.
    case numberS
    case bodyM
    case bodyMStrong
    case bodyS
    case caption
    /// Tracked caps labels, such as "ENERGY".
    case labelCaps
    case labelCapsS
    /// Tracked caps link, such as "BREAK DOWN MY DAY".
    case labelCapsLink
    /// The screen's one editorial line, such as "A steady day.".
    case editorialL
    case editorialM

    // MARK: Legacy names
    // Mapped onto the scale above until each screen is migrated.

    case dayWord, heroTitle, detailTitle, sectionTitle, rowTitle, body
    case secondary, label, badge, metricHero, metricLarge, metric, metricInline

    struct Spec {
        let size: CGFloat
        let weight: Font.Weight
        let trackingPercent: CGFloat
        /// Line height in points at the base size; `nil` uses the default.
        let lineHeight: CGFloat?
        let relativeTo: Font.TextStyle
        var serif = false
        var uppercase = false
        var numeric = false
    }

    var spec: Spec {
        switch self {
        case .displayHero: Spec(size: 76, weight: .bold, trackingPercent: -3, lineHeight: nil, relativeTo: .largeTitle, numeric: true)
        case .displayL: Spec(size: 48, weight: .bold, trackingPercent: -2, lineHeight: nil, relativeTo: .largeTitle, numeric: true)
        case .displayM: Spec(size: 32, weight: .semibold, trackingPercent: -1.5, lineHeight: nil, relativeTo: .title, numeric: true)
        case .titleL: Spec(size: 22, weight: .semibold, trackingPercent: -0.5, lineHeight: nil, relativeTo: .title2)
        case .numberRow: Spec(size: 19, weight: .semibold, trackingPercent: -0.5, lineHeight: nil, relativeTo: .title3, numeric: true)
        case .numberS: Spec(size: 15, weight: .semibold, trackingPercent: -0.2, lineHeight: nil, relativeTo: .subheadline, numeric: true)
        case .bodyM: Spec(size: 16, weight: .regular, trackingPercent: -0.2, lineHeight: 22, relativeTo: .body)
        case .bodyMStrong: Spec(size: 16, weight: .semibold, trackingPercent: -0.2, lineHeight: 22, relativeTo: .body)
        case .bodyS: Spec(size: 14, weight: .regular, trackingPercent: -0.1, lineHeight: 19, relativeTo: .subheadline)
        case .caption: Spec(size: 12, weight: .regular, trackingPercent: 0, lineHeight: 16, relativeTo: .caption, numeric: true)
        case .labelCaps: Spec(size: 12, weight: .semibold, trackingPercent: 9, lineHeight: nil, relativeTo: .caption, uppercase: true)
        case .labelCapsS: Spec(size: 10.5, weight: .semibold, trackingPercent: 10, lineHeight: nil, relativeTo: .caption2, uppercase: true)
        case .labelCapsLink: Spec(size: 12, weight: .bold, trackingPercent: 10, lineHeight: nil, relativeTo: .caption, uppercase: true)
        case .editorialL: Spec(size: 30, weight: .regular, trackingPercent: -1, lineHeight: 34, relativeTo: .title, serif: true)
        case .editorialM: Spec(size: 24, weight: .regular, trackingPercent: -0.5, lineHeight: 29, relativeTo: .title2, serif: true)

        case .heroTitle, .dayWord: VESSTextStyle.editorialL.spec
        case .detailTitle: VESSTextStyle.titleL.spec
        case .sectionTitle: VESSTextStyle.labelCaps.spec
        case .rowTitle: VESSTextStyle.bodyMStrong.spec
        case .body: VESSTextStyle.bodyM.spec
        case .secondary: VESSTextStyle.bodyS.spec
        case .label: VESSTextStyle.caption.spec
        case .badge: VESSTextStyle.labelCapsS.spec
        case .metricHero: VESSTextStyle.displayL.spec
        case .metricLarge: VESSTextStyle.displayM.spec
        case .metric: VESSTextStyle.numberRow.spec
        case .metricInline: VESSTextStyle.numberS.spec
        }
    }

    /// Default color. `nil` lets the caller's `foregroundStyle` apply.
    var defaultColor: Color? {
        switch self {
        case .secondary, .label, .sectionTitle: VESSColor.secondaryText
        case .dayWord, .heroTitle, .detailTitle, .rowTitle, .body, .badge,
             .metricHero, .metricLarge, .metric, .metricInline: VESSColor.text
        default: nil
        }
    }
}

extension View {
    /// Applies a VESS text style: font, tracking, line height, case and digits.
    ///
    ///     Text("Fuel").vessTextStyle(.labelCaps).foregroundStyle(VESSColor.text)
    func vessTextStyle(_ style: VESSTextStyle) -> some View {
        modifier(VESSTextStyleModifier(style: style))
    }
}

private struct VESSTextStyleModifier: ViewModifier {
    let style: VESSTextStyle
    @ScaledMetric private var size: CGFloat
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(style: VESSTextStyle) {
        self.style = style
        _size = ScaledMetric(wrappedValue: style.spec.size, relativeTo: style.spec.relativeTo)
    }

    func body(content: Content) -> some View {
        let spec = style.spec
        var font = Font.system(size: size, weight: spec.weight, design: spec.serif ? .serif : .default)
        if spec.numeric { font = font.monospacedDigit() }
        // Extra leading beyond the font's natural line height (about 1.19 × size).
        let scale = size / spec.size
        let leading = spec.lineHeight.map { max(0, $0 * scale - size * 1.19) } ?? 0
        // At accessibility sizes tracked caps read as plain sentence case.
        let isCaps = spec.uppercase && !dynamicTypeSize.isAccessibilitySize
        let tracking = spec.uppercase && !isCaps ? 0 : size * spec.trackingPercent / 100

        // The case is applied first so layout measures the uppercase glyphs.
        return content
            .textCase(isCaps ? .uppercase : nil)
            .font(font)
            .tracking(tracking)
            .lineSpacing(leading)
            .modifier(OptionalForeground(color: style.defaultColor))
    }
}

private struct OptionalForeground: ViewModifier {
    let color: Color?

    func body(content: Content) -> some View {
        if let color {
            content.foregroundStyle(color)
        } else {
            content
        }
    }
}
