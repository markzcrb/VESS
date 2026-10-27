import SwiftUI

extension TodayRing {
    /// The caption under the ring.
    var shortTitle: LocalizedStringResource {
        switch self {
        case .fuel: "Fuel"
        case .energy: "Energy"
        case .protein: "Protein"
        case .carbs: "Carbs"
        case .fat: "Fat"
        case .fiber: "Fibre"
        case .water: "Water"
        case .caffeine: "Caffeine"
        case .steps: "Steps"
        case .activeEnergy: "Active"
        case .sleep: "Sleep"
        case .restingHeartRate: "Resting"
        case .hrv: "HRV"
        case .stress: "Stress"
        case .habits: "Habits"
        case .cycleDay: "Cycle"
        case .bmi: "BMI"
        case .weight: "Weight"
        }
    }

    /// The name in the Edit rings sheet.
    var title: LocalizedStringResource {
        switch self {
        case .fuel: "Fuel"
        case .energy: "Energy"
        case .protein: "Protein"
        case .carbs: "Carbs"
        case .fat: "Fat"
        case .fiber: "Fibre"
        case .water: "Water"
        case .caffeine: "Caffeine"
        case .steps: "Steps"
        case .activeEnergy: "Active energy"
        case .sleep: "Sleep"
        case .restingHeartRate: "Resting heart rate"
        case .hrv: "Heart rate variability"
        case .stress: "Stress"
        case .habits: "Habits"
        case .cycleDay: "Cycle day"
        case .bmi: "BMI"
        case .weight: "Weight"
        }
    }

    /// The secondary line in the Edit rings sheet: what the ring measures.
    var subtitle: LocalizedStringResource? {
        switch self {
        case .fuel: "today's summary"
        case .energy: "kcal vs your target"
        case .protein, .carbs, .fat, .water: "vs your target"
        case .fiber: "vs 30 g a day"
        case .caffeine: "vs your limit"
        case .steps: "vs your goal"
        case .activeEnergy: "vs your 7-day average"
        case .sleep: "last night vs target"
        case .restingHeartRate: "in your usual range"
        case .hrv: "vs your 30-day average"
        case .stress: "estimate"
        case .habits: "done today"
        case .cycleDay: "day of your cycle"
        case .bmi: "on the 15–35 scale"
        case .weight: "progress to your goal"
        }
    }

    /// Its metric hue; rings without one (Fuel, Fiber, Habits) are neutral.
    var metric: VESSMetricKind {
        switch self {
        case .fuel, .fiber, .habits, .bmi, .weight: .fuel
        case .energy: .energy
        case .protein: .protein
        case .carbs, .caffeine: .carbs
        case .fat: .fat
        case .water, .stress: .water
        case .steps, .activeEnergy: .activity
        case .sleep: .sleep
        case .restingHeartRate, .hrv: .heart
        case .cycleDay: .cycle
        }
    }

    var symbol: String {
        switch self {
        case .fuel: "gauge.with.needle"
        case .energy: "flame"
        case .protein: "fish"
        case .carbs: "leaf"
        case .fat: "drop.halffull"
        case .fiber: "carrot"
        case .water: "drop"
        case .caffeine: "cup.and.saucer"
        case .steps: "figure.walk"
        case .activeEnergy: "bolt.heart"
        case .sleep: "moon"
        case .restingHeartRate: "heart"
        case .hrv: "waveform.path.ecg"
        case .stress: "waveform"
        case .habits: "checkmark.circle"
        case .cycleDay: CycleCopy.symbol
        case .bmi: "figure"
        case .weight: "scalemass"
        }
    }
}

extension TodayRing.Group {
    var title: LocalizedStringResource {
        switch self {
        case .nutrition: "Nutrition"
        case .activity: "Activity"
        case .body: "Body"
        case .mind: "Mind"
        }
    }
}

/// What one ring shows: worked out from the day's summary, Apple Health and
/// the logs. Health rings show "—" until Health has data.
struct TodayRingReading: Identifiable {
    let ring: TodayRing
    /// "77", "7:12", "Calm" or "—".
    let value: String
    let progress: Double
    let spoken: Text
    /// A range marked on the ring's track, 0…1 (BMI's 18.5–25).
    var band: ClosedRange<Double>? = nil
    var id: TodayRing { ring }

    /// "77 %", "180 mg", "58 bpm" for the rows at accessibility sizes,
    /// where there's room for the unit.
    var valueWithUnit: String {
        guard value != Self.empty else { return value }
        switch ring {
        case .energy, .protein, .carbs, .fat, .fiber, .water, .steps: return "\(value) %"
        case .caffeine: return String(localized: "\(value) mg")
        case .activeEnergy: return String(localized: "\(value) kcal")
        case .restingHeartRate: return String(localized: "\(value) bpm")
        case .hrv: return String(localized: "\(value) ms")
        case .weight: return String(localized: "\(value) kg")
        default: return value
        }
    }

    static let empty = "—"
    /// The BMI ring's scale, as on H04.
    static let bmiScale = 15.0...35.0

    struct Input {
        let profile: UserProfile
        let summary: DaySummary
        let fuel: FuelScore?
        let snapshot: HealthSnapshot?
        let caffeineMilligrams: Double
        let habitsDone: Int
        let habitsListed: Int
        let cycleDay: Int?
        /// Average of the completed cycles, in days.
        let cycleLength: Double?
        let now: Date
        let calendar: Calendar
    }

    static func readings(_ rings: [TodayRing], input: Input) -> [TodayRingReading] {
        let needsHealth = rings.contains { [.sleep, .restingHeartRate, .hrv, .stress].contains($0) }
        let health = needsHealth ? input.snapshot.map { HealthReadings(snapshot: $0, now: input.now, calendar: input.calendar) } : nil
        return rings.map { reading($0, input: input, health: health) }
    }

    private static func percent(_ ring: TodayRing, _ value: Double, of target: Double) -> TodayRingReading {
        let fraction = target > 0 ? value / target : 0
        let percent = Int((fraction * 100).rounded())
        return TodayRingReading(ring: ring, value: "\(percent)", progress: min(fraction, 1), spoken: Text("\(percent) percent of target"))
    }

    private static func none(_ ring: TodayRing) -> TodayRingReading {
        TodayRingReading(ring: ring, value: empty, progress: 0, spoken: Text("No value yet"))
    }

    private static func reading(_ ring: TodayRing, input: Input, health: HealthReadings?) -> TodayRingReading {
        let consumed = input.summary.consumed
        let targets = input.summary.targets
        switch ring {
        case .fuel:
            guard let fuel = input.fuel else { return none(ring) }
            return TodayRingReading(ring: ring, value: "\(fuel.value)", progress: Double(fuel.value) / 100, spoken: Text("\(fuel.value) of 100"))
        case .energy: return percent(ring, consumed.calories, of: targets.calories)
        case .protein: return percent(ring, consumed.proteinGrams, of: targets.proteinGrams)
        case .carbs: return percent(ring, consumed.carbohydrateGrams, of: targets.carbohydrateGrams)
        case .fat: return percent(ring, consumed.fatGrams, of: targets.fatGrams)
        case .fiber:
            guard let fiber = consumed.fiberGrams else { return none(ring) }
            return percent(ring, fiber, of: TodayRingRules.fiberTargetGrams)
        case .water:
            return percent(ring, input.summary.hydration.consumedMilliliters, of: input.summary.hydration.targetMilliliters)
        case .caffeine:
            let mg = input.caffeineMilligrams
            return TodayRingReading(
                ring: ring, value: VESSFormat.grams(mg), progress: min(CaffeineModel.limitShare(of: mg), 1),
                spoken: Text("\(VESSFormat.grams(mg)) of \(VESSFormat.grams(CaffeineModel.dailyLimitMilligrams)) milligrams")
            )
        case .steps:
            guard let snapshot = input.snapshot else { return none(ring) }
            let percent = Int((Double(snapshot.steps) / Double(max(snapshot.stepsTarget, 1)) * 100).rounded())
            return TodayRingReading(ring: ring, value: "\(percent)", progress: snapshot.stepsFraction,
                                    spoken: Text("\(VESSFormat.steps(Double(snapshot.steps))) of \(VESSFormat.steps(Double(snapshot.stepsTarget))) steps"))
        case .activeEnergy:
            guard let snapshot = input.snapshot, let kcal = snapshot.activeEnergyKilocalories else { return none(ring) }
            // Against the average of the 7 days before, the only "usual" there is.
            let yesterday = input.calendar.date(byAdding: .day, value: -1, to: input.calendar.startOfDay(for: input.now)) ?? input.now
            let usual = ActivityTrends.average(ActivityTrends.dailyTotals(snapshot.hourlyActiveEnergy, days: 7, endingOn: yesterday, calendar: input.calendar))
            return TodayRingReading(ring: ring, value: VESSFormat.calories(kcal), progress: usual.map { $0 > 0 ? min(kcal / $0, 1) : 0 } ?? 0,
                                    spoken: Text("\(VESSFormat.calories(kcal)) kilocalories"))
        case .sleep:
            guard let night = health?.lastNight else { return none(ring) }
            let minutes = Int(night.asleepMinutes.rounded())
            return TodayRingReading(
                ring: ring, value: "\(minutes / 60):\((minutes % 60).formatted(.number.precision(.integerLength(2))))",
                progress: night.asleepMinutes / Double(input.profile.dailySleepTargetMinutes),
                spoken: Text(verbatim: HealthFormat.duration(minutes: night.asleepMinutes))
            )
        case .restingHeartRate:
            guard let resting = health?.restingToday else { return none(ring) }
            return TodayRingReading(ring: ring, value: HealthFormat.whole(resting),
                                    progress: health?.restingUsual.map { HeartRules.ringFraction(resting, in: $0) } ?? 0,
                                    spoken: Text("\(HealthFormat.whole(resting)) beats per minute"))
        case .hrv:
            guard let hrv = health?.hrvToday else { return none(ring) }
            return TodayRingReading(ring: ring, value: HealthFormat.whole(hrv),
                                    progress: health?.hrvAverage.map { $0 > 0 ? min(hrv / $0, 1) : 0 } ?? 0,
                                    spoken: Text("\(HealthFormat.whole(hrv)) milliseconds"))
        case .stress:
            guard case .estimate(let today, _) = health?.stress else { return none(ring) }
            return TodayRingReading(ring: ring, value: String(localized: today.title), progress: today.ringFraction,
                                    spoken: Text("\(Text(today.title)), an estimate"))
        case .habits:
            guard input.habitsListed > 0 else { return none(ring) }
            return TodayRingReading(ring: ring, value: "\(input.habitsDone)/\(input.habitsListed)",
                                    progress: Double(input.habitsDone) / Double(input.habitsListed),
                                    spoken: Text("\(input.habitsDone) of \(input.habitsListed) done"))
        case .bmi:
            // As on H04: adults only, never during pregnancy (the ring isn't
            // offered then); "—" without height or weight.
            guard BodyRules.showsBMI(profile: input.profile, now: input.now, calendar: input.calendar),
                  let bmi = BodyRules.bmi(profile: input.profile, health: input.snapshot?.latestWeight) else { return none(ring) }
            let scale = TodayRingReading.bmiScale
            func fraction(_ value: Double) -> Double { min(max((value - scale.lowerBound) / (scale.upperBound - scale.lowerBound), 0), 1) }
            let value = bmi.formatted(.number.precision(.fractionLength(1)))
            return TodayRingReading(ring: ring, value: value, progress: fraction(bmi), spoken: Text("BMI \(value)"),
                                    band: fraction(18.5)...fraction(25))
        case .weight:
            let weight = BodyRules.weight(profile: input.profile, health: input.snapshot?.latestWeight)
            guard weight > 0 else { return none(ring) }
            let value = VESSFormat.quantity(weight)
            // Toward the goal from the earliest weight in the last 12 weeks;
            // no arc without a goal, or during pregnancy.
            var progress = 0.0
            if let goal = input.profile.goalWeightKilograms, !input.profile.pregnant,
               let start = input.snapshot?.weights.first?.kilograms ?? Optional(input.profile.weightKilograms), start != goal {
                progress = min(max((start - weight) / (start - goal), 0), 1)
            }
            return TodayRingReading(ring: ring, value: value, progress: progress, spoken: Text("\(value) kilograms"))
        case .cycleDay:
            guard let day = input.cycleDay else { return none(ring) }
            return TodayRingReading(ring: ring, value: "\(day)", progress: min(Double(day) / (input.cycleLength ?? 28), 1),
                                    spoken: Text("Cycle day \(day)"))
        }
    }
}
