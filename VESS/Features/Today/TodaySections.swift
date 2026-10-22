import SwiftUI

// MARK: - Header

/// Date in tracked caps, the greeting, and (Debug builds only) the Coach entry.
struct TodayHeader: View {
    let date: Date
    let greeting: String
    var onCoach: (() -> Void)?

    var body: some View {
        HStack(alignment: .center, spacing: VESSSpacing.sm) {
            VStack(alignment: .leading, spacing: VESSSpacing.xxs) {
                Text(date, format: .dateTime.weekday(.wide).day().month(.wide))
                    .vessTextStyle(.labelCapsS)
                    .foregroundStyle(VESSColor.secondaryText)
                Text(greeting)
                    .vessTextStyle(.titleL)
                    .foregroundStyle(VESSColor.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            if let onCoach {
                VESSIconButton(systemImage: "bubble.left", label: "Coach", action: onCoach)
            }
        }
    }
}

// MARK: - Metric strip

/// Fuel, then energy, protein and water as plain percentages of target, then
/// steps from Apple Health ("—" until it is connected; steps are never estimated).
struct TodayMetricStrip: View {
    let summary: DaySummary
    let fuel: FuelScore?
    let health: HealthSnapshot?

    var body: some View {
        VESSMetricStrip {
            VESSMetricStripItem(value: fuel.map { "\($0.value)" } ?? "—", label: "Fuel", progress: Double(fuel?.value ?? 0) / 100, metric: .fuel)
            NavigationLink(destination: EnergyDetailView()) {
                percentItem(summary.consumed.calories, of: summary.targets.calories, label: "Energy", metric: .energy)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens Energy")
            NavigationLink(destination: MacrosDetailView()) {
                percentItem(summary.consumed.proteinGrams, of: summary.targets.proteinGrams, label: "Protein", metric: .protein)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens Macros")
            percentItem(summary.hydration.consumedMilliliters, of: summary.hydration.targetMilliliters, label: "Water", metric: .water)
            NavigationLink(value: ActivityRoute.activity) {
                VESSMetricStripItem(
                    value: health.map { "\(Int((Double($0.steps) / Double(max($0.stepsTarget, 1)) * 100).rounded()))" } ?? "—",
                    label: "Steps",
                    progress: health?.stepsFraction ?? 0,
                    metric: .activity,
                    spokenValue: health.map { Text("\(VESSFormat.steps(Double($0.steps))) of \(VESSFormat.steps(Double($0.stepsTarget))) steps") }
                )
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens Activity")
            .accessibilityIdentifier("today.activity")
        }
    }

    private func percentItem(_ value: Double, of target: Double, label: LocalizedStringResource, metric: VESSMetricKind) -> some View {
        let fraction = target > 0 ? value / target : 0
        let percent = Int((fraction * 100).rounded())
        return VESSMetricStripItem(
            value: "\(percent)",
            label: label,
            progress: min(fraction, 1),
            metric: metric,
            spokenValue: Text("\(percent) percent of target")
        )
    }
}

// MARK: - Fuel ring

struct TodayFuelRing: View {
    let fuel: FuelScore?
    /// Breakfast, lunch and dinner are all logged.
    let mainMealsLogged: Bool
    let onInfo: () -> Void

    var body: some View {
        Button(action: onInfo) {
            ring
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier("today.fuel")
        .accessibilityHint("Explains how Fuel is calculated. A summary of today's logging, not a health measurement.")
    }

    private var ring: some View {
        VESSScoreRing(
            value: fuel.map { "\($0.value)" } ?? "—",
            label: "Fuel",
            // "Building" while the day is still being logged.
            sublabel: mainMealsLogged ? Text("Main meals logged") : Text("Building"),
            progress: Double(fuel?.value ?? 0) / 100
        )
    }
}

// MARK: - Breakdown

/// Energy, protein, fibre and hydration so far, each with its trend versus
/// the prior 30 days when there is enough history (`TrendRule`). "—" before
/// anything is logged; fibre shows "—" when no logged food reports it. The
/// legend appears only when at least one trend is shown.
struct TodayBreakdown: View {
    struct Trends {
        var energy: Trend?
        var protein: Trend?
        var fibre: Trend?
        var hydration: Trend?

        var isEmpty: Bool { [energy, protein, fibre, hydration].allSatisfy { $0 == nil } }
    }

    let summary: DaySummary
    let hasLogged: Bool
    var trends = Trends()

    var body: some View {
        VStack(spacing: VESSSpacing.sm + 2) {
            VESSRowGroup(staggered: true) {
                NavigationLink(destination: EnergyDetailView()) {
                    VESSMetricRow(systemImage: "flame", label: "Energy", value: value(VESSFormat.calories(summary.consumed.calories)), trend: mark(trends.energy))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                NavigationLink(destination: MacrosDetailView()) {
                    VESSMetricRow(systemImage: "fish", label: "Protein", value: value("\(VESSFormat.grams(summary.consumed.proteinGrams)) g"), trend: mark(trends.protein))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                VESSMetricRow(systemImage: "leaf", label: "Fibre", value: summary.consumed.fiberGrams.map { value("\(VESSFormat.grams($0)) g") } ?? "—", trend: mark(trends.fibre))
                VESSMetricRow(
                    systemImage: "drop",
                    label: "Hydration",
                    value: summary.hydration.consumedMilliliters > 0
                        ? "\(VESSFormat.liters(fromMilliliters: summary.hydration.consumedMilliliters)) L"
                        : "—",
                    trend: mark(trends.hydration)
                )
            }
            .vessHairlineBottom()
            if hasLogged && !trends.isEmpty {
                VESSLegendChip()
                    .accessibilityIdentifier("today.legend")
            }
        }
    }

    private func mark(_ trend: Trend?) -> VESSTrend? {
        guard hasLogged else { return nil }
        return switch trend {
        case .up: .up
        case .down: .down
        case .flat: .flat
        case nil: nil
        }
    }

    private func value(_ text: String) -> String {
        hasLogged ? text : "—"
    }
}

// MARK: - Intake

/// Today's energy: the total, the target and what's left, then a 24-hour
/// strip with one bar per logged meal time.
struct TodayIntake: View {
    let summary: DaySummary
    let entries: [FoodLogEntry]
    let calendar: Calendar

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        // At accessibility sizes the link goes under the header.
        let header = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 0))
            : AnyLayout(HStackLayout())

        VStack(alignment: .leading, spacing: VESSSpacing.sm) {
            header {
                VESSSectionHeader(title: "Intake today")
                NavigationLink(destination: EnergyDetailView()) {
                    HStack(spacing: 2) {
                        Text("Energy")
                            .vessTextStyle(.bodyS)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(VESSColor.tertiaryText)
                            .accessibilityHidden(true)
                    }
                    .foregroundStyle(VESSColor.secondaryText)
                    .frame(minHeight: VESSHitTarget.minimum)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("today.openEnergy")
            }
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: VESSSpacing.xs) {
                    total
                    context
                }
                VStack(alignment: .leading, spacing: VESSSpacing.xxs) {
                    total
                    context
                }
            }
            .accessibilityElement(children: .combine)
            IntakeChart(entries: entries, calendar: calendar)
                .padding(.top, VESSSpacing.sm)
        }
    }

    private var total: some View {
        Text(VESSFormat.calories(summary.consumed.calories))
            .vessTextStyle(.displayM)
            .foregroundStyle(VESSColor.text)
            .contentTransition(.numericText())
    }

    private var context: some View {
        let remaining = summary.caloriesRemaining
        let balance = remaining >= 0
            ? String(localized: "\(VESSFormat.calories(remaining)) left")
            : String(localized: "\(VESSFormat.calories(-remaining)) above")
        return Text("of \(VESSFormat.calories(summary.targets.calories)) kcal · \(balance)")
            .vessTextStyle(.bodyS)
            .foregroundStyle(VESSColor.secondaryText)
    }
}

/// One bar per logging time, height relative to the largest. Decorative for
/// VoiceOver; the totals above carry the numbers.
private struct IntakeChart: View {
    let entries: [FoodLogEntry]
    let calendar: Calendar

    @ScaledMetric(relativeTo: .body) private var chartHeight: CGFloat = 64
    @State private var grown = false

    var body: some View {
        let bars = Self.bars(entries, calendar: calendar)
        let largest = bars.map(\.calories).max() ?? 1

        VStack(spacing: VESSSpacing.xs) {
            GeometryReader { proxy in
                ZStack(alignment: .bottomLeading) {
                    Line()
                        .stroke(VESSColor.decorative, style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
                        .frame(height: 1)
                    ForEach(Array(bars.enumerated()), id: \.element.minute) { index, bar in
                        Capsule()
                            .fill(VESSColor.calories)
                            .frame(width: 3, height: max(4, chartHeight * bar.calories / largest) * (grown ? 1 : 0.02))
                            .vessBarGrow(index: index, isGrown: grown)
                            .offset(x: proxy.size.width * Double(bar.minute) / 1440 - 1.5)
                    }
                }
                .frame(maxHeight: .infinity, alignment: .bottom)
            }
            .frame(height: chartHeight)
            HStack {
                ForEach([0, 6, 12, 18, 24], id: \.self) { hour in
                    Text(verbatim: String(format: "%02d", hour))
                        .vessTextStyle(.caption)
                        .foregroundStyle(VESSColor.tertiaryText)
                    if hour != 24 { Spacer(minLength: 0) }
                }
            }
        }
        .accessibilityHidden(true)
        .onAppear { grown = true }
    }

    private struct Bar {
        let minute: Int
        let calories: Double
    }

    private static func bars(_ entries: [FoodLogEntry], calendar: Calendar) -> [Bar] {
        var byMinute: [Int: Double] = [:]
        for entry in entries {
            let parts = calendar.dateComponents([.hour, .minute], from: entry.loggedAt)
            byMinute[(parts.hour ?? 0) * 60 + (parts.minute ?? 0), default: 0] += entry.nutrition.calories
        }
        return byMinute.map { Bar(minute: $0.key, calories: $0.value) }.sorted { $0.minute < $1.minute }
    }

    private struct Line: Shape {
        func path(in rect: CGRect) -> Path {
            Path { path in
                path.move(to: CGPoint(x: rect.minX, y: rect.midY))
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            }
        }
    }
}

// MARK: - Meals

/// The day's meals as a hairline list; each row opens the Nutrition diary.
struct TodayMeals: View {
    let entries: [FoodLogEntry]
    let onOpenDiary: () -> Void

    var body: some View {
        let logged = MealType.dayOrder.filter { !entries.entries(for: $0).isEmpty }

        VStack(alignment: .leading, spacing: 0) {
            VESSSectionHeader(title: "Meals", actionTitle: "Diary", action: onOpenDiary)
            VESSRowGroup {
                ForEach(logged) { meal in
                    let mealEntries = entries.entries(for: meal)
                    Button(action: onOpenDiary) {
                        VESSMealRow(
                            time: mealEntries.map(\.loggedAt).min() ?? AppClock.now,
                            title: Text(meal.title),
                            detail: Text(Self.itemList(mealEntries.map(\.foodName))),
                            calories: VESSFormat.calories(mealEntries.totalNutrition.calories)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Opens Nutrition")
                }
            }
            .vessHairlineBottom()
        }
    }
}

extension TodayMeals {
    /// "Greek yogurt, oats, blueberries": items after the first start in
    /// lowercase, unless they begin with an acronym or brand capital pair.
    static func itemList(_ names: [String]) -> String {
        names.enumerated().map { index, name in
            guard index > 0, let first = name.first, first.isUppercase else { return name }
            let second = name.dropFirst().first
            if let second, second.isUppercase { return name }
            return first.lowercased() + name.dropFirst()
        }
        .formatted(.list(type: .and, width: .narrow))
    }
}

// MARK: - Hydration

/// Water counted toward the target, with a quick +250 ml and the full drink sheet.
struct TodayHydration: View {
    let hydration: HydrationProgress
    let lastDrink: Date?
    let onAddWater: () -> Void
    let onAddDrink: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        // At accessibility sizes the button goes under the sentence (J03),
        // so the sentence keeps the full width.
        let lastDrinkLayout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: VESSSpacing.sm))
            : AnyLayout(HStackLayout(alignment: .center, spacing: VESSSpacing.sm))

        VStack(alignment: .leading, spacing: VESSSpacing.sm) {
            VESSSectionHeader(title: "Hydration", actionTitle: "Add drink", action: onAddDrink)
            VESSMacroBar(
                name: "Water",
                value: VESSFormat.liters(fromMilliliters: hydration.consumedMilliliters),
                target: "/ \(VESSFormat.liters(fromMilliliters: hydration.targetMilliliters)) L",
                adding: hydration.fractionComplete,
                metric: .water
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Water")
            .accessibilityValue(Text("\(VESSFormat.liters(fromMilliliters: hydration.consumedMilliliters)) of \(VESSFormat.liters(fromMilliliters: hydration.targetMilliliters)) liters"))
            .accessibilityIdentifier("today.water.value")
            lastDrinkLayout {
                Group {
                    if let lastDrink {
                        Text("Last drink \(lastDrink, format: .dateTime.hour().minute()).")
                    } else {
                        Text("No drinks logged yet.")
                    }
                }
                .vessTextStyle(.bodyS)
                .foregroundStyle(VESSColor.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                if !dynamicTypeSize.isAccessibilitySize {
                    Spacer(minLength: 0)
                }
                Button("+250 ml", action: onAddWater)
                    .buttonStyle(.vessQuick)
                    .fixedSize()
                    .accessibilityLabel("Add 250 milliliters of water")
                    .accessibilityIdentifier("today.water.add250")
            }
        }
    }
}

// MARK: - Loading (S2)

/// Skeleton shown while Apple Health syncs, with a slow shimmer (static with
/// Reduce Motion). The "Syncing…" label is pinned above the tab bar by the
/// screen (`TodaySyncingLabel`).
struct TodaySkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: VESSSpacing.section) {
            VStack(alignment: .leading, spacing: VESSSpacing.sm) {
                block(width: 140, height: 12)
                block(width: 240, height: 22)
            }
            HStack {
                ForEach(0..<5, id: \.self) { index in
                    VStack(spacing: VESSSpacing.xs) {
                        Circle().fill(VESSColor.fill).frame(width: VESSSize.stripRing, height: VESSSize.stripRing)
                        block(width: 36, height: 6)
                    }
                    if index < 4 { Spacer(minLength: 0) }
                }
            }
            Circle()
                .stroke(VESSColor.fill, lineWidth: VESSRing.lineWidth(diameter: VESSSize.heroRing))
                .frame(width: VESSSize.heroRing, height: VESSSize.heroRing)
                .frame(maxWidth: .infinity)
            VStack(spacing: VESSSpacing.md) {
                block(width: 280, height: 24)
                block(width: 180, height: 24)
            }
            .frame(maxWidth: .infinity)
            VStack(spacing: VESSSize.rowHeight) {
                ForEach(0..<4, id: \.self) { _ in
                    HStack(spacing: VESSSpacing.sm) {
                        Circle().fill(VESSColor.fill).frame(width: 20, height: 20)
                        block(width: 120, height: 10)
                        Spacer()
                        block(width: 64, height: 14)
                    }
                }
            }
        }
        .vessShimmer()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Syncing with Apple Health")
    }

    private func block(width: CGFloat, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: VESSRadius.small, style: .continuous)
            .fill(VESSColor.fill)
            .frame(width: width, height: height)
    }
}

extension View {
    /// A slow highlight sweep across skeleton blocks; static with Reduce Motion.
    func vessShimmer() -> some View {
        modifier(ShimmerModifier())
    }
}

private struct ShimmerModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = -1

    func body(content: Content) -> some View {
        content
            .overlay {
                if !reduceMotion {
                    GeometryReader { proxy in
                        LinearGradient(
                            colors: [.clear, VESSColor.chartGuide, .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: proxy.size.width * 0.6)
                        .offset(x: phase * proxy.size.width)
                    }
                    .mask(content)
                    .clipped()
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
            }
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) { phase = 1.2 }
            }
    }
}

/// "Syncing with Apple Health…", pinned above the tab bar during S2.
struct TodaySyncingLabel: View {
    var body: some View {
        Text("Syncing with Apple Health…")
            .vessTextStyle(.bodyS)
            .foregroundStyle(VESSColor.secondaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, VESSSpacing.screenInset)
            .padding(.vertical, VESSSpacing.sm)
            .background(VESSColor.background)
    }
}
