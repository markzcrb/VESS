import SwiftUI

// MARK: - H04 BMI

/// "23.7 · 78.4 kg · 182 cm", the WHO range scale with a marker, and the
/// honest note. Shown to adults only, never during pregnancy.
struct BodyMassIndexSection: View {
    let bmi: Double
    let weight: Double
    let height: Double

    var body: some View {
        let value = bmi.formatted(.number.precision(.fractionLength(1)))

        VStack(alignment: .leading, spacing: VESSSpacing.xl) {
            VStack(alignment: .leading, spacing: VESSSpacing.xs) {
                Text("Body mass index")
                    .vessTextStyle(.labelCaps)
                    .foregroundStyle(VESSColor.secondaryText)
                    .accessibilityAddTraits(.isHeader)
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: VESSSpacing.md) {
                        number(value)
                        measures
                    }
                    VStack(alignment: .leading, spacing: VESSSpacing.xxs) {
                        number(value)
                        measures
                    }
                }
            }
            .accessibilityElement(children: .combine)

            BodyMassIndexScale(bmi: bmi)

            Text("\(Text(Self.rangeText(BodyRules.Range(bmi)))) BMI is a rough guide: it doesn't tell muscle from fat, so read it next to your weight trend and how you feel.")
                .vessTextStyle(.bodyM)
                .foregroundStyle(VESSColor.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func number(_ value: String) -> some View {
        Text(verbatim: value)
            .vessTextStyle(.displayL)
            .foregroundStyle(VESSColor.text)
    }

    private var measures: some View {
        Text("\(VESSFormat.quantity(weight))\u{00A0}kg · \(VESSFormat.quantity(height))\u{00A0}cm")
            .vessTextStyle(.bodyM)
            .foregroundStyle(VESSColor.secondaryText)
    }

    private static func rangeText(_ range: BodyRules.Range) -> LocalizedStringResource {
        let low = 18.5.formatted(.number.precision(.fractionLength(1)))
        switch range {
        case .below18_5: return "Below \(low) for your height."
        case .from18_5to25: return "In the \(low)\u{2013}25 range for your height."
        case .from25to30: return "In the 25\u{2013}30 range for your height."
        case .from30: return "Above 30 for your height."
        }
    }
}

/// Four WHO ranges from 15 to 35, with a marker at the user's BMI. Calm
/// colours: the range around 18.5–25 in the positive hue, above it amber,
/// never red. Decorative for VoiceOver; the text states the range.
struct BodyMassIndexScale: View {
    let bmi: Double

    private static let bounds: ClosedRange<Double> = 15...35
    private static let segments: [ClosedRange<Double>] = [15...18.5, 18.5...25, 25...30, 30...35]

    var body: some View {
        VStack(spacing: VESSSpacing.xs) {
            GeometryReader { proxy in
                let width = proxy.size.width
                let span = Self.bounds.upperBound - Self.bounds.lowerBound
                ZStack(alignment: .leading) {
                    HStack(spacing: VESSSpacing.xxs) {
                        ForEach(Self.segments.indices, id: \.self) { index in
                            let range = Self.segments[index]
                            Capsule()
                                .fill(fill(index))
                                .frame(width: max(width * (range.upperBound - range.lowerBound) / span - VESSSpacing.xxs, 0))
                        }
                    }
                    .frame(height: VESSSpacing.xs)
                    Circle()
                        .fill(VESSColor.text)
                        .overlay(Circle().strokeBorder(VESSColor.background, lineWidth: 2))
                        .frame(width: VESSSpacing.md + 2, height: VESSSpacing.md + 2)
                        .position(x: width * (min(max(bmi, Self.bounds.lowerBound), Self.bounds.upperBound) - Self.bounds.lowerBound) / span,
                                  y: proxy.size.height / 2)
                }
            }
            .frame(height: VESSSpacing.md + 2)

            GeometryReader { proxy in
                let span = Self.bounds.upperBound - Self.bounds.lowerBound
                ForEach([18.5, 25, 30], id: \.self) { mark in
                    Text(verbatim: mark.formatted(.number.precision(.fractionLength(0...1))))
                        .vessTextStyle(.labelCapsS)
                        .foregroundStyle(VESSColor.tertiaryText)
                        .fixedSize()
                        .position(x: proxy.size.width * (mark - Self.bounds.lowerBound) / span, y: proxy.size.height / 2)
                }
            }
            .frame(height: VESSSpacing.md)
        }
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .accessibilityHidden(true)
    }

    private func fill(_ index: Int) -> Color {
        switch index {
        case 0: VESSColor.chartMuted
        case 1: VESSColor.statusOptimal
        case 2: VESSColor.warning.opacity(0.6)
        default: VESSColor.warning.opacity(0.4)
        }
    }
}

/// BMI over 12 weeks as one line, with the first and last value and date.
struct BodyTrendLine: View {
    let points: [TimedValue]

    @ScaledMetric(relativeTo: .body) private var height: CGFloat = 64

    var body: some View {
        let values = points.map(\.value)
        let low = (values.min() ?? 0) - 0.5
        let high = (values.max() ?? 1) + 0.5

        VStack(spacing: VESSSpacing.xs) {
            line(values, low: low, high: high)
            if let first = points.first, let last = points.last {
                HStack {
                    label(first)
                    Spacer()
                    label(last)
                }
                .vessTextStyle(.caption)
                .foregroundStyle(VESSColor.tertiaryText)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("BMI over 12 weeks"))
        .accessibilityValue(accessibilityValue)
    }

    private func label(_ point: TimedValue) -> Text {
        Text("\(Self.format(point.value)) · \(point.date, format: .dateTime.day().month(.abbreviated))")
    }

    private var accessibilityValue: Text {
        guard let first = points.first, let last = points.last else { return Text(verbatim: "") }
        return Text("From \(Self.format(first.value)) to \(Self.format(last.value))")
    }

    private static func format(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1)))
    }

    private func line(_ values: [Double], low: Double, high: Double) -> some View {
        GeometryReader { proxy in
            Path { path in
                for (index, value) in values.enumerated() {
                    let point = CGPoint(
                        x: proxy.size.width * CGFloat(index) / CGFloat(max(values.count - 1, 1)),
                        y: proxy.size.height * (1 - (value - low) / (high - low))
                    )
                    if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
                }
            }
            .stroke(VESSColor.text, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        }
        .frame(height: height)
    }
}
