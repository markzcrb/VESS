import SwiftUI

// MARK: - Insight card

/// A plain-language insight with an optional tracked-caps link. 1 pt gradient
/// border, which brightens once about 0.9 s after appearing.
struct VESSInsightCard: View {
    /// A short status above the text, such as "Steady".
    var kicker: Text?
    let text: Text
    var linkTitle: LocalizedStringResource? = "Break down my day"
    var action: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isBright = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: VESSRadius.large, style: .continuous)

        VStack(alignment: .leading, spacing: VESSSpacing.sm) {
            kicker?
                .vessTextStyle(.labelCapsS)
                .foregroundStyle(VESSColor.statusOptimal)
            text
                .vessTextStyle(.bodyM)
                .foregroundStyle(VESSColor.text)
                .fixedSize(horizontal: false, vertical: true)
            if let linkTitle {
                Button(action: action) {
                    // One Text, so the arrow follows the tracked caps exactly.
                    Text("\(Text(linkTitle))  \(Image(systemName: "arrow.right"))")
                        .vessTextStyle(.labelCapsLink)
                        .foregroundStyle(VESSColor.accent)
                        .accessibilityLabel(Text(linkTitle))
                    .frame(minHeight: VESSHitTarget.minimum)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, VESSSpacing.md + 2)
        .padding(.bottom, linkTitle == nil ? VESSSpacing.md + 2 : VESSSpacing.xxs)
        .padding(.horizontal, VESSSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(VESSColor.surfaceGlass, in: shape)
        .overlay {
            shape
                .strokeBorder(VESSColor.insightBorder, lineWidth: 1)
                .opacity(isBright ? 1 : 0.85)
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.6).delay(0.9)) { isBright = true }
        }
    }
}

// MARK: - Macro bar

/// Linear macro progress. Grey is what's already logged today; the metric
/// hue is what this item adds (or today's total when nothing is being added).
struct VESSMacroBar: View {
    let name: LocalizedStringResource
    /// "108" or "+31 g".
    let value: String
    /// "/ 140 g" or "→ 139 / 140 g".
    let target: String
    /// Share of the target already logged, drawn in grey.
    var logged: Double = 0
    /// Share of the target this item adds, drawn in the metric hue after `logged`.
    let adding: Double
    let metric: VESSMetricKind

    @ScaledMetric(relativeTo: .body) private var barHeight: CGFloat = 6

    var body: some View {
        VStack(alignment: .leading, spacing: VESSSpacing.sm - 2) {
            HStack(alignment: .firstTextBaseline, spacing: VESSSpacing.xs) {
                Text(name)
                    .vessTextStyle(.labelCaps)
                    .foregroundStyle(VESSColor.text)
                Spacer(minLength: VESSSpacing.xs)
                Text(verbatim: value)
                    .vessTextStyle(.numberS)
                    .foregroundStyle(VESSColor.text)
                Text(verbatim: target)
                    .vessTextStyle(.caption)
                    .foregroundStyle(VESSColor.tertiaryText)
            }
            GeometryReader { proxy in
                let width = proxy.size.width
                let loggedShare = clamp(logged, to: 1)
                let addingShare = clamp(adding, to: 1 - loggedShare)
                ZStack(alignment: .leading) {
                    Capsule().fill(VESSColor.chartTrack)
                    HStack(spacing: 0) {
                        Rectangle().fill(VESSColor.chartMuted).frame(width: width * loggedShare)
                        Rectangle().fill(metric.tint).frame(width: width * addingShare)
                    }
                    .clipShape(Capsule())
                }
            }
            .frame(height: barHeight)
            .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
    }

    private func clamp(_ value: Double, to maximum: Double) -> Double {
        min(max(value, 0), max(maximum, 0))
    }
}

// MARK: - Impact row

/// A pattern in the journal: how a tag relates to the Fuel score, as a
/// centre-zero bar. HURTS extends left in amber, HELPS right in green.
/// Patterns, not causes.
struct VESSImpactRow: View {
    let label: LocalizedStringResource
    /// Signed percent difference, such as 24 or -11.
    let impactPercent: Int
    /// Percent that fills half the bar.
    var maxPercent: Int = 26
    var isNew = false

    @ScaledMetric(relativeTo: .body) private var barHeight: CGFloat = 6

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: VESSRadius.thumbnail, style: .continuous)
        let isPositive = impactPercent >= 0
        let tint = isPositive ? VESSColor.statusOptimal : VESSColor.statusPoor

        VStack(alignment: .leading, spacing: VESSSpacing.sm + 2) {
            HStack(spacing: VESSSpacing.xs) {
                if isNew {
                    VESSTag(text: Text("New"), tone: .accent)
                }
                Text(label)
                    .vessTextStyle(.labelCaps)
                    .foregroundStyle(VESSColor.text)
                Spacer(minLength: VESSSpacing.xs)
                Text(verbatim: isPositive ? "+\(impactPercent)%" : "−\(abs(impactPercent))%")
                    .vessTextStyle(.numberS)
                    .foregroundStyle(tint)
            }
            GeometryReader { proxy in
                let half = proxy.size.width / 2
                let length = max(barHeight, half * min(1, Double(abs(impactPercent)) / Double(maxPercent)))
                ZStack(alignment: .leading) {
                    Capsule().fill(VESSColor.chartTrack).frame(height: barHeight)
                    Capsule()
                        .fill(tint)
                        .frame(width: length, height: barHeight)
                        .offset(x: isPositive ? half : half - length)
                    Circle()
                        .fill(VESSColor.text)
                        .frame(width: barHeight + 2, height: barHeight + 2)
                        .offset(x: half - (barHeight + 2) / 2)
                }
            }
            .frame(height: barHeight + 2)
            .accessibilityHidden(true)
        }
        .padding(.top, VESSSpacing.sm + 2)
        .padding(.bottom, VESSSpacing.md)
        .padding(.horizontal, VESSSpacing.md)
        .background(VESSColor.card, in: shape)
        .overlay { if isNew { shape.strokeBorder(VESSColor.strokeLink, lineWidth: 1) } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(label))
        .accessibilityValue(Text(isPositive ? "\(impactPercent) percent higher Fuel on these days" : "\(abs(impactPercent)) percent lower Fuel on these days"))
    }
}
