import SwiftUI

/// Journal insights (04). The statistical method isn't decided yet
/// (PRODUCT-LOGIC.md #3), so Release always shows S3: how many days are
/// logged toward the 30 the design asks for, with example rows. DEBUG demo
/// builds (`-seedSampleData`, previews) show the 04 list with demo values.
struct InsightsView: View {
    @Environment(LocalStore.self) private var store

    #if DEBUG
    /// Previews only: force the demo list (`true`) or S3 (`false`).
    var forcesDemo: Bool? = nil
    #endif

    /// Days of logging the design asks for before showing patterns.
    static let daysNeeded = 30
    private static let windowDays = 90

    private let calendar = Calendar.current

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: VESSSpacing.section) {
                #if DEBUG
                if forcesDemo ?? Self.showsDemo {
                    demo
                } else {
                    notEnoughData
                }
                #else
                notEnoughData
                #endif
            }
            .padding(.horizontal, VESSSpacing.screenInset)
            .padding(.top, VESSSpacing.xs)
            .padding(.bottom, VESSSpacing.huge)
        }
        .vessScreenBackground()
        .vessDetailTitle("Journal insights")
        .toolbar(.hidden, for: .tabBar)
    }

    /// Distinct days with something logged in the last 90 days.
    private var loggedDays: Int {
        let today = calendar.startOfDay(for: AppClock.now)
        let start = calendar.date(byAdding: .day, value: -(Self.windowDays - 1), to: today) ?? today
        let end = calendar.date(byAdding: .day, value: 1, to: today) ?? today
        return Set(store.foodEntries(from: start, to: end).map { calendar.startOfDay(for: $0.loggedAt) }).count
    }

    // MARK: S3

    @ViewBuilder
    private var notEnoughData: some View {
        let days = loggedDays
        let remaining = max(Self.daysNeeded - days, 0)

        Text("What moves your Fuel")
            .vessTextStyle(.editorialL)
            .foregroundStyle(VESSColor.text)
            .accessibilityAddTraits(.isHeader)

        ZStack {
            VESSRingShape(
                progress: Double(min(days, Self.daysNeeded)) / Double(Self.daysNeeded),
                tint: VESSColor.accent,
                lineWidth: VESSRing.lineWidth(diameter: VESSSize.heroRing)
            )
            VStack(spacing: VESSSpacing.xxs) {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(verbatim: "\(min(days, Self.daysNeeded))")
                        .vessTextStyle(.displayHero)
                        .foregroundStyle(VESSColor.text)
                    Text(verbatim: "/\(Self.daysNeeded)")
                        .vessTextStyle(.titleL)
                        .foregroundStyle(VESSColor.secondaryText)
                }
                Text("Days logged")
                    .vessTextStyle(.labelCaps)
                    .foregroundStyle(VESSColor.text)
                Group {
                    if remaining > 0 {
                        Text("^[\(remaining) more](inflect: true) to go")
                    } else {
                        Text("Enough days logged")
                    }
                }
                .vessTextStyle(.caption)
                .foregroundStyle(VESSColor.secondaryText)
            }
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        }
        .frame(width: VESSSize.heroRing, height: VESSSize.heroRing)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Days logged"))
        .accessibilityValue(Text("\(min(days, Self.daysNeeded)) of \(Self.daysNeeded)"))

        Group {
            if remaining > 0 {
                Text("Insights need about \(Self.daysNeeded) days of logging so a pattern isn't just one odd week. Keep logging and they'll show up here.")
            } else {
                Text("You've logged enough days. Insights will appear here once VESS can compare them carefully.")
            }
        }
        .vessTextStyle(.bodyM)
        .foregroundStyle(VESSColor.secondaryText)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity)

        // Examples of what will appear, faded and silent for VoiceOver.
        VStack(spacing: VESSSpacing.sm) {
            VESSImpactRow(label: "Drank 2\u{00A0}L or more", impactPercent: 14, isPlaceholder: true)
            VESSImpactRow(label: "Protein at breakfast", impactPercent: 14, isPlaceholder: true)
            VESSImpactRow(label: "Dinner after 21:00", impactPercent: -7, isPlaceholder: true)
        }
        .opacity(0.28)
        .accessibilityHidden(true)
    }

    // MARK: 04 (DEBUG demo)

    #if DEBUG
    /// Demo builds only: the reference values, pescatarian ("Ate fish").
    static var showsDemo: Bool {
        let info = ProcessInfo.processInfo
        return info.arguments.contains("-seedSampleData") || info.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }

    private static let demoRows: [(label: LocalizedStringResource, percent: Int, isNew: Bool)] = [
        ("Drank 2\u{00A0}L or more", 24, false),
        ("Protein at breakfast", 21, false),
        ("Cooked at home", 13, false),
        ("Workout day", 6, false),
        ("Ate fish", 2, true),
        ("Dinner after 21:00", -6, false),
        ("Alcohol", -11, false),
        ("Skipped lunch", -14, false),
    ]

    @ViewBuilder
    private var demo: some View {
        VStack(alignment: .leading, spacing: VESSSpacing.sm) {
            Text("Demo values")
                .vessTextStyle(.labelCapsS)
                .foregroundStyle(VESSColor.secondaryText)
            Text("What moves your Fuel")
                .vessTextStyle(.editorialL)
                .foregroundStyle(VESSColor.text)
                .accessibilityAddTraits(.isHeader)
            Text("How behaviours you log shifted your Fuel score over the past 90 days.")
                .vessTextStyle(.bodyM)
                .foregroundStyle(VESSColor.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }

        VStack(spacing: VESSSpacing.sm) {
            HStack {
                Text("\(Image(systemName: "arrowtriangle.down.fill")) Hurts")
                    .foregroundStyle(VESSColor.warningText)
                Spacer()
                Text("% impact")
                    .foregroundStyle(VESSColor.tertiaryText)
                Spacer()
                Text("Helps \(Image(systemName: "arrowtriangle.up.fill"))")
                    .foregroundStyle(VESSColor.statusOptimalText)
            }
            .vessTextStyle(.labelCapsS)
            .accessibilityHidden(true)

            ForEach(Self.demoRows, id: \.percent) { row in
                VESSImpactRow(label: row.label, impactPercent: row.percent, isNew: row.isNew)
            }
        }

        ActivityFootnote(text: Text(verbatim: "Demo values for review (DEBUG only). These are patterns, not causes; small effects can be noise."))
    }
    #endif
}

#if DEBUG
#Preview("04 demo") {
    NavigationStack {
        InsightsView()
    }
    .previewEnvironment(LocalStore.preview())
    .preferredColorScheme(.dark)
}

#Preview("S3") {
    NavigationStack {
        InsightsView(forcesDemo: false)
    }
    .previewEnvironment(LocalStore.preview())
}
#endif
