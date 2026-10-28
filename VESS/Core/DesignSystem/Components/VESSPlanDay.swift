import SwiftUI

/// A day in the Plan week strip and month grid (17, 18; Figma PlanDay).
///
/// - State: Default, Selected (filled), Today (a ring, only when not
///   selected: Selected wins), Muted (outside the month).
/// - Dot: filled when all main meals are planned or eaten, hollow for some,
///   none for nothing. Neutral colours only, never a metric hue.
/// - With `showsWeekday` (the week strip) the selected day is a tall pill;
///   without it (the month grid) a circle.
struct VESSPlanDay: View {
    enum Dot: Equatable { case none, some, all }

    let date: Date
    var dot: Dot = .none
    var isSelected = false
    var isToday = false
    var isMuted = false
    var showsWeekday = true
    /// Spoken after the date: "2 of 3 meals planned".
    var spokenStatus: Text?
    let action: () -> Void

    @ScaledMetric(relativeTo: .body) private var scaledSize: CGFloat = 44

    /// Seven across must fit the width; the week strip scrolls at AX sizes.
    private var size: CGFloat { min(scaledSize, 52) }

    var body: some View {
        Button { action() } label: {
            VStack(spacing: VESSSpacing.xxs) {
                if showsWeekday {
                    Text(date, format: .dateTime.weekday(.narrow))
                        .vessTextStyle(.labelCapsS)
                        .foregroundStyle(isSelected ? VESSColor.onAccent : VESSColor.tertiaryText)
                }
                Text(date, format: .dateTime.day())
                    .vessTextStyle(.numberS)
                    .monospacedDigit()
                    .foregroundStyle(numberColor)
                dotView
            }
            .lineLimit(1)
            // Narrow screens (SE at large sizes) shrink the shape, never overlap.
            .frame(maxWidth: size)
            .frame(height: showsWeekday ? size * 1.45 : size)
            .background { selectionShape }
            .frame(maxWidth: .infinity, minHeight: VESSHitTarget.minimum)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityShowsLargeContentViewer { Text(date, format: .dateTime.weekday(.abbreviated).day()) }
    }

    private var numberColor: Color {
        if isSelected { return VESSColor.onAccent }
        return isMuted ? VESSColor.tertiaryText : VESSColor.text
    }

    @ViewBuilder
    private var dotView: some View {
        let color = isSelected ? VESSColor.onAccent : VESSColor.secondaryText
        Group {
            switch dot {
            case .all: Circle().fill(color)
            case .some: Circle().strokeBorder(color, lineWidth: 1)
            case .none: Color.clear
            }
        }
        .frame(width: 5, height: 5)
    }

    @ViewBuilder
    private var selectionShape: some View {
        if isSelected {
            if showsWeekday {
                Capsule().fill(VESSColor.accentFill)
            } else {
                Circle().fill(VESSColor.accentFill)
            }
        } else if isToday {
            if showsWeekday {
                Capsule().strokeBorder(VESSColor.text, lineWidth: 1.5)
            } else {
                Circle().strokeBorder(VESSColor.text, lineWidth: 1.5)
            }
        }
    }

    /// "Friday 23 October, today, 2 of 3 meals planned".
    private var accessibilityText: Text {
        var text = Text(date, format: .dateTime.weekday(.wide).day().month(.wide))
        if isToday { text = Text("\(text), today") }
        if let spokenStatus { text = Text("\(text), \(spokenStatus)") }
        return text
    }
}

#Preview("States") {
    let day = AppClock.now
    HStack(spacing: 0) {
        VESSPlanDay(date: day, dot: .none, action: {})
        VESSPlanDay(date: day, dot: .some, action: {})
        VESSPlanDay(date: day, dot: .all, action: {})
        VESSPlanDay(date: day, dot: .some, isSelected: true, action: {})
        VESSPlanDay(date: day, dot: .some, isToday: true, action: {})
        VESSPlanDay(date: day, isMuted: true, showsWeekday: false, action: {})
        VESSPlanDay(date: day, dot: .all, isSelected: true, showsWeekday: false, action: {})
    }
    .padding()
    .background(VESSColor.background)
    .preferredColorScheme(.dark)
}
