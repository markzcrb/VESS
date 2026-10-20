import SwiftUI

/// A week of days to pick from (Plan week pills). Each day is a column of
/// weekday, date and a dot for days with entries; the selected day is a
/// tall filled capsule. Future days are shown but not selectable.
struct VESSDayStrip: View {
    let days: [Date]
    @Binding var selection: Date
    let today: Date
    let calendar: Calendar
    let hasEntries: (Date) -> Bool

    @ScaledMetric(relativeTo: .body) private var scaledPillWidth: CGFloat = 38
    @ScaledMetric(relativeTo: .body) private var scaledPillHeight: CGFloat = 68
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Capped so seven days always fit: the scaled metric reads the text size
    /// from outside this view's own `dynamicTypeSize` clamp.
    private var pillWidth: CGFloat { min(scaledPillWidth, 46) }
    private var pillHeight: CGFloat { min(scaledPillHeight, 84) }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(days, id: \.self) { day in
                dayButton(day)
            }
        }
        // Seven columns must always fit the width. Past XXXL the pills
        // would overflow and push the whole screen sideways; VoiceOver
        // still reads each full date.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .animation(reduceMotion ? nil : VESSMotion.selection, value: selection)
    }

    private func dayButton(_ day: Date) -> some View {
        let isSelected = calendar.isDate(day, inSameDayAs: selection)
        let isFuture = calendar.startOfDay(for: day) > calendar.startOfDay(for: today)
        let foreground = isSelected ? VESSColor.background : (isFuture ? VESSColor.tertiaryText : VESSColor.text)

        return Button {
            selection = day
        } label: {
            VStack(spacing: VESSSpacing.xxs + 2) {
                Text(day, format: .dateTime.weekday(.narrow))
                    .vessTextStyle(.labelCapsS)
                    .foregroundStyle(isSelected ? VESSColor.background : VESSColor.tertiaryText)
                Text(day, format: .dateTime.day())
                    .vessTextStyle(.numberS)
                    .foregroundStyle(foreground)
                Circle()
                    .fill(hasEntries(day) ? (isSelected ? VESSColor.background : VESSColor.tertiaryText) : .clear)
                    .frame(width: 4, height: 4)
            }
            .frame(width: pillWidth, height: pillHeight)
            .background {
                if isSelected {
                    Capsule().fill(VESSColor.text)
                }
            }
            .frame(maxWidth: .infinity, minHeight: VESSHitTarget.minimum)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isFuture)
        .accessibilityLabel(Text(day, format: .dateTime.weekday(.wide).day().month(.wide)))
        .accessibilityValue(hasEntries(day) ? Text("Has entries") : Text(verbatim: ""))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
