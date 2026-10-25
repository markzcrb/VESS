import SwiftUI

// MARK: - Routes

/// H00–H04 and the Apple Health screen, pushed by value on the Today and
/// You stacks.
enum HealthRoute: Hashable {
    case hub, sleep, heart, stress, body, appleHealth
}

extension View {
    func healthDestinations() -> some View {
        navigationDestination(for: HealthRoute.self) { route in
            switch route {
            case .hub: HealthHubView()
            case .sleep: SleepView()
            case .heart: HeartView()
            case .stress: StressView()
            case .body: BodyView()
            case .appleHealth: AppleHealthView()
            }
        }
    }
}

// MARK: - Formatting

enum HealthFormat {
    /// "7 h 12", "1 h 05", "22 min".
    static func duration(minutes: Double) -> String {
        let total = Int(minutes.rounded())
        guard total >= 60 else { return String(localized: "\(total) min") }
        let minutesPart = (total % 60).formatted(.number.precision(.integerLength(2)))
        return String(localized: "\(total / 60) h \(minutesPart)")
    }

    /// "8 h", "7.5 h".
    static func hours(minutes: Int) -> String {
        let hours = Double(minutes) / 60
        return String(localized: "\(hours.formatted(.number.precision(.fractionLength(0...1)))) h")
    }

    /// "58" (bpm, ms): whole numbers.
    static func whole(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0)))
    }

    /// "56–61".
    static func range(_ range: ClosedRange<Double>) -> String {
        "\(whole(range.lowerBound))\u{2013}\(whole(range.upperBound))"
    }
}

extension StressRules.Level {
    var title: LocalizedStringResource {
        switch self {
        case .calm: "Calm"
        case .elevated: "Elevated"
        case .high: "High"
        }
    }

    /// How far the ring sweeps: a third per level. Not a score.
    var ringFraction: Double {
        switch self {
        case .calm: 1.0 / 3
        case .elevated: 2.0 / 3
        case .high: 1
        }
    }
}

extension StressRules.PartOfDay {
    var title: LocalizedStringResource {
        switch self {
        case .morning: "Morning"
        case .afternoon: "Afternoon"
        case .evening: "Evening"
        }
    }

    /// "afternoon" inside a sentence.
    var inSentence: String {
        switch self {
        case .morning: String(localized: "morning", comment: "Part of the day, inside a sentence")
        case .afternoon: String(localized: "afternoon", comment: "Part of the day, inside a sentence")
        case .evening: String(localized: "evening", comment: "Part of the day, inside a sentence")
        }
    }
}

extension HeartRules.Comparison {
    /// "a little below", for "HRV is a little below your 30-day average."
    var phrase: String {
        switch self {
        case .below: String(localized: "below")
        case .aLittleBelow: String(localized: "a little below")
        case .close: String(localized: "close to")
        case .aLittleAbove: String(localized: "a little above")
        case .above: String(localized: "above")
        }
    }

    /// "Below your 30-day average", for the HRV signal on H03.
    var signal: LocalizedStringResource {
        switch self {
        case .below: "Below your 30-day average"
        case .aLittleBelow: "A little below your 30-day average"
        case .close: "Close to your 30-day average"
        case .aLittleAbove: "A little above your 30-day average"
        case .above: "Above your 30-day average"
        }
    }
}

// MARK: - Shared pieces

/// The info (i) button in a Health screen's nav bar.
struct HealthInfoButton: View {
    let label: LocalizedStringResource
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "info.circle")
        }
        .accessibilityLabel(Text(label))
    }
}

/// What a Health screen measures and what it doesn't: title, then notes.
struct HealthInfoSheet: View {
    let title: LocalizedStringResource
    let notes: [LocalizedStringResource]

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: VESSSpacing.lg) {
                    Text(title)
                        .vessTextStyle(.editorialM)
                        .foregroundStyle(VESSColor.text)
                        .fixedSize(horizontal: false, vertical: true)
                    ForEach(notes.indices, id: \.self) { index in
                        Text(notes[index])
                            .vessTextStyle(.bodyM)
                            .foregroundStyle(index == 0 ? VESSColor.text : VESSColor.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(VESSSpacing.screenInset)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(VESSColor.card)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationCornerRadius(VESSRadius.sheet)
    }
}

/// The scroll page H01–H03 use: hero ring first, then sections.
struct HealthPage<Content: View>: View {
    let title: LocalizedStringResource
    let metric: VESSMetricKind
    let infoLabel: LocalizedStringResource
    let info: HealthInfoSheet
    @ViewBuilder let content: Content

    @State private var showInfo = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: VESSSpacing.section) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, VESSSpacing.screenInset)
            .padding(.top, VESSSpacing.xs)
            .padding(.bottom, VESSSpacing.huge)
        }
        .vessScreenBackground(metric)
        .vessDetailTitle(title)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HealthInfoButton(label: infoLabel) { showInfo = true }
            }
        }
        .sheet(isPresented: $showInfo) { info }
    }
}

/// "A pattern, not a cause": shown only once a pattern is found.
struct HealthPatternCard: View {
    let text: Text

    var body: some View {
        VESSInsightCard(kicker: Text("Pattern"), text: text, linkTitle: nil)
    }
}

/// Seven daily bars, today's in the metric hue and the rest grey, with
/// weekday initials. Decorative for VoiceOver; the screen states the values.
struct HealthWeekBars: View {
    let days: [(day: Date, value: Double?)]
    let metric: VESSMetricKind
    /// Bars start here, so small differences show (resting heart rate).
    var baseline: Double = 0

    @ScaledMetric(relativeTo: .body) private var height: CGFloat = 120
    @State private var grown = false

    var body: some View {
        let values = days.map { max(($0.value ?? baseline) - baseline, 0) }
        let scaleMax = max(values.max() ?? 0, 1)

        VStack(spacing: VESSSpacing.xs) {
            HStack(alignment: .bottom, spacing: 0) {
                ForEach(days.indices, id: \.self) { index in
                    let isLast = index == days.count - 1
                    Capsule()
                        .fill(isLast && days[index].value != nil ? metric.tint : VESSColor.chartMuted)
                        .frame(width: 34, height: max(VESSSpacing.xs, height * values[index] / scaleMax) * (grown ? 1 : 0.02))
                        .vessBarGrow(index: index, isGrown: grown)
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: height, alignment: .bottom)
            HStack(spacing: 0) {
                ForEach(days.indices, id: \.self) { index in
                    Text(days[index].day, format: .dateTime.weekday(.narrow))
                        .frame(maxWidth: .infinity)
                }
            }
            .vessTextStyle(.caption)
            .foregroundStyle(VESSColor.tertiaryText)
        }
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .accessibilityHidden(true)
        .onAppear { grown = true }
    }
}

/// The 2 × 2 tiles on H00; one column at accessibility sizes.
struct HealthTile: View {
    let systemImage: String
    let iconTint: Color
    let label: LocalizedStringResource
    let value: Text
    let caption: Text

    var body: some View {
        VStack(alignment: .leading, spacing: VESSSpacing.xs) {
            HStack(spacing: VESSSpacing.xs) {
                Image(systemName: systemImage)
                    .foregroundStyle(iconTint)
                    .accessibilityHidden(true)
                Text(label)
                    .vessTextStyle(.labelCaps)
                    .foregroundStyle(VESSColor.secondaryText)
            }
            value
                .vessTextStyle(.titleL)
                .foregroundStyle(VESSColor.text)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            caption
                .vessTextStyle(.bodyS)
                .foregroundStyle(VESSColor.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(VESSSpacing.lg)
        .background(VESSColor.card, in: RoundedRectangle(cornerRadius: VESSRadius.large, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: VESSRadius.large, style: .continuous).strokeBorder(VESSColor.divider, lineWidth: 1))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
