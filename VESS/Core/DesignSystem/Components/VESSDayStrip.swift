import SwiftUI

/// A week of days to pick from. The selected day is a filled disc, today is
/// ringed, and a dot marks days that have entries. Future days are shown
/// but not selectable.
struct VESSDayStrip: View {
    let days: [Date]
    @Binding var selection: Date
    let today: Date
    let calendar: Calendar
    let hasEntries: (Date) -> Bool

    @ScaledMetric(relativeTo: .body) private var scaledCircleSize: CGFloat = 36

    /// Capped so seven days always fit: the scaled metric reads the text size
    /// from outside this view's own `dynamicTypeSize` clamp.
    private var circleSize: CGFloat { min(scaledCircleSize, 44) }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(days, id: \.self) { day in
                dayButton(day)
            }
        }
        // Seven columns must always fit the width. Past XXXL the circles
        // would overflow and push the whole screen sideways; VoiceOver
        // still reads each full date.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    private func dayButton(_ day: Date) -> some View {
        let isSelected = calendar.isDate(day, inSameDayAs: selection)
        let isFuture = calendar.startOfDay(for: day) > calendar.startOfDay(for: today)
        let isToday = calendar.isDate(day, inSameDayAs: today)

        return Button {
            selection = day
        } label: {
            VStack(spacing: VESSSpacing.xs - 2) {
                Text(day, format: .dateTime.weekday(.narrow))
                    .vessTextStyle(.label)
                // Selected: a filled disc. Today, when not selected: a quiet ring.
                Text(day, format: .dateTime.day())
                    .font(.callout.weight(isSelected ? .semibold : .regular).monospacedDigit())
                    .foregroundStyle(isSelected ? VESSColor.background : (isFuture ? VESSColor.tertiaryText : VESSColor.text))
                    .frame(width: circleSize, height: circleSize)
                    .background {
                        if isSelected {
                            Circle().fill(VESSColor.text)
                        } else if isToday {
                            Circle().strokeBorder(VESSColor.divider, lineWidth: 1)
                        }
                    }
                Circle()
                    .fill(hasEntries(day) ? VESSColor.secondaryText : .clear)
                    .frame(width: 4, height: 4)
            }
            .frame(maxWidth: .infinity, minHeight: VESSHitTarget.minimum)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isFuture)
        .accessibilityLabel(Text(day, format: .dateTime.weekday(.wide).day().month(.wide)))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
