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
                } else if calendar.isDateInYesterday(day) {
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

/// Seven days as vertical bars against a dashed target line. Past days are
/// grey; the last (today) is in the metric hue. Decorative for VoiceOver;
/// callers give the summary as text.
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

    @ScaledMetric(relativeTo: .body) private var height: CGFloat = 120
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var grown = false

    var body: some View {
        let scaleMax = max(target * 1.1, bars.map(\.value).max() ?? 0, 1)

        VStack(spacing: VESSSpacing.xs) {
            ZStack(alignment: .topTrailing) {
                GeometryReader { proxy in
                    let targetY = proxy.size.height * (1 - target / scaleMax)
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: targetY))
                        path.addLine(to: CGPoint(x: proxy.size.width, y: targetY))
                    }
                    .stroke(VESSColor.decorative, style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
                    Text(verbatim: targetLabel)
                        .vessTextStyle(.caption)
                        .foregroundStyle(VESSColor.tertiaryText)
                        .padding(.horizontal, VESSSpacing.xxs)
                        .background(VESSColor.background)
                        .position(x: proxy.size.width - 24, y: max(targetY - 10, 8))
                    HStack(alignment: .bottom, spacing: 0) {
                        ForEach(Array(bars.enumerated()), id: \.element.id) { index, bar in
                            Capsule()
                                .fill(index == bars.count - 1 ? tint : VESSColor.chartMuted)
                                .frame(width: 12, height: max(4, proxy.size.height * bar.value / scaleMax) * (grown ? 1 : 0.02))
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .frame(maxHeight: .infinity, alignment: .bottom)
                }
            }
            .frame(height: height)
            HStack(spacing: 0) {
                ForEach(Array(bars.enumerated()), id: \.element.id) { index, bar in
                    Text(bar.day, format: .dateTime.weekday(.narrow))
                        .vessTextStyle(.caption)
                        .foregroundStyle(index == bars.count - 1 ? VESSColor.text : VESSColor.tertiaryText)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .accessibilityHidden(true)
        .onAppear { withAnimation(reduceMotion ? nil : VESSMotion.chart) { grown = true } }
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
