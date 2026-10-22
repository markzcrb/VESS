import SwiftUI

/// One day in a month calendar (13-cycle): its number in a circle.
///
/// - Default: the number alone.
/// - Muted: a day outside the month.
/// - Logged: filled in the cycle hue.
/// - Estimated: a dashed cycle-hue outline on the cycle tint.
/// - Today: outlined in the text colour, over any of the above.
///
/// Decorative states are also spoken: VoiceOver reads "9 October, logged".
struct VESSCalendarDay: View {
    enum State: Equatable {
        case `default`, muted, logged, estimated
    }

    let date: Date
    var state: State = .default
    var isToday = false
    /// `nil` for days that can't be opened (future days).
    var action: (() -> Void)?

    @ScaledMetric(relativeTo: .body) private var scaledDiameter: CGFloat = 40

    /// Seven across must fit 402 pt with 20 pt margins, at every text size.
    private var diameter: CGFloat { min(scaledDiameter, 46) }

    var body: some View {
        // The whole cell is the target: at least 44 pt, even when the
        // circle is 40 pt.
        let cell = circle
            .frame(maxWidth: .infinity, minHeight: VESSHitTarget.minimum)
            .contentShape(Rectangle())
        Group {
            if let action {
                Button(action: action) { cell }
                    .buttonStyle(.plain)
            } else {
                cell
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(date, format: .dateTime.day().month(.wide)))
        .accessibilityValue(spokenState)
        .accessibilityAddTraits(action == nil ? [] : .isButton)
    }

    private var circle: some View {
        Text(date, format: .dateTime.day())
            .vessTextStyle(state == .logged || isToday ? .numberRow : .bodyM)
            .monospacedDigit()
            .foregroundStyle(foreground)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            .frame(width: diameter, height: diameter)
            .background {
                switch state {
                case .logged:
                    Circle().fill(VESSColor.cycle)
                case .estimated:
                    Circle()
                        .fill(VESSColor.tintCycle)
                        .overlay(Circle().strokeBorder(VESSColor.cycle, style: StrokeStyle(lineWidth: 1.5, dash: [3, 3])))
                case .default, .muted:
                    EmptyView()
                }
            }
            .overlay {
                if isToday {
                    // Outside the fill, so a logged today keeps both marks.
                    Circle()
                        .strokeBorder(VESSColor.text, lineWidth: 2)
                        .padding(state == .logged ? -4 : 0)
                }
            }
            .contentShape(Circle())
    }

    private var foreground: Color {
        switch state {
        case .logged: VESSColor.onAccent
        case .muted: VESSColor.tertiaryText
        case .default, .estimated: VESSColor.text
        }
    }

    private var spokenState: Text {
        let base: Text? = switch state {
        case .logged: Text("Logged")
        case .estimated: Text("Estimated")
        case .default, .muted: nil
        }
        switch (base, isToday) {
        case (let base?, true): return Text("Today, \(base)")
        case (let base?, false): return base
        case (nil, true): return Text("Today")
        case (nil, false): return Text(verbatim: "")
        }
    }
}

#Preview("States") {
    let calendar = Calendar.current
    let day = AppClock.now
    HStack(spacing: 0) {
        VESSCalendarDay(date: calendar.date(byAdding: .day, value: -30, to: day) ?? day, state: .muted)
        VESSCalendarDay(date: day, state: .default)
        VESSCalendarDay(date: day, state: .logged)
        VESSCalendarDay(date: day, state: .estimated)
        VESSCalendarDay(date: day, isToday: true)
        VESSCalendarDay(date: day, state: .logged, isToday: true)
    }
    .padding()
    .background(VESSColor.background)
    .preferredColorScheme(.dark)
}
