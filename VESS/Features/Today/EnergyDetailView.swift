import Charts
import SwiftUI

/// Energy (02): one day's energy against the target, how it was spread over
/// the day, and the last seven days. Pushed from Today.
struct EnergyDetailView: View {
    @Environment(LocalStore.self) private var store
    @State private var day = AppClock.now
    @State private var showInfo = false
    @State private var showInsights = false

    private let calendar = Calendar.current

    var body: some View {
        Group {
            if let profile = store.profile {
                content(profile: profile, now: AppClock.now)
            }
        }
        .vessScreenBackground(.energy, clipsUnderBar: false)
        // Content scrolls softly under the glass buttons, not to a hard edge.
        .scrollEdgeEffectStyle(.soft, for: .top)
        .vessDetailTitle("Energy")
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("How this is measured", systemImage: "info.circle") { showInfo = true }
            }
        }
        .sheet(isPresented: $showInfo) { EnergyInfoSheet() }
        .navigationDestination(isPresented: $showInsights) { InsightsView() }
    }

    private func content(profile: UserProfile, now: Date) -> some View {
        let isToday = calendar.isDate(day, inSameDayAs: now)
        let clock = isToday ? now : (calendar.date(bySettingHour: 23, minute: 59, second: 0, of: day) ?? day)
        let entries = store.foodEntries(on: day, calendar: calendar)
        let history = store.foodEntries(
            from: calendar.date(byAdding: .day, value: -MealRegularity.historyDays, to: calendar.startOfDay(for: day)) ?? day,
            to: calendar.startOfDay(for: day)
        )
        let drinks = store.hydrationLogs(on: day, calendar: calendar)
        // Every drink's kcal count in the day's energy (ring, rows, chart,
        // week); alcohol's never in Fuel.
        let alcohol = drinks.drinkEnergy
        let hasEnergy = !entries.isEmpty || !alcohol.isEmpty
        let summary = DaySummary(
            entries: entries,
            hydrationLogs: drinks,
            targets: profile.nutritionTargets,
            waterTargetMilliliters: profile.waterTargetMilliliters,
            day: day,
            now: clock,
            calendar: calendar
        )
        let target = summary.targets.calories
        let consumed = summary.consumed.calories
        let share = target > 0 ? consumed / target : 0
        let allMainMeals = MealType.mainMeals.allSatisfy { !entries.entries(for: $0).isEmpty }
        let pace = allMainMeals ? 1 : max(summary.expectedPace, DaySummary.minimumPace)
        let regularity = MealRegularity.score(today: entries, history: history, calendar: calendar)
        let beforeNoon = IntakeAnalysis.beforeNoonShare(entries, extra: alcohol, calendar: calendar)
        let weekStart = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: day)) ?? day
        let weekEnd = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: day)) ?? clock
        let week = IntakeAnalysis.dailyTotals(
            store.foodEntries(from: weekStart, to: weekEnd),
            extra: store.hydrationLogs(from: weekStart, to: weekEnd).drinkEnergy,
            endingOn: day, days: 7, calendar: calendar
        )

        return ScrollView {
            VStack(alignment: .leading, spacing: VESSSpacing.section) {
                VStack(spacing: VESSSpacing.xl) {
                    VESSDayPicker(day: $day, today: now, calendar: calendar)
                    VESSScoreRing(
                        value: hasEnergy ? "\(Int((share * 100).rounded()))" : "—",
                        unit: hasEnergy ? "%" : nil,
                        label: "Energy",
                        sublabel: Text("\(VESSFormat.calories(consumed)) of \(VESSFormat.calories(target)) kcal"),
                        progress: min(share, 1),
                        metric: .energy
                    )
                    .frame(maxWidth: .infinity)
                }

                VStack(spacing: VESSSpacing.sm + 2) {
                    VESSRowGroup(staggered: true) {
                        VESSStatusRow(
                            systemImage: "flame",
                            label: "Energy vs. target",
                            value: hasEnergy ? percent(share) : "—",
                            level: !hasEnergy ? nil : StatusLevel.energy(ratio: target > 0 ? consumed / (target * pace) : 0).vessLevel
                        )
                        VESSStatusRow(
                            systemImage: "clock",
                            label: "Meal regularity",
                            value: regularity.map(percent) ?? "—",
                            level: regularity.map { StatusLevel.regularity($0).vessLevel }
                        )
                        VESSStatusRow(
                            systemImage: "sun.max",
                            label: "Before noon",
                            value: beforeNoon.map(percent) ?? "—",
                            level: nil
                        )
                    }
                    .vessHairlineBottom()
                    VESSLegendChip(text: Text("Low · Sufficient · Optimal"), showsTriangles: false)
                }

                if let beforeNoon {
                    VESSInsightCard(
                        text: Text("\(percent(beforeNoon)) of \(isToday ? String(localized: "today's") : String(localized: "the day's")) energy came before noon."),
                        linkTitle: "What moves your Fuel",
                        action: { showInsights = true }
                    )
                }

                VStack(alignment: .leading, spacing: VESSSpacing.md) {
                    // Beside the header when it fits, below it at large sizes.
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .firstTextBaseline) {
                            VESSSectionHeader(title: "Through the day").fixedSize()
                            Spacer(minLength: VESSSpacing.md)
                            nowLabel(now: now, isToday: isToday)
                        }
                        VStack(alignment: .leading, spacing: VESSSpacing.xxs) {
                            VESSSectionHeader(title: "Through the day")
                            nowLabel(now: now, isToday: isToday)
                        }
                    }
                    EnergyThroughDayChart(entries: entries, extra: alcohol, target: target, now: isToday ? now : nil, calendar: calendar)
                }

                lastSevenDays(week: week, target: target, isToday: isToday)
            }
            .padding(.horizontal, VESSSpacing.screenInset)
            .padding(.bottom, VESSSpacing.huge)
        }
    }

    @ViewBuilder
    private func nowLabel(now: Date, isToday: Bool) -> some View {
        if isToday {
            Text("Now · \(now, format: .dateTime.hour().minute())")
                .vessTextStyle(.caption)
                .foregroundStyle(VESSColor.secondaryText)
                .fixedSize()
        }
    }

    private func lastSevenDays(week: [IntakeAnalysis.DayTotal], target: Double, isToday: Bool) -> some View {
        let summary = IntakeAnalysis.weekAverage(week, today: AppClock.now, calendar: calendar)
        return VStack(alignment: .leading, spacing: VESSSpacing.md) {
            VESSSectionHeader(title: "Last 7 days")
            switch summary {
            case .average(let calories, let days):
                VStack(alignment: .leading, spacing: VESSSpacing.xxs) {
                    VESSMetric(
                        value: Text(VESSFormat.calories(calories)),
                        context: Text("kcal average · \(Self.share(calories, target: target))"),
                        style: .displayM,
                        contextStyle: .bodyS
                    )
                    .foregroundStyle(VESSColor.text)
                    Text(isToday
                         ? "Based on ^[\(days) day](inflect: true) with meals logged, not counting today."
                         : "Based on ^[\(days) day](inflect: true) with meals logged.")
                        .vessTextStyle(.bodyS)
                        .foregroundStyle(VESSColor.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
            case .notEnough:
                Text("Not enough days yet. An average needs three days with meals logged, not counting today.")
                    .vessTextStyle(.bodyS)
                    .foregroundStyle(VESSColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VESSWeekBars(
                bars: week.map { .init(day: $0.day, value: $0.nutrition.calories) },
                target: target,
                targetLabel: VESSFormat.calories(target),
                tint: VESSColor.calories
            )
            Text(isToday
                 ? "Dashed line is your \(VESSFormat.calories(target)) kcal target. Today is still in progress."
                 : "Dashed line is your \(VESSFormat.calories(target)) kcal target.")
                .vessTextStyle(.bodyS)
                .foregroundStyle(VESSColor.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// "18 % of your 2 550 kcal target": neutral, never "under" or "over".
    static func share(_ value: Double, target: Double) -> String {
        guard target > 0 else { return "" }
        let percent = (value / target).formatted(.percent.precision(.fractionLength(0)))
        return String(localized: "\(percent) of your \(VESSFormat.calories(target)) kcal target")
    }

    private func percent(_ value: Double) -> String {
        value.formatted(.percent.precision(.fractionLength(0)))
    }
}

/// The running energy total through the day as a step line, the target as a
/// dashed line, meal icons at their times and, for today, a "now" marker.
/// Reveals a chart's plot area from the left over 0.6 s on first appear.
/// Shown at once with Reduce Motion. Used by Energy and Caffeine.
struct LineDrawReveal: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drawn = false

    func body(content: Content) -> some View {
        content
            .mask(alignment: .leading) {
                // Taller than the plot: annotations above it (the "Target"
                // label, meal icons) must not be clipped, only revealed.
                Rectangle()
                    .scaleEffect(x: drawn || reduceMotion ? 1 : 0, anchor: .leading)
                    .padding(.vertical, -VESSSpacing.huge)
            }
            .onAppear {
                withAnimation(reduceMotion ? nil : VESSMotion.chart) { drawn = true }
            }
    }
}

private struct EnergyThroughDayChart: View {
    let entries: [FoodLogEntry]
    /// Drinks with kcal, which add to the line but have no meal icon.
    let extra: [IntakeAnalysis.EnergyItem]
    let target: Double
    /// `nil` for past days.
    let now: Date?
    let calendar: Calendar

    @ScaledMetric(relativeTo: .body) private var height: CGFloat = 200
    /// With nothing logged the plot is shorter and says so.
    @ScaledMetric(relativeTo: .body) private var emptyHeight: CGFloat = 120

    var body: some View {
        let points = IntakeAnalysis.cumulative(entries, extra: extra, calendar: calendar)
        let isEmpty = points.isEmpty
        let total = points.last?.calories ?? 0
        let endMinute = now.map(minute) ?? 1440
        let line = [IntakeAnalysis.CumulativePoint(minute: 0, calories: 0)] + points
            + [IntakeAnalysis.CumulativePoint(minute: max(endMinute, points.last?.minute ?? 0), calories: total)]
        // Headroom above the target keeps the meal icons (top row) clear of
        // the "Target" label (just above the dashed line).
        let yMax = max(target, total) * 1.25
        let meals = MealType.dayOrder.compactMap { meal -> (MealType, Int)? in
            entries.entries(for: meal).map(\.loggedAt).min().map { (meal, minute($0)) }
        }

        Chart {
            // Guides at 0, half and the target; the axes are drawn by hand
            // below so labels sit exactly at their values.
            RuleMark(y: .value("Zero", 0)).foregroundStyle(VESSColor.chartGuide)
            RuleMark(y: .value("Half", target / 2)).foregroundStyle(VESSColor.chartGuide)
            if !isEmpty {
                ForEach(Array(line.enumerated()), id: \.offset) { _, point in
                    LineMark(x: .value("Time", point.minute), y: .value("Energy", point.calories))
                        .interpolationMethod(.stepEnd)
                        .foregroundStyle(VESSColor.calories)
                        .lineStyle(StrokeStyle(lineWidth: 1.75))
                }
            }
            RuleMark(y: .value("Target", target))
                .foregroundStyle(VESSColor.decorative)
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 4]))
            ForEach(meals, id: \.0) { meal, minute in
                PointMark(x: .value("Time", minute), y: .value("Energy", yMax))
                    .opacity(0)
                    .annotation(position: .overlay) {
                        Image(systemName: meal.chartSymbol)
                            .font(.caption)
                            .foregroundStyle(VESSColor.secondaryText)
                    }
            }
            if let now {
                RuleMark(x: .value("Now", minute(now)))
                    .foregroundStyle(VESSColor.decorative)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
                PointMark(x: .value("Now", minute(now)), y: .value("Energy", total))
                    .foregroundStyle(VESSColor.calories)
                    .symbolSize(60)
            }
        }
        .chartXScale(domain: 0...1440)
        .chartYScale(domain: 0...yMax)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        // The line draws left to right (MOTION.md); axes stay in place.
        .chartPlotStyle { plot in plot.modifier(LineDrawReveal()) }
        .chartOverlay { proxy in
            GeometryReader { geometry in
                if let plotFrame = proxy.plotFrame {
                    let frame = geometry[plotFrame]
                    axes(proxy: proxy, frame: frame, isEmpty: isEmpty)
                }
            }
        }
        .frame(height: isEmpty ? emptyHeight : height)
        // Room for the hour labels under the plot and the value column on
        // its right (shared with the 7-day bars).
        .padding(.bottom, VESSSpacing.lg)
        .padding(.trailing, VESSChartAxis.labelColumn + VESSChartAxis.labelGap)
        // Labels and meal icons stop growing at accessibility sizes, so they
        // don't run into each other; VoiceOver hears the summary below.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        // Swift Charts exposes its marks even under `children: .ignore`
        // (as minutes since midnight), so the chart is replaced by one summary.
        .accessibilityRepresentation {
            Text("Energy through the day")
                .accessibilityValue(isEmpty ? Text("Nothing logged yet") : Text("\(VESSFormat.calories(total)) of \(VESSFormat.calories(target)) kcal"))
        }
    }

    /// Hour labels at their exact x (00 flush left, 24 flush right) with
    /// faint ticks; value labels right-aligned in the column; "Target" at
    /// the dashed line's end; "Now" beside its rule on the side that's free.
    @ViewBuilder
    private func axes(proxy: ChartProxy, frame: CGRect, isEmpty: Bool) -> some View {
        ForEach([0, 6, 12, 18, 24], id: \.self) { hour in
            if let x = proxy.position(forX: hour * 60) {
                let alignment: Alignment = hour == 0 ? .leading : (hour == 24 ? .trailing : .center)
                Rectangle()
                    .fill(VESSColor.chartGuide)
                    .frame(width: 1, height: 4)
                    .position(x: frame.minX + x, y: frame.maxY + 2)
                Text(verbatim: String(format: "%02d", hour))
                    .vessTextStyle(.caption)
                    .monospacedDigit()
                    .foregroundStyle(VESSColor.tertiaryText)
                    .fixedSize()
                    .frame(width: 40, alignment: alignment)
                    .position(
                        x: frame.minX + x + (hour == 0 ? 20 : (hour == 24 ? -20 : 0)),
                        y: frame.maxY + VESSSpacing.md
                    )
            }
        }
        ForEach([0, target / 2, target], id: \.self) { value in
            if let y = proxy.position(forY: value) {
                VESSChartAxis.label(VESSFormat.calories(value))
                    .position(x: frame.maxX + VESSChartAxis.labelGap + VESSChartAxis.labelColumn / 2, y: frame.minY + y)
            }
        }
        if let y = proxy.position(forY: target) {
            Text("Target")
                .vessTextStyle(.caption)
                .foregroundStyle(VESSColor.tertiaryText)
                .fixedSize()
                .frame(width: frame.width, alignment: .trailing)
                .position(x: frame.midX, y: frame.minY + y - VESSSpacing.sm)
        }
        if let now, let x = proxy.position(forX: minute(now)) {
            // To the right of the rule, where the line has not reached yet;
            // to its left only near midnight, still above the baseline.
            let fitsRight = x + 44 < frame.width
            Text("Now")
                .vessTextStyle(.caption)
                .foregroundStyle(VESSColor.secondaryText)
                .fixedSize()
                .frame(width: 40, alignment: fitsRight ? .leading : .trailing)
                .position(x: frame.minX + x + (fitsRight ? 26 : -26), y: frame.maxY - VESSSpacing.md)
        }
        if isEmpty {
            Text("Nothing logged yet")
                .vessTextStyle(.bodyS)
                .foregroundStyle(VESSColor.tertiaryText)
                .position(x: frame.midX, y: frame.midY)
        }
    }

    private func minute(_ date: Date) -> Int {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }
}

extension MealType {
    /// The icon above the meal's time on charts.
    var chartSymbol: String {
        switch self {
        case .breakfast: "cup.and.saucer"
        case .lunch: "fork.knife"
        case .snack: "leaf"
        case .dinner: "moon"
        }
    }
}

/// How the Energy screen's measures are worked out.
struct EnergyInfoSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: VESSSpacing.lg) {
                    Text("How energy is measured")
                        .vessTextStyle(.editorialM)
                        .foregroundStyle(VESSColor.text)
                    item("Energy vs. target", "What you've logged as a share of your daily target. The level compares it with the share expected by this time of day: optimal within 90–105 %.")
                    item("Meal regularity", "How close today's meals are to your usual times, from the last 14 days. A meal at its usual time scores 100 %; two hours away or more scores 0 %.")
                    item("Before noon", "The share of today's energy you logged before 12:00. It has no level: VESS doesn't judge when you eat.")
                    item("Last 7 days", "The average covers days with at least one meal logged, not counting today, and needs three of them.")
                    Text("Everything here comes from what you log. It describes your logging, not your health.")
                        .vessTextStyle(.bodyS)
                        .foregroundStyle(VESSColor.secondaryText)
                }
                .padding(VESSSpacing.screenInset)
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

    private func item(_ title: LocalizedStringResource, _ text: LocalizedStringResource) -> some View {
        VStack(alignment: .leading, spacing: VESSSpacing.xxs) {
            Text(title)
                .vessTextStyle(.labelCaps)
                .foregroundStyle(VESSColor.text)
            Text(text)
                .vessTextStyle(.bodyM)
                .foregroundStyle(VESSColor.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#Preview("Energy · Dark") {
    NavigationStack { EnergyDetailView() }
        .previewEnvironment(LocalStore.preview())
        .preferredColorScheme(.dark)
}
