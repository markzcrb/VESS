import SwiftUI

/// A number with its unit or context set beside it on the same baseline,
/// such as "1,840 of 2,400 kcal" or "1.4 L".
struct VESSMetric: View {
    let value: Text
    var context: Text?
    var style: VESSTextStyle = .metricHero

    var body: some View {
        // Context sits beside the number when it fits on one line, otherwise
        // directly below it (large text sizes).
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: VESSSpacing.xs) {
                valueText
                contextText?.fixedSize()
            }
            VStack(alignment: .leading, spacing: 0) {
                valueText
                contextText
            }
        }
    }

    private var valueText: some View {
        value
            .vessTextStyle(style)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }

    private var contextText: (some View)? {
        // Beside a hero number the context steps up to body size,
        // so the target reads as part of the figure, not a footnote.
        context.map {
            $0.font(style == .metricHero || style == .metricLarge ? .body : .subheadline)
                .foregroundStyle(VESSColor.secondaryText)
        }
    }
}

/// A small dot plus label, as used at the top of metric cards ("● Calories").
struct VESSDotLabel: View {
    let title: LocalizedStringKey
    let tint: Color

    var body: some View {
        HStack(spacing: VESSSpacing.xs - 2) {
            Circle()
                .fill(tint)
                .frame(width: 6, height: 6)
                .accessibilityHidden(true)
            Text(title)
                .vessTextStyle(.label)
        }
    }
}

/// A small tracked-caps tag, such as "Recorded", "Entered", "Use by Thu" or
/// "New". The text always carries the meaning; tint is secondary.
struct VESSTag: View {
    enum Tone {
        case neutral
        case positive
        case warning
        case accent
    }

    let text: Text
    var tone: Tone = .neutral

    var body: some View {
        text
            .vessTextStyle(.labelCapsS)
            .foregroundStyle(foreground)
            .padding(.horizontal, VESSSpacing.xs - 1)
            .padding(.vertical, VESSSpacing.xxs)
            .background(background, in: RoundedRectangle(cornerRadius: VESSRadius.tag, style: .continuous))
    }

    private var foreground: Color {
        switch tone {
        case .neutral: VESSColor.secondaryText
        case .positive: VESSColor.statusOptimal
        case .warning: VESSColor.statusPoor
        case .accent: VESSColor.accent
        }
    }

    private var background: Color {
        switch tone {
        case .neutral: VESSColor.fill
        case .positive: VESSColor.tintOptimal
        case .warning: VESSColor.tintPoor
        case .accent: VESSColor.tintLink
        }
    }
}
