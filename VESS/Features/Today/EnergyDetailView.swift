import Charts
import SwiftUI

/// Energy (02): one day's energy against the target, how it was spread over
/// the day, and the last seven days. Pushed from Today.
struct EnergyDetailView: View {
    @Environment(LocalStore.self) private var store
    @State private var day = AppClock.now
    @State private var showInfo = false

    private let calendar = Calendar.current

    var body: some View {
        Group {
            if let profile = store.profile {
                content(profile: profile, now: AppClock.now)
            }
        }
        .vessScreenBackground(.energy)
        .vessDetailTitle("Energy")
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("How this is measured", systemImage: "info.circle") { showInfo = true }
            }
        }
        .sheet(isPresented: $showInfo) { EnergyInfoSheet() }
    }

    private func content(profile: UserProfile, now: Date) -> some View {
        let isToday = calendar.isDate(day, inSameDayAs: now)
        let clock = isToday ? now : (calendar.date(bySettingHour: 23, minute: 59, second: 0, of: day) ?? day)
        let entries = store.foodEntries(on: day, calendar: calendar)
        let history = store.foodEntries(
            from: calendar.date(byAdding: .day, value: -MealRegularity.historyDays, to: calendar.startOfDay(for: day)) ?? day,
            to: calendar.startOfDay(for: day)
        )
        let summary = DaySummary(
            entries: entries,
            hydrationLogs: store.hydrationLogs(on: day, calendar: calendar),
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
        let beforeNoon = IntakeAnalysis.beforeNoonShare(entries, calendar: calendar)
        let week = IntakeAnalysis.dailyTotals(
            store.foodEntries(
                from: calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: day)) ?? day,
                to: calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: day)) ?? clock
            ),
            endingOn: day, days: 7, calendar: calendar
        )

        return ScrollView {
            VStack(alignment: .leading, spacing: VESSSpacing.section) {
                VStack(spacing: VESSSpacing.xl) {
                    VESSDayPicker(day: $day, today: now, calendar: calendar)
                    VESSScoreRing(
                        value: entries.isEmpty ? "—" : "\(Int((share * 100).rounded()))",
                        unit: entries.isEmpty ? nil : "%",
                        label: "Energy",
                        sublabel: Text("\(VESSFormat.calories(consumed)) of \(VESSFormat.calories(target)) kcal"),
                        progress: min(share, 1),
                        metric: .energy
                    )
                    .frame(maxWidth: .infinity)
                }

                VStack(spacing: VESSSpacing.sm + 2) {
                    VESSRowGroup {
                        VESSStatusRow(
                            systemImage: "flame",
                            label: "Energy vs. target",
                            value: entries.isEmpty ? "—" : percent(share),
                            level: entries.isEmpty ? nil : StatusLevel.energy(ratio: target > 0 ? consumed / (target * pace) : 0).vessLevel
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
                        linkTitle: nil
                    )
                }

                VStack(alignment: .leading, spacing: VESSSpacing.md) {
                    HStack(alignment: .firstTextBaseline) {
                        VESSSectionHeader(title: "Through the day")
                        if isToday {
                            Text("Now · \(now, format: .dateTime.hour().minute())")
                                .vessTextStyle(.caption)
                                .foregroundStyle(VESSColor.secondaryText)
                        }
                    }
                    EnergyThroughDayChart(entries: entries, target: target, now: isToday ? now : nil, calendar: calendar)
                }

                lastSevenDays(week: week, target: target, isToday: isToday)
            }
            .padding(.horizontal, VESSSpacing.screenInset)
            .padding(.bottom, VESSSpacing.huge)
        }
    }

    private func lastSevenDays(week: [IntakeAnalysis.DayTotal], target: Double, isToday: Bool) -> some View {
        let average = IntakeAnalysis.average(week, \.calories)
        return VStack(alignment: .leading, spacing: VESSSpacing.md) {
            VESSSectionHeader(title: "Last 7 days")
            if let average {
                HStack(alignment: .firstTextBaseline, spacing: VESSSpacing.xs) {
                    Text(VESSFormat.calories(average))
                        .vessTextStyle(.displayM)
                        .foregroundStyle(VESSColor.text)
                    Text("kcal average · \(Self.comparison(average, target: target))")
                        .vessTextStyle(.bodyS)
                        .foregroundStyle(VESSColor.secondaryText)
                }
                .accessibilityElement(children: .combine)
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

    /// "5% under target", "3% above target" or "on target".
    static func comparison(_ value: Double, target: Double) -> String {
        guard target > 0 else { return "" }
        let difference = value / target - 1
        if abs(difference) < 0.01 { return String(localized: "on target") }
        let amount = abs(difference).formatted(.percent.precision(.fractionLength(0)))
        return difference < 0 ? String(localized: "\(amount) under target") : String(localized: "\(amount) above target")
    }

    private func percent(_ value: Double) -> String {
        value.formatted(.percent.precision(.fractionLength(0)))
    }
}

/// The running energy total through the day as a step line, the target as a
/// dashed line, meal icons at their times and, for today, a "now" marker.
private struct EnergyThroughDayChart: View {
    let entries: [FoodLogEntry]
    let target: Double
    /// `nil` for past days.
    let now: Date?
    let calendar: Calendar

    @ScaledMetric(relativeTo: .body) private var height: CGFloat = 200

    var body: some View {
        let points = IntakeAnalysis.cumulative(entries, calendar: calendar)
        let total = points.last?.calories ?? 0
        let endMinute = now.map(minute) ?? 1440
        let line = [IntakeAnalysis.CumulativePoint(minute: 0, calories: 0)] + points
            + [IntakeAnalysis.CumulativePoint(minute: max(endMinute, points.last?.minute ?? 0), calories: total)]
        let yMax = max(target, total) * 1.08
        let meals = MealType.dayOrder.compactMap { meal -> (MealType, Int)? in
            entries.entries(for: meal).map(\.loggedAt).min().map { (meal, minute($0)) }
        }

        Chart {
            ForEach(Array(line.enumerated()), id: \.offset) { _, point in
                LineMark(x: .value("Time", point.minute), y: .value("Energy", point.calories))
                    .interpolationMethod(.stepEnd)
                    .foregroundStyle(VESSColor.calories)
                    .lineStyle(StrokeStyle(lineWidth: 1.75))
            }
            RuleMark(y: .value("Target", target))
                .foregroundStyle(VESSColor.decorative)
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 4]))
                .annotation(position: .top, alignment: .leading) {
                    Text("Target")
                        .vessTextStyle(.caption)
                        .foregroundStyle(VESSColor.tertiaryText)
                }
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
                    .symbolSize(70)
            }
        }
        .chartXScale(domain: 0...1440)
        .chartYScale(domain: 0...yMax)
        .chartXAxis {
            AxisMarks(values: [0, 360, 720, 1080, 1440]) { value in
                AxisValueLabel {
                    if let minutes = value.as(Int.self) {
                        Text(verbatim: String(format: "%02d", minutes / 60))
                            .vessTextStyle(.caption)
                            .foregroundStyle(VESSColor.tertiaryText)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: [0, target / 2, target]) { value in
                AxisGridLine().foregroundStyle(VESSColor.chartGuide)
                AxisValueLabel {
                    if let kcal = value.as(Double.self) {
                        Text(VESSFormat.calories(kcal))
                            .vessTextStyle(.caption)
                            .foregroundStyle(VESSColor.tertiaryText)
                    }
                }
            }
        }
        .frame(height: height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Energy through the day")
        .accessibilityValue(Text("\(VESSFormat.calories(total)) of \(VESSFormat.calories(target)) kcal"))
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
                    item("Last 7 days", "The average covers days with at least one meal logged.")
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
