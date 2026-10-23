import SwiftUI

/// "‹ TODAY ›": steps one day back or forward; never past today.
struct VESSDayPicker: View {
    @Binding var day: Date
    let today: Date
    let calendar: Calendar

    var body: some View {
        let isToday = calendar.isDate(day, inSameDayAs: today)

        HStack(spacing: VESSSpacing.xl) {
            step(by: -1, systemImage: "chevron.left", label: "Previous day", isEnabled: true)
            Group {
                if isToday {
                    Text("Today")
                } else if let yesterday = calendar.date(byAdding: .day, value: -1, to: today),
                          calendar.isDate(day, inSameDayAs: yesterday) {
                    Text("Yesterday")
                } else {
                    Text(day, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated))
                }
            }
            .vessTextStyle(.labelCaps)
            .foregroundStyle(VESSColor.text)
            .frame(minWidth: 110)
            .contentTransition(.opacity)
            step(by: 1, systemImage: "chevron.right", label: "Next day", isEnabled: !isToday)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
    }

    private func step(by days: Int, systemImage: String, label: LocalizedStringResource, isEnabled: Bool) -> some View {
        Button {
            if let next = calendar.date(byAdding: .day, value: days, to: day) { day = next }
        } label: {
            Image(systemName: systemImage)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(isEnabled ? VESSColor.text : VESSColor.decorative)
                .frame(minWidth: VESSHitTarget.minimum, minHeight: VESSHitTarget.minimum)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(Text(label))
    }
}

/// The right-hand label column the Energy charts share, so "0", "1 275"
/// and "2 550" line up on their trailing edge in both.
enum VESSChartAxis {
    static let labelColumn: CGFloat = 48
    static let labelGap: CGFloat = VESSSpacing.xs

    /// A right-aligned axis value with monospaced digits.
    static func label(_ text: String) -> some View {
        Text(verbatim: text)
            .vessTextStyle(.caption)
            .monospacedDigit()
            .foregroundStyle(VESSColor.tertiaryText)
            .lineLimit(1)
            .frame(width: labelColumn, alignment: .trailing)
    }
}

/// Seven days as vertical bars against a dashed target line. Past days are
/// grey; the last (today) is in the metric hue, and with `highlightsReached`
/// so is every day at or above the target. A day with nothing logged is the
/// same short dash every time. Decorative for VoiceOver; callers give the
/// summary as text. The target value sits in the shared label column.
struct VESSWeekBars: View {
    struct Bar: Identifiable {
        let day: Date
        let value: Double
        var id: Date { day }
    }

    let bars: [Bar]
    let target: Double
    let targetLabel: String
    let tint: Color
    var highlightsReached = false

    @ScaledMetric(relativeTo: .body) private var height: CGFloat = 120
    @State private var grown = false

    private static let emptyDash: CGFloat = 4

    var body: some View {
        let scaleMax = max(target * 1.1, bars.map(\.value).max() ?? 0, 1)

        VStack(spacing: VESSSpacing.xs) {
            HStack(alignment: .top, spacing: VESSChartAxis.labelGap) {
                GeometryReader { proxy in
                    let targetY = proxy.size.height * (1 - target / scaleMax)
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: targetY))
                        path.addLine(to: CGPoint(x: proxy.size.width, y: targetY))
                    }
                    .stroke(VESSColor.decorative, style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
                    HStack(alignment: .bottom, spacing: 0) {
                        ForEach(Array(bars.enumerated()), id: \.element.id) { index, bar in
                            let barHeight = bar.value > 0 ? max(Self.emptyDash, proxy.size.height * bar.value / scaleMax) : Self.emptyDash
                            Capsule()
                                .fill(index == bars.count - 1 || (highlightsReached && bar.value >= target) ? tint : VESSColor.chartMuted)
                                .frame(width: 12, height: barHeight * (grown ? 1 : 0.02))
                                .vessBarGrow(index: index, isGrown: grown)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .frame(maxHeight: .infinity, alignment: .bottom)
                }
                GeometryReader { proxy in
                    VESSChartAxis.label(targetLabel)
                        .position(x: VESSChartAxis.labelColumn / 2, y: proxy.size.height * (1 - target / scaleMax))
                }
                .frame(width: VESSChartAxis.labelColumn)
            }
            .frame(height: height)
            HStack(spacing: VESSChartAxis.labelGap) {
                HStack(spacing: 0) {
                    ForEach(Array(bars.enumerated()), id: \.element.id) { index, bar in
                        Text(bar.day, format: .dateTime.weekday(.narrow))
                            .vessTextStyle(.caption)
                            .foregroundStyle(index == bars.count - 1 ? VESSColor.text : VESSColor.tertiaryText)
                            .frame(maxWidth: .infinity)
                    }
                }
                Color.clear.frame(width: VESSChartAxis.labelColumn, height: 1)
            }
        }
        // Chart labels stop growing at accessibility sizes, so the target
        // label doesn't cover the bars; the numbers are in the text above.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .accessibilityHidden(true)
        .onAppear { grown = true }
    }
}

extension StatusLevel {
    var vessLevel: VESSLevel {
        switch self {
        case .low: .poor
        case .sufficient: .sufficient
        case .optimal: .optimal
        }
    }
}
