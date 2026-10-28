import SwiftUI

/// The numbers behind a Coach chart, always from this iPhone's own data
/// (the log and Apple Health), never from the answer's text.
struct CoachChartSeries {
    nonisolated enum Style { case bars, line }

    let request: CoachChartRequest
    /// Oldest first; `nil` where there's no data.
    let points: [(day: Date, value: Double?)]
    let target: Double?
    let style: Style

    var hasData: Bool { points.contains { $0.value != nil } }

    @MainActor
    static func make(_ request: CoachChartRequest, store: LocalStore, health: HealthSnapshot?, now: Date, calendar: Calendar) -> CoachChartSeries {
        let today = calendar.startOfDay(for: now)
        let days = (0..<request.days).reversed().compactMap { calendar.date(byAdding: .day, value: -$0, to: today) }
        let start = days.first ?? today
        let end = calendar.date(byAdding: .day, value: 1, to: today) ?? now
        let profile = store.profile
        let targets = profile?.nutritionTargets

        let entries = Dictionary(grouping: store.foodEntries(from: start, to: end)) { calendar.startOfDay(for: $0.loggedAt) }
        let drinks = Dictionary(grouping: store.hydrationLogs(from: start, to: end)) { calendar.startOfDay(for: $0.loggedAt) }
        func food(_ value: (NutritionFacts) -> Double?) -> [(Date, Double?)] {
            days.map { day in (day, entries[day].flatMap { value($0.map(\.nutrition).total) }) }
        }

        switch request.metric {
        case .steps:
            let totals = health.map { ActivityTrends.dailyTotals($0.hourlySteps, days: request.days, endingOn: today, calendar: calendar) }
            return .init(request: request, points: days.map { day in (day, totals?.first { $0.day == day }?.value) },
                         target: profile.map { Double($0.dailyStepsTarget) }, style: .bars)
        case .energy:
            let points = days.map { day -> (Date, Double?) in
                guard entries[day] != nil || drinks[day] != nil else { return (day, nil) }
                let food = entries[day]?.map(\.nutrition).total.calories ?? 0
                return (day, food + (drinks[day] ?? []).reduce(0) { $0 + $1.energyCalories })
            }
            return .init(request: request, points: points, target: targets?.calories, style: .bars)
        case .protein: return .init(request: request, points: food { $0.proteinGrams }, target: targets?.proteinGrams, style: .bars)
        case .carbs: return .init(request: request, points: food { $0.carbohydrateGrams }, target: targets?.carbohydrateGrams, style: .bars)
        case .fat: return .init(request: request, points: food { $0.fatGrams }, target: targets?.fatGrams, style: .bars)
        case .fiber: return .init(request: request, points: food { $0.fiberGrams }, target: TodayRingRules.fiberTargetGrams, style: .bars)
        case .water:
            return .init(request: request, points: days.map { day in (day, drinks[day].map { $0.reduce(0) { $0 + $1.hydrationMilliliters } }) },
                         target: profile?.waterTargetMilliliters, style: .bars)
        case .caffeine:
            return .init(request: request, points: days.map { day in (day, drinks[day].map { _ in CaffeineModel.total(drinks[day] ?? [], on: day, calendar: calendar) }) },
                         target: CaffeineModel.dailyLimitMilligrams, style: .bars)
        case .sleep:
            let nights = SleepRules.nights(health?.sleep ?? [], calendar: calendar)
            return .init(request: request, points: days.map { day in (day, nights.first { $0.day == day }?.asleepMinutes) },
                         target: profile.map { Double($0.dailySleepTargetMinutes) }, style: .bars)
        case .weight:
            let weights = profile.map { Self.weights(profile: $0, health: health, from: start, calendar: calendar) } ?? []
            return .init(request: request, points: days.map { day in (day, weights.last { calendar.isDate($0.measuredAt, inSameDayAs: day) }?.kilograms) },
                         target: profile?.goalWeightKilograms, style: .line)
        case .restingHeartRate:
            return .init(request: request, points: days.map { day in (day, health.flatMap { HeartRules.value(on: day, $0.restingHeartRate, calendar: calendar) }) },
                         target: nil, style: .line)
        case .activeEnergy:
            let totals = health.map { ActivityTrends.dailyTotals($0.hourlyActiveEnergy, days: request.days, endingOn: today, calendar: calendar) }
            return .init(request: request, points: days.map { day in (day, totals?.first { $0.day == day }?.value) }, target: nil, style: .bars)
        case .workouts:
            // Minutes per day, logged and from Apple Health.
            let all = store.workouts + (health?.workouts ?? [])
            return .init(request: request, points: days.map { day in
                let minutes = all.filter { $0.completedAt.map { calendar.isDate($0, inSameDayAs: day) } == true }.compactMap(\.durationMinutes)
                return (day, minutes.isEmpty ? nil : Double(minutes.reduce(0, +)))
            }, target: TodayRingRules.workoutMinutesGoal, style: .bars)
        case .sugar: return .init(request: request, points: food { $0.sugarGrams }, target: TodayRingRules.sugarLimitGrams, style: .bars)
        case .hrv:
            let overnight = health.map { StressRules.overnightHRV($0.heartRateVariability, calendar: calendar) } ?? []
            return .init(request: request, points: days.map { day in (day, HeartRules.value(on: day, overnight, calendar: calendar)) }, target: nil, style: .line)
        case .stress:
            // Each afternoon's level: calm 0, elevated 1, high 2.
            let levels = health.map { StressRules.pastAfternoons(hrvSamples: $0.heartRateVariability, restingHeartRate: $0.restingHeartRate,
                                                                 days: request.days, now: now, calendar: calendar) } ?? [:]
            return .init(request: request, points: days.map { day in (day, levels[day].map(Self.stressValue)) }, target: nil, style: .line)
        case .bmi:
            guard let profile, BodyRules.showsBMI(profile: profile, now: now, calendar: calendar) else {
                return .init(request: request, points: days.map { ($0, nil) }, target: nil, style: .line)
            }
            let trend = BodyRules.trend(weights(profile: profile, health: health, from: start, calendar: calendar), heightCentimeters: profile.heightCentimeters)
            return .init(request: request, points: days.map { day in (day, trend.last { calendar.isDate($0.date, inSameDayAs: day) }?.value) },
                         target: nil, style: .line)
        case .habits:
            // Share of the day's listed habits done, in %.
            let log = HabitLogLoader.log(store: store, health: health, from: start, through: now, calendar: calendar)
            return .init(request: request, points: days.map { day in
                let status = HabitRules.status(store.habits, on: day, today: now, log: log, calendar: calendar)
                return (day, status.listed > 0 ? Double(status.done) / Double(status.listed) * 100 : nil)
            }, target: 100, style: .bars)
        case .supplements:
            // Taken per day; days with nothing due are empty.
            return .init(request: request, points: days.map { day in
                let summary = SupplementRules.today(store.supplements, logs: store.supplementLogs(on: day, calendar: calendar), on: day, calendar: calendar)
                let due = summary.items.filter { SupplementRules.isScheduled($0.supplement, on: day, calendar: calendar) }
                return (day, due.isEmpty ? nil : Double(due.filter { $0.takenAt != nil }.count))
            }, target: nil, style: .bars)
        }
    }

    static func stressValue(_ level: StressRules.Level) -> Double {
        switch level {
        case .calm: 0
        case .elevated: 1
        case .high: 2
        }
    }

    /// Apple Health's weights from `start`, plus the profile weight on the
    /// day it was last saved when Health has none that day.
    private static func weights(profile: UserProfile, health: HealthSnapshot?, from start: Date, calendar: Calendar) -> [BodyMassSample] {
        var weights = (health?.weights ?? []).filter { $0.measuredAt >= start }
        if profile.updatedAt >= start, !weights.contains(where: { calendar.isDate($0.measuredAt, inSameDayAs: profile.updatedAt) }) {
            weights.append(BodyMassSample(kilograms: profile.weightKilograms, measuredAt: profile.updatedAt))
        }
        return weights
    }
}

extension CoachChartRequest.Metric {
    var title: LocalizedStringResource {
        switch self {
        case .steps: "Steps"
        case .energy: "Energy"
        case .protein: "Protein"
        case .carbs: "Carbs"
        case .fat: "Fat"
        case .fiber: "Fiber"
        case .water: "Water"
        case .caffeine: "Caffeine"
        case .sleep: "Sleep"
        case .weight: "Weight"
        case .restingHeartRate: "Resting heart rate"
        case .activeEnergy: "Active energy"
        case .workouts: "Workouts"
        case .sugar: "Sugar"
        case .hrv: "Heart rate variability"
        case .stress: "Stress"
        case .bmi: "BMI"
        case .habits: "Habits"
        case .supplements: "Supplements"
        }
    }

    /// Today's ring for the metric, where Today has one.
    var todayRing: TodayRing? {
        switch self {
        case .steps: .steps
        case .activeEnergy: .activeEnergy
        case .energy: .energy
        case .protein: .protein
        case .carbs: .carbs
        case .fat: .fat
        case .fiber: .fiber
        case .water: .water
        case .caffeine: .caffeine
        case .sleep: .sleep
        case .hrv: .hrv
        case .restingHeartRate: .restingHeartRate
        case .stress: .stress
        case .weight: .weight
        case .bmi: .bmi
        case .habits: .habits
        case .workouts, .sugar, .supplements: nil
        }
    }

    var tint: Color {
        switch self {
        case .steps: VESSColor.activity
        case .energy: VESSColor.calories
        case .protein: VESSColor.protein
        case .carbs, .caffeine: VESSColor.carbs
        case .fat: VESSColor.fat
        case .fiber, .weight, .bmi, .sugar, .supplements: VESSColor.text
        case .water: VESSColor.water
        case .sleep, .stress: VESSColor.sleep
        case .restingHeartRate, .hrv: VESSColor.heart
        case .activeEnergy, .workouts: VESSColor.activity
        case .habits: VESSColor.calories
        }
    }
}

/// A small chart inside a Coach answer: the metric's hue, a dashed target
/// line, day labels and "Last 7 days". Taps open the metric's screen.
struct CoachChartCard: View {
    let series: CoachChartSeries
    let action: () -> Void

    @ScaledMetric(relativeTo: .body) private var height: CGFloat = 96

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: VESSSpacing.sm) {
                HStack(alignment: .firstTextBaseline) {
                    Text(series.request.metric.title)
                        .vessTextStyle(.labelCaps)
                        .foregroundStyle(VESSColor.secondaryText)
                    Spacer()
                    Text(series.request.days == 7 ? "Last 7 days" : "Last 30 days")
                        .vessTextStyle(.caption)
                        .foregroundStyle(VESSColor.tertiaryText)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(VESSColor.tertiaryText)
                }
                if series.hasData {
                    chart.frame(height: height)
                    labels
                } else {
                    Text("No data for these days yet.")
                        .vessTextStyle(.bodyS)
                        .foregroundStyle(VESSColor.secondaryText)
                }
            }
            .padding(VESSSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(VESSColor.card, in: RoundedRectangle(cornerRadius: VESSRadius.large, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: VESSRadius.large, style: .continuous).strokeBorder(VESSColor.divider))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(Text(series.request.metric.title)) chart, last \(series.request.days) days"))
        .accessibilityHint("Opens the details")
    }

    private var chart: some View {
        let values = series.points.compactMap(\.value)
        let isLine = series.style == .line
        let low = isLine ? min(values.min() ?? 0, series.target ?? .infinity) - 1 : 0
        let high = max(values.max() ?? 1, series.target ?? 0) * (isLine ? 1 : 1.1) + (isLine ? 1 : 0)
        func y(_ value: Double, _ size: CGSize) -> CGFloat {
            size.height * (1 - (value - low) / max(high - low, 0.001))
        }
        return GeometryReader { proxy in
            let size = proxy.size
            let slot = size.width / CGFloat(max(series.points.count, 1))
            ZStack(alignment: .topLeading) {
                if let target = series.target {
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: y(target, size)))
                        path.addLine(to: CGPoint(x: size.width, y: y(target, size)))
                    }
                    .stroke(VESSColor.decorative, style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
                }
                if isLine {
                    Path { path in
                        var started = false
                        for (index, point) in series.points.enumerated() {
                            guard let value = point.value else { continue }
                            let location = CGPoint(x: slot * (CGFloat(index) + 0.5), y: y(value, size))
                            if started { path.addLine(to: location) } else { path.move(to: location); started = true }
                        }
                    }
                    .stroke(series.request.metric.tint, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                } else {
                    ForEach(series.points.indices, id: \.self) { index in
                        if let value = series.points[index].value {
                            let top = y(value, size)
                            Capsule()
                                .fill(index == series.points.count - 1 ? series.request.metric.tint : series.request.metric.tint.opacity(0.55))
                                .frame(width: max(min(slot * 0.55, VESSSpacing.md), 2), height: max(size.height - top, 3))
                                .position(x: slot * (CGFloat(index) + 0.5), y: top + (size.height - top) / 2)
                        }
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var labels: some View {
        if series.points.count <= 7 {
            HStack(spacing: 0) {
                ForEach(series.points.indices, id: \.self) { index in
                    Text(series.points[index].day, format: .dateTime.weekday(.narrow))
                        .frame(maxWidth: .infinity)
                }
            }
            .vessTextStyle(.caption)
            .foregroundStyle(VESSColor.tertiaryText)
        } else if let first = series.points.first?.day, let last = series.points.last?.day {
            HStack {
                Text(first, format: .dateTime.day().month(.abbreviated))
                Spacer()
                Text(last, format: .dateTime.day().month(.abbreviated))
            }
            .vessTextStyle(.caption)
            .foregroundStyle(VESSColor.tertiaryText)
        }
    }
}

/// `[[chart:METRIC:today]]`: the metric's ring now, as on Today, with its
/// value. Without a Today ring: workouts fill toward 30 minutes, sugar
/// toward a 50 g limit (like caffeine, never red), supplements as taken
/// of due.
struct CoachTodayCard: View {
    let metric: CoachChartRequest.Metric
    let action: () -> Void

    @Environment(LocalStore.self) private var store
    @Environment(HealthDataStore.self) private var health

    private let calendar = Calendar.current

    var body: some View {
        let reading = self.reading
        Button(action: action) {
            HStack(spacing: VESSSpacing.md) {
                VESSMetricStripItem(value: reading.value, label: metric.title, progress: reading.progress,
                                    metric: reading.kind, spokenValue: reading.spoken, band: reading.band)
                    // Only the ring: the label and value are in the text beside it.
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: VESSSpacing.xxs) {
                    Text(metric.title)
                        .vessTextStyle(.labelCaps)
                        .foregroundStyle(VESSColor.secondaryText)
                    Text(verbatim: reading.detail)
                        .vessTextStyle(.numberRow)
                        .foregroundStyle(VESSColor.text)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Today")
                        .vessTextStyle(.caption)
                        .foregroundStyle(VESSColor.tertiaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(VESSColor.tertiaryText)
                    .accessibilityHidden(true)
            }
            .padding(VESSSpacing.md)
            .background(VESSColor.card, in: RoundedRectangle(cornerRadius: VESSRadius.large, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: VESSRadius.large, style: .continuous).strokeBorder(VESSColor.divider))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(Text(metric.title)) today"))
        .accessibilityValue(reading.spoken)
        .accessibilityHint("Opens the details")
    }

    private struct Reading {
        var value: String
        var detail: String
        var progress: Double
        var kind: VESSMetricKind
        var spoken: Text
        var band: ClosedRange<Double>?
    }

    private var reading: Reading {
        let now = AppClock.now
        let snapshot = health.state.snapshot
        guard let profile = store.profile else {
            return Reading(value: TodayRingReading.empty, detail: TodayRingReading.empty, progress: 0, kind: .fuel, spoken: Text("No value yet"))
        }
        let drinks = store.hydrationLogs(on: now, calendar: calendar)
        if let ring = metric.todayRing {
            let summary = DaySummary(entries: store.foodEntries(on: now, calendar: calendar), hydrationLogs: drinks,
                                     targets: profile.nutritionTargets, waterTargetMilliliters: profile.waterTargetMilliliters,
                                     day: now, now: now, calendar: calendar)
            let showsBMI = BodyRules.showsBMI(profile: profile, now: now, calendar: calendar)
            if ring == .bmi, !showsBMI {
                return Reading(value: TodayRingReading.empty, detail: TodayRingReading.empty, progress: 0, kind: ring.metric, spoken: Text("No value yet"))
            }
            let reading = TodayRingReading.current([ring], profile: profile, summary: summary, fuel: nil, store: store,
                                                   snapshot: snapshot, drinks: drinks, now: now, calendar: calendar)[0]
            return Reading(value: reading.value, detail: reading.valueWithUnit, progress: reading.progress, kind: ring.metric,
                           spoken: reading.spoken, band: reading.band)
        }
        switch metric {
        case .sugar:
            let limit = TodayRingRules.sugarLimitGrams
            guard let sugar = store.foodEntries(on: now, calendar: calendar).map(\.nutrition).total.sugarGrams else {
                return Reading(value: TodayRingReading.empty, detail: TodayRingReading.empty, progress: 0, kind: .carbs, spoken: Text("No value yet"))
            }
            let detail = String(localized: "\(VESSFormat.grams(sugar)) of \(VESSFormat.grams(limit))\u{00A0}g")
            return Reading(value: VESSFormat.grams(sugar), detail: detail, progress: min(sugar / limit, 1), kind: .carbs,
                           spoken: Text(verbatim: detail))
        case .workouts:
            let goal = TodayRingRules.workoutMinutesGoal
            let all = (store.workouts + (snapshot?.workouts ?? [])).filter { $0.completedAt.map { calendar.isDate($0, inSameDayAs: now) } == true }
            let minutes = all.compactMap(\.durationMinutes).reduce(0, +)
            let detail = String(localized: "\(minutes) of \(Int(goal))\u{00A0}min")
            return Reading(value: "\(minutes)", detail: detail, progress: min(Double(minutes) / goal, 1), kind: .activity,
                           spoken: Text(verbatim: detail))
        default:
            // Supplements: taken of due.
            let summary = SupplementRules.today(store.supplements, logs: store.supplementLogs(on: now, calendar: calendar), on: now, calendar: calendar)
            let due = summary.items.filter { SupplementRules.isScheduled($0.supplement, on: now, calendar: calendar) }
            let taken = due.filter { $0.takenAt != nil }.count
            guard !due.isEmpty else {
                return Reading(value: TodayRingReading.empty, detail: String(localized: "Nothing due today"), progress: 0, kind: .fuel, spoken: Text("Nothing due today"))
            }
            return Reading(value: "\(taken)", detail: String(localized: "\(taken) of \(due.count) taken"), progress: Double(taken) / Double(due.count),
                           kind: .fuel, spoken: Text("\(taken) of \(due.count) taken"))
        }
    }
}
