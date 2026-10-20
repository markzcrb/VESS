import SwiftUI

// MARK: - Hairline list

/// A list of rows separated by hairlines, set directly on the page.
/// Lists are never stacked cards: one surface, rows divided by 1 pt lines.
struct VESSRowGroup<Content: View>: View {
    /// Leading inset of the separators, so they align with row text.
    var dividerInset: CGFloat = 0
    @ViewBuilder let content: Content

    var body: some View {
        Group(subviews: content) { subviews in
            VStack(spacing: 0) {
                ForEach(subviews) { subview in
                    subview
                    if subview.id != subviews.last?.id {
                        VESSHairline()
                            .padding(.leading, dividerInset)
                    }
                }
            }
        }
    }
}

/// A 1 pt separator line.
struct VESSHairline: View {
    var body: some View {
        Rectangle()
            .fill(VESSColor.divider)
            .frame(height: 1)
            .accessibilityHidden(true)
    }
}

extension View {
    /// Draws a hairline under the view, for rows outside a `VESSRowGroup`.
    func vessHairlineBottom() -> some View {
        overlay(alignment: .bottom) { VESSHairline() }
    }
}

// MARK: - Row

/// A standard row: optional leading view, title and subtitle, optional trailing view.
struct VESSRow<Leading: View, Trailing: View>: View {
    let title: Text
    var subtitle: Text?
    var titleStyle: VESSTextStyle = .bodyM
    var subtitleLineLimit = 1
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        // At accessibility sizes the trailing value moves below the text,
        // so titles keep the full width instead of breaking mid-word.
        let isStacked = dynamicTypeSize.isAccessibilitySize

        HStack(spacing: VESSSpacing.sm + 2) {
            leading

            VStack(alignment: .leading, spacing: 2) {
                title
                    .vessTextStyle(titleStyle)
                    .foregroundStyle(VESSColor.text)
                    .lineLimit(isStacked ? nil : 2)
                if let subtitle {
                    subtitle
                        .vessTextStyle(.bodyS)
                        .foregroundStyle(VESSColor.secondaryText)
                        .lineLimit(isStacked ? nil : subtitleLineLimit)
                }
                if isStacked {
                    trailing
                        .padding(.top, VESSSpacing.xxs)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if !isStacked {
                trailing
            }
        }
        .padding(.vertical, VESSSpacing.sm + 2)
        .frame(minHeight: VESSHitTarget.minimum)
        .contentShape(Rectangle())
    }
}

extension VESSRow where Leading == EmptyView {
    init(
        title: Text,
        subtitle: Text? = nil,
        titleStyle: VESSTextStyle = .bodyM,
        subtitleLineLimit: Int = 1,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.init(
            title: title,
            subtitle: subtitle,
            titleStyle: titleStyle,
            subtitleLineLimit: subtitleLineLimit,
            leading: { EmptyView() },
            trailing: trailing
        )
    }
}

/// A settings, goals or ingredient row: icon, title, subtitle, value and chevron.
struct VESSListRow<Trailing: View>: View {
    var systemImage: String?
    let title: Text
    var subtitle: Text?
    var value: Text?
    var showsChevron = true
    @ViewBuilder var trailing: Trailing

    var body: some View {
        VESSRow(title: title, subtitle: subtitle) {
            if let systemImage { VESSRowIcon(systemImage: systemImage) }
        } trailing: {
            HStack(spacing: VESSSpacing.xs) {
                value?
                    .vessTextStyle(.bodyM)
                    .foregroundStyle(VESSColor.secondaryText)
                trailing
                if showsChevron {
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(VESSColor.tertiaryText)
                        .accessibilityHidden(true)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

extension VESSListRow where Trailing == EmptyView {
    init(systemImage: String? = nil, title: Text, subtitle: Text? = nil, value: Text? = nil, showsChevron: Bool = true) {
        self.init(systemImage: systemImage, title: title, subtitle: subtitle, value: value, showsChevron: showsChevron) { EmptyView() }
    }
}

/// A row's leading SF Symbol: 17 pt regular in a 20 pt frame, secondary text color.
struct VESSRowIcon: View {
    let systemImage: String
    var tint: Color = VESSColor.secondaryText

    @ScaledMetric(relativeTo: .body) private var width = VESSSize.rowIcon

    var body: some View {
        // Wide symbols such as "fish" scale down to the same column as the rest.
        Image(systemName: systemImage)
            .resizable()
            .scaledToFit()
            .fontWeight(.regular)
            .foregroundStyle(tint)
            .frame(width: width, height: width)
            .accessibilityHidden(true)
    }
}

// MARK: - Meal row

/// A meal in the day: time, name and items, kcal. Planned meals are dimmed.
struct VESSMealRow: View {
    let time: Date
    let title: Text
    let detail: Text
    let calories: String
    var isPlanned = false

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                // Title, items, then "520 kcal · 07:45" (J04).
                VStack(alignment: .leading, spacing: VESSSpacing.xxs) {
                    title
                        .vessTextStyle(.bodyMStrong)
                        .foregroundStyle(VESSColor.text)
                    detail
                        .vessTextStyle(.bodyS)
                        .foregroundStyle(VESSColor.secondaryText)
                    Text("\(calories) kcal · \(time, format: .dateTime.hour().minute())")
                        .vessTextStyle(.bodyS)
                        .foregroundStyle(VESSColor.secondaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                regular
            }
        }
        .padding(.vertical, VESSSpacing.sm + 2)
        .opacity(isPlanned ? 0.5 : 1)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var regular: some View {
        HStack(alignment: .top, spacing: VESSSpacing.sm + 2) {
            // A fixed column as wide as the widest time ("12:59 PM" or "23:59"),
            // so titles line up whatever the clock format.
            ZStack(alignment: .leading) {
                Text(Self.widestTime, format: .dateTime.hour().minute())
                    .hidden()
                Text(time, format: .dateTime.hour().minute())
                    .foregroundStyle(VESSColor.tertiaryText)
            }
            .vessTextStyle(.caption)
            VStack(alignment: .leading, spacing: 2) {
                title
                    .vessTextStyle(.bodyMStrong)
                    .foregroundStyle(VESSColor.text)
                detail
                    .vessTextStyle(.bodyS)
                    .foregroundStyle(VESSColor.secondaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 0) {
                Text(verbatim: calories)
                    .vessTextStyle(.numberS)
                    .foregroundStyle(VESSColor.text)
                Text("kcal")
                    .vessTextStyle(.caption)
                    .foregroundStyle(VESSColor.tertiaryText)
            }
        }
    }
}

extension VESSMealRow {
    /// 12:58, the widest hour and minutes in both 12- and 24-hour clocks.
    fileprivate static let widestTime: Date = {
        Calendar.current.date(bySettingHour: 12, minute: 58, second: 0, of: Date(timeIntervalSinceReferenceDate: 0)) ?? .now
    }()
}

// MARK: - Metric rows

/// The direction of today versus the prior 30 days.
enum VESSTrend {
    case up, down, flat
}

/// A small triangle (up, green; down, amber) or a dot (no change).
struct VESSDeltaMark: View {
    let trend: VESSTrend

    var body: some View {
        Group {
            switch trend {
            case .up: VESSTriangle().fill(VESSColor.statusOptimal)
            case .down: VESSTriangle().fill(VESSColor.statusPoor).rotationEffect(.degrees(180))
            case .flat: Circle().fill(VESSColor.statusSufficient).padding(2)
            }
        }
        .frame(width: 8, height: 7)
        .accessibilityLabel(Text(label))
    }

    private var label: LocalizedStringResource {
        switch trend {
        case .up: "Higher than usual"
        case .down: "Lower than usual"
        case .flat: "About usual"
        }
    }
}

struct VESSTriangle: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.closeSubpath()
        }
    }
}

/// A breakdown row: icon, TRACKED LABEL, value and the 30-day delta. 56 pt tall.
struct VESSMetricRow: View {
    let systemImage: String
    let label: LocalizedStringResource
    let value: String
    var trend: VESSTrend?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: VESSSpacing.xxs) {
                    Text(label)
                        .vessTextStyle(.labelCaps)
                        .foregroundStyle(VESSColor.secondaryText)
                    HStack(spacing: VESSSpacing.xs) {
                        Text(verbatim: value)
                            .vessTextStyle(.numberRow)
                            .foregroundStyle(VESSColor.text)
                        if let trend { VESSDeltaMark(trend: trend) }
                    }
                }
                .padding(.vertical, VESSSpacing.sm)
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(spacing: VESSSpacing.sm + 2) {
                    VESSRowIcon(systemImage: systemImage)
                    Text(label)
                        .vessTextStyle(.labelCaps)
                        .foregroundStyle(VESSColor.text)
                    Spacer(minLength: VESSSpacing.xs)
                    Text(verbatim: value)
                        .vessTextStyle(.numberRow)
                        .foregroundStyle(VESSColor.text)
                    if let trend { VESSDeltaMark(trend: trend) }
                }
            }
        }
        .frame(minHeight: VESSSize.rowHeight)
        .accessibilityElement(children: .combine)
    }
}

/// How a measure compares with its range. The tag text carries the meaning.
enum VESSLevel: Int {
    case poor = 0, sufficient, optimal

    var color: Color {
        switch self {
        case .poor: VESSColor.statusPoor
        case .sufficient: VESSColor.secondaryText
        case .optimal: VESSColor.statusOptimal
        }
    }

    var name: LocalizedStringResource {
        switch self {
        case .poor: "Low"
        case .sufficient: "Sufficient"
        case .optimal: "Optimal"
        }
    }
}

/// A status row: icon, TRACKED LABEL, a three-step level and the value.
struct VESSStatusRow: View {
    let systemImage: String
    let label: LocalizedStringResource
    let value: String
    let level: VESSLevel

    @ScaledMetric(relativeTo: .title3) private var valueWidth: CGFloat = 58
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: VESSSpacing.xs))
            : AnyLayout(HStackLayout(spacing: VESSSpacing.sm + 2))

        layout {
            if !dynamicTypeSize.isAccessibilitySize {
                VESSRowIcon(systemImage: systemImage)
            }
            Text(label)
                .vessTextStyle(.labelCaps)
                .foregroundStyle(dynamicTypeSize.isAccessibilitySize ? VESSColor.secondaryText : VESSColor.text)
            if !dynamicTypeSize.isAccessibilitySize {
                Spacer(minLength: VESSSpacing.xs)
            }
            HStack(spacing: 3) {
                ForEach(0..<3, id: \.self) { index in
                    Capsule()
                        .fill(index == level.rawValue ? level.color : VESSColor.chartTrack)
                        .frame(width: 22, height: 3)
                }
            }
            .accessibilityHidden(true)
            Text(verbatim: value)
                .vessTextStyle(.numberRow)
                .foregroundStyle(VESSColor.text)
                .frame(minWidth: dynamicTypeSize.isAccessibilitySize ? nil : valueWidth, alignment: .trailing)
        }
        .padding(.vertical, dynamicTypeSize.isAccessibilitySize ? VESSSpacing.sm : 0)
        .frame(maxWidth: .infinity, minHeight: VESSSize.rowHeight, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(label))
        .accessibilityValue(Text("\(value), \(Text(level.name))"))
    }
}

/// "▲▼ Today vs. prior 30 days": the key for delta marks, on a sunken strip.
struct VESSLegendChip: View {
    var text: Text = Text("Today vs. prior 30 days")
    var showsTriangles = true

    var body: some View {
        HStack(spacing: VESSSpacing.xs - 2) {
            if showsTriangles {
                VESSDeltaMark(trend: .up)
                VESSDeltaMark(trend: .down)
            }
            text
                .vessTextStyle(.caption)
                .foregroundStyle(VESSColor.secondaryText)
            Spacer(minLength: 0)
        }
        .padding(.vertical, VESSSpacing.xs)
        .padding(.horizontal, VESSSpacing.sm)
        .background(VESSColor.sunken, in: RoundedRectangle(cornerRadius: VESSRadius.small, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
    }
}

// MARK: - Thumbnail

/// A square row thumbnail: the user's photo in later phases, otherwise a
/// quiet tile with a symbol. Never stock imagery.
struct VESSThumbnail: View {
    let systemImage: String
    var isAction = false

    @ScaledMetric(relativeTo: .body) private var size: CGFloat = 48

    var body: some View {
        RoundedRectangle(cornerRadius: VESSRadius.thumbnail, style: .continuous)
            .fill(VESSColor.fill)
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: systemImage)
                    .font(.body.weight(isAction ? .medium : .regular))
                    .foregroundStyle(isAction ? VESSColor.accent : VESSColor.secondaryText)
            }
            .accessibilityHidden(true)
    }
}
