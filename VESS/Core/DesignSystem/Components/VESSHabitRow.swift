import SwiftUI

/// A habit in today's list (14-habits): a done toggle, the title and
/// subtitle, and seven day dots for this week.
///
/// No streaks: a day without it is an empty dot, nothing more.
struct VESSHabitRow: View {
    /// One day of the week.
    enum Dot: Equatable {
        /// Done, in the habit's hue.
        case done
        /// A past day without it: an empty dot, nothing more.
        case notDone
        /// Today, not done yet.
        case open
        /// Later this week, or a day the habit isn't scheduled.
        case future
    }

    let title: Text
    let subtitle: Text
    let isDone: Bool
    /// Seven days, in the calendar's week order.
    let dots: [Dot]
    /// The habit's category hue for done dots.
    var hue: Color = VESSColor.text
    /// `nil` when the habit tracks itself: the toggle only shows its state.
    var onToggle: (() -> Void)?
    /// What VoiceOver says for the week, when counting dots isn't right
    /// (N times a week: "1 of 2 this week").
    var spokenWeek: Text?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var toggleSize: CGFloat = 32
    @ScaledMetric(relativeTo: .caption) private var dotSize: CGFloat = 8

    var body: some View {
        let isStacked = dynamicTypeSize.isAccessibilitySize

        // At accessibility sizes the toggle stays beside the title.
        HStack(alignment: isStacked ? .top : .center, spacing: VESSSpacing.md) {
            toggle
            VStack(alignment: .leading, spacing: 2) {
                title
                    .vessTextStyle(.bodyM)
                    .foregroundStyle(VESSColor.text)
                subtitle
                    .vessTextStyle(.bodyS)
                    .foregroundStyle(VESSColor.secondaryText)
                    .lineLimit(isStacked ? nil : 1)
                if isStacked {
                    week.padding(.top, VESSSpacing.xs)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            if !isStacked {
                week
            }
        }
        .padding(.vertical, VESSSpacing.md)
        .frame(minHeight: VESSSize.rowHeight)
    }

    private var toggle: some View {
        let mark = ZStack {
            if isDone {
                Circle().fill(VESSColor.accentFill)
                Image(systemName: "checkmark")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(VESSColor.onAccent)
            } else {
                Circle().strokeBorder(VESSColor.borderStrong, lineWidth: 1.5)
            }
        }
        .frame(width: min(toggleSize, 44), height: min(toggleSize, 44))
        .frame(minWidth: VESSHitTarget.minimum, minHeight: VESSHitTarget.minimum)
        .contentShape(Rectangle())

        return Group {
            if let onToggle {
                Button(action: onToggle) { mark }
                    .buttonStyle(.plain)
                    .accessibilityLabel(title)
                    .accessibilityValue(isDone ? Text("Done") : Text("Not done"))
                    .accessibilityHint("Double-tap to change")
                    .vessHaptic(.success, trigger: isDone) { _, new in new }
            } else {
                mark
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(title)
                    .accessibilityValue(isDone ? Text("Done, from your log") : Text("Not done yet, from your log"))
            }
        }
    }

    /// The week, decorative to VoiceOver except for one summary.
    private var week: some View {
        HStack(spacing: dotSize * 0.6) {
            ForEach(Array(dots.enumerated()), id: \.offset) { _, dot in
                dotView(dot)
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("This week")
        .accessibilityValue(spokenWeek ?? Text("Done on \(dots.filter { $0 == .done }.count) of \(dots.filter { $0 != .future }.count) days so far"))
    }

    @ViewBuilder
    private func dotView(_ dot: Dot) -> some View {
        switch dot {
        case .done: Circle().fill(hue).frame(width: dotSize, height: dotSize)
        case .notDone: Circle().fill(VESSColor.chartTrack).frame(width: dotSize, height: dotSize)
        case .open: Circle().strokeBorder(VESSColor.text, lineWidth: 1.5).frame(width: dotSize, height: dotSize)
        case .future: Circle().strokeBorder(VESSColor.decorative, lineWidth: 1).frame(width: dotSize, height: dotSize)
        }
    }
}

#Preview("Rows") {
    VESSRowGroup {
        VESSHabitRow(title: Text(verbatim: "Protein at breakfast"), subtitle: Text(verbatim: "Daily · from your log"), isDone: true,
                     dots: [.done, .done, .notDone, .done, .future, .future, .future], hue: VESSColor.protein)
        VESSHabitRow(title: Text(verbatim: "Vitamin D"), subtitle: Text(verbatim: "Daily · 08:00"), isDone: true,
                     dots: [.done, .done, .done, .done, .future, .future, .future], onToggle: {})
        VESSHabitRow(title: Text(verbatim: "Water 2.2 L"), subtitle: Text(verbatim: "1.6 of 2.2 L · from your log"), isDone: false,
                     dots: [.done, .notDone, .done, .open, .future, .future, .future], hue: VESSColor.water)
    }
    .padding()
    .background(VESSColor.background)
    .preferredColorScheme(.dark)
}
