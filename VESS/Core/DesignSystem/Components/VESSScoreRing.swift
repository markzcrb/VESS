import SwiftUI

/// A ring: track plus progress arc. Flat caps, starting at 12 o'clock,
/// clockwise. Decorative for VoiceOver; the parent speaks the value.
struct VESSRingShape: View {
    /// Progress toward the target, 0...1. Values above 1 draw a full ring.
    let progress: Double
    let tint: Color
    let lineWidth: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .inset(by: lineWidth / 2)
                .stroke(VESSColor.chartTrack, lineWidth: lineWidth)
            Circle()
                .inset(by: lineWidth / 2)
                .trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
                .rotationEffect(.degrees(-90))
        }
        .accessibilityHidden(true)
    }
}

/// The hero ring, such as Fuel on Today: value, caps label and a caption.
/// The arc sweeps in on first appear (instant with Reduce Motion).
struct VESSScoreRing: View {
    /// "78", "6,420" or "—".
    let value: String
    var unit: String?
    let label: LocalizedStringResource
    var sublabel: Text?
    /// 0...1. Zero shows the empty track.
    let progress: Double
    var metric: VESSMetricKind = .fuel
    var diameter: CGFloat = VESSSize.heroRing
    /// With no value: only "—" inside the ring and this one line under it
    /// ("No sleep recorded last night"). Without it, the label stays inside.
    var emptyCaption: Text?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var shown: Double = 0
    @State private var hasCounted = false

    var body: some View {
        // The ring keeps its size; at accessibility sizes the caption is
        // repeated at full size below it (J04).
        VStack(spacing: VESSSpacing.md) {
            ring
            if isEmptyWithCaption, let emptyCaption {
                emptyCaption
                    .vessTextStyle(.bodyM)
                    .foregroundStyle(VESSColor.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityHidden(true)
            } else if dynamicTypeSize.isAccessibilitySize, let sublabel {
                sublabel
                    .vessTextStyle(.bodyM)
                    .foregroundStyle(VESSColor.secondaryText)
                    .multilineTextAlignment(.center)
                    .accessibilityHidden(true)
            }
        }
        .onAppear { animate(to: progress) }
        .onChange(of: progress) { _, new in animate(to: new) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(label))
        .accessibilityValue(accessibilityValue)
    }

    private var isEmptyWithCaption: Bool { value == Self.empty && emptyCaption != nil }

    private var accessibilityValue: Text {
        if isEmptyWithCaption, let emptyCaption { return emptyCaption }
        // "—" is read as "em dash"; say what it means instead.
        let value = self.value == Self.empty ? Text("No value yet") : Text(verbatim: "\(self.value)\(unit ?? "")")
        guard let sublabel else { return value }
        return Text("\(value), \(sublabel)")
    }

    private var ring: some View {
        ZStack {
            VESSRingShape(progress: shown, tint: metric.tint, lineWidth: VESSRing.lineWidth(diameter: diameter))
            VStack(spacing: VESSSpacing.xxs) {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    if value == Self.empty {
                        // No value yet: a thin en dash, not a heavy bar.
                        Text(verbatim: "\u{2013}")
                            .vessTextStyle(.displayHero)
                            .fontWeight(.ultraLight)
                            .foregroundStyle(VESSColor.secondaryText)
                    } else {
                        // Rolls up from 0 in the sweep's 0.8 s transaction.
                        Text(verbatim: hasCounted || reduceMotion ? value : Self.zero(for: value))
                            .vessTextStyle(value.count > 3 ? .displayL : .displayHero)
                            .contentTransition(.numericText(countsDown: false))
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                    }
                    if let unit {
                        Text(verbatim: unit)
                            .vessTextStyle(.titleL)
                            .foregroundStyle(VESSColor.secondaryText)
                    }
                }
                .foregroundStyle(VESSColor.text)
                if !isEmptyWithCaption {
                    Text(label)
                        .vessTextStyle(.labelCaps)
                        .foregroundStyle(VESSColor.text)
                }
                // At accessibility sizes the caption is shown once, below the ring.
                if let sublabel, !dynamicTypeSize.isAccessibilitySize, !isEmptyWithCaption {
                    sublabel
                        .vessTextStyle(.caption)
                        .foregroundStyle(VESSColor.secondaryText)
                }
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, VESSSpacing.xl)
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        }
        .frame(width: diameter, height: diameter)
    }

    private func animate(to value: Double) {
        withAnimation(reduceMotion ? nil : VESSMotion.ringSweep) {
            shown = value
            hasCounted = true
        }
    }

    /// "0" before the count for whole numbers in this locale's format
    /// ("78", "6,420"); anything else ("—") is shown from the start.
    /// The value before there is one.
    private static let empty = "—"

    private static func zero(for text: String) -> String {
        guard let number = try? Int(text, format: .number), number.formatted() == text else { return text }
        return 0.formatted()
    }
}

/// A small ring with its value inside and a caption below, for Today's
/// metric strip (Fuel · Energy · Protein · Water · Steps).
struct VESSMetricStripItem: View {
    /// "77" or "—".
    let value: String
    let label: LocalizedStringResource
    let progress: Double
    let metric: VESSMetricKind
    /// What VoiceOver reads instead of the bare number, such as
    /// "77 percent of target".
    var spokenValue: Text?

    @ScaledMetric(relativeTo: .body) private var scaledDiameter = VESSSize.stripRing
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var shown: Double = 0

    /// Capped so five rings always fit the width.
    private var diameter: CGFloat { min(scaledDiameter, 64) }
    /// The ring beside "Fuel · 78" at accessibility sizes (J03, J04),
    /// large enough for two digits inside the stroke.
    private static let stackedDiameter: CGFloat = 44

    var body: some View {
        // At accessibility sizes: a small ring beside "Fuel · 78" (J04).
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(HStackLayout(spacing: VESSSpacing.sm))
            : AnyLayout(VStackLayout(spacing: VESSSpacing.xs))

        layout {
            ZStack {
                VESSRingShape(
                    progress: shown,
                    tint: metric.tint,
                    lineWidth: VESSRing.lineWidth(diameter: diameter, innerRadiusRatio: 0.88)
                )
                Text(verbatim: value)
                    .vessTextStyle(.numberS)
                    .foregroundStyle(VESSColor.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.horizontal, VESSSpacing.xxs)
                    .dynamicTypeSize(...DynamicTypeSize.large)
            }
            .frame(width: dynamicTypeSize.isAccessibilitySize ? Self.stackedDiameter : diameter,
                   height: dynamicTypeSize.isAccessibilitySize ? Self.stackedDiameter : diameter)
            if dynamicTypeSize.isAccessibilitySize {
                Text("\(Text(label)) · \(value)")
                    .vessTextStyle(.bodyM)
                    .foregroundStyle(VESSColor.text)
            } else {
                Text(label)
                    .vessTextStyle(.caption)
                    .foregroundStyle(VESSColor.secondaryText)
                    .lineLimit(1)
            }
        }
        .onAppear { withAnimation(reduceMotion ? nil : VESSMotion.ringSweep) { shown = progress } }
        .onChange(of: progress) { _, new in withAnimation(reduceMotion ? nil : VESSMotion.ringSweep) { shown = new } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(label))
        .accessibilityValue(spokenValue ?? Text(verbatim: value))
    }
}

/// Today's metric strip: rings spread across the width, or a vertical list
/// at accessibility sizes.
struct VESSMetricStrip<Content: View>: View {
    @ViewBuilder let content: Content

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: VESSSpacing.sm) { content }
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack(alignment: .top, spacing: 0) {
                Group(subviews: content) { subviews in
                    ForEach(subviews) { subview in
                        subview
                        if subview.id != subviews.last?.id { Spacer(minLength: VESSSpacing.xs) }
                    }
                }
            }
        }
    }
}
