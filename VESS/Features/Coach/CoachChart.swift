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
            // Apple Health's weights, plus the profile weight on the day it was
            // last saved when Health has none that day.
            var weights = (health?.weights ?? []).filter { $0.measuredAt >= start }
            if let profile, profile.updatedAt >= start, !weights.contains(where: { calendar.isDate($0.measuredAt, inSameDayAs: profile.updatedAt) }) {
                weights.append(BodyMassSample(kilograms: profile.weightKilograms, measuredAt: profile.updatedAt))
            }
            return .init(request: request, points: days.map { day in (day, weights.last { calendar.isDate($0.measuredAt, inSameDayAs: day) }?.kilograms) },
                         target: profile?.goalWeightKilograms, style: .line)
        case .restingHeartRate:
            return .init(request: request, points: days.map { day in (day, health.flatMap { HeartRules.value(on: day, $0.restingHeartRate, calendar: calendar) }) },
                         target: nil, style: .line)
        }
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
        }
    }

    var tint: Color {
        switch self {
        case .steps: VESSColor.activity
        case .energy: VESSColor.calories
        case .protein: VESSColor.protein
        case .carbs, .caffeine: VESSColor.carbs
        case .fat: VESSColor.fat
        case .fiber, .weight: VESSColor.text
        case .water: VESSColor.water
        case .sleep: VESSColor.sleep
        case .restingHeartRate: VESSColor.heart
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
