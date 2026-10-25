import Foundation
import HealthKit

/// Reads activity from Apple Health. Read-only: VESS asks for no write
/// access. Views never use this directly; `HealthDataStore` does.
nonisolated protocol HealthService: Sendable {
    /// Whether this device has Apple Health.
    var isAvailable: Bool { get }
    /// Shows the system sheet for steps, workouts, active energy and weight.
    func requestAuthorization() async throws
    /// The last `HealthKitService.historyDays` days. `nil` when Health shares
    /// nothing at all: access is off, or there is no data. Health doesn't
    /// say which.
    func snapshot(now: Date, calendar: Calendar, stepsTarget: Int) async throws -> HealthSnapshot?
}

/// The live reader, built on HealthKit's async query descriptors.
nonisolated struct HealthKitService: HealthService {
    /// Enough for 30 days against the 30 before, and four past same weekdays.
    static let historyDays = 61

    private let store = HKHealthStore()

    /// Read only. Sleep, heart and stress (H01–H03), body fat and waist
    /// (H04), State of Mind and mindful minutes as stress signals.
    private var readTypes: Set<HKObjectType> {
        [
            HKQuantityType(.stepCount), HKQuantityType(.activeEnergyBurned), HKQuantityType(.bodyMass), HKObjectType.workoutType(),
            HKCategoryType(.sleepAnalysis), HKQuantityType(.restingHeartRate), HKQuantityType(.heartRateVariabilitySDNN),
            HKQuantityType(.walkingHeartRateAverage), HKQuantityType(.heartRate), HKSampleType.stateOfMindType(),
            HKCategoryType(.mindfulSession), HKQuantityType(.bodyFatPercentage), HKQuantityType(.waistCircumference),
        ]
    }

    /// Six weeks of sleep: 28 nights for "usual", five weeks for patterns.
    static let sleepDays = 42

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    func requestAuthorization() async throws {
        try await store.requestAuthorization(toShare: [], read: readTypes)
    }

    func snapshot(now: Date, calendar: Calendar, stepsTarget: Int) async throws -> HealthSnapshot? {
        let today = calendar.startOfDay(for: now)
        guard let start = calendar.date(byAdding: .day, value: -(Self.historyDays - 1), to: today),
              let end = calendar.date(byAdding: .day, value: 1, to: today) else { return nil }

        async let steps = hourly(.stepCount, unit: .count(), from: start, to: end)
        async let energy = hourly(.activeEnergyBurned, unit: .kilocalorie(), from: start, to: end)
        async let workouts = workouts(from: start, to: end)
        async let weight = latestWeight()
        async let weightHistory = weights(since: calendar.date(byAdding: .weekOfYear, value: -12, to: today) ?? today)
        let (hourlySteps, hourlyEnergy, recorded, latestWeight, weights) = try await (steps, energy, workouts, weight, weightHistory)

        let sleepStart = calendar.date(byAdding: .day, value: -Self.sleepDays, to: today) ?? start
        let beatsPerMinute = HKUnit.count().unitDivided(by: .minute())
        async let sleep = sleepSamples(from: sleepStart, to: end)
        async let resting = daily(.restingHeartRate, unit: beatsPerMinute, from: start, to: end)
        async let walking = daily(.walkingHeartRateAverage, unit: beatsPerMinute, from: start, to: end)
        async let variability = samples(.heartRateVariabilitySDNN, unit: .secondUnit(with: .milli), from: start, to: end)
        async let heartToday = hourlyRange(.heartRate, unit: beatsPerMinute, from: today, to: end)
        async let mood = stateOfMind(from: start, to: end)
        async let mindful = mindfulMinutes(from: today, to: end)
        async let fat = latest(.bodyFatPercentage, unit: .percent())
        async let waistSize = latest(.waistCircumference, unit: .meterUnit(with: .centi))
        let (sleepSamples, restingHR, walkingHR, hrv, heartRanges, moods, mindfulToday, bodyFat, waist) =
            try await (sleep, resting, walking, variability, heartToday, mood, mindful, fat, waistSize)

        let hasAny = !hourlySteps.isEmpty || !hourlyEnergy.isEmpty || !recorded.isEmpty || !sleepSamples.isEmpty
            || !restingHR.isEmpty || !hrv.isEmpty || latestWeight != nil || bodyFat != nil
        guard hasAny else { return nil }
        return HealthSnapshot(
            steps: Int(ActivityTrends.total(hourlySteps, on: now, calendar: calendar) ?? 0),
            stepsTarget: stepsTarget,
            activeEnergyKilocalories: ActivityTrends.total(hourlyEnergy, on: now, calendar: calendar),
            updatedAt: now,
            hourlySteps: hourlySteps,
            hourlyActiveEnergy: hourlyEnergy,
            workouts: recorded,
            latestWeight: latestWeight,
            weights: weights,
            sleep: sleepSamples,
            restingHeartRate: restingHR,
            heartRateVariability: hrv,
            walkingHeartRate: walkingHR,
            heartRateToday: heartRanges,
            stateOfMind: moods,
            mindfulMinutesToday: mindfulToday,
            bodyFat: bodyFat.map { MeasurementSample(value: $0.value * 100, measuredAt: $0.measuredAt) },
            waist: waist
        )
    }

    // MARK: Body signals

    private func sleepSamples(from start: Date, to end: Date) async throws -> [SleepSample] {
        let query = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: HKCategoryType(.sleepAnalysis), predicate: HKQuery.predicateForSamples(withStart: start, end: end))],
            sortDescriptors: [SortDescriptor(\.startDate)],
            limit: 5000
        )
        do {
            return try await query.result(for: store).compactMap { sample in
                guard let stage = Self.stage(HKCategoryValueSleepAnalysis(rawValue: sample.value)) else { return nil }
                return SleepSample(
                    start: sample.startDate, end: sample.endDate, stage: stage,
                    isWatch: sample.sourceRevision.productType?.hasPrefix("Watch") == true
                )
            }
        } catch let error as HKError where error.code == .errorNoData {
            return []
        }
    }

    private static func stage(_ value: HKCategoryValueSleepAnalysis?) -> SleepSample.Stage? {
        switch value {
        case .inBed: .inBed
        case .asleepUnspecified: .asleep
        case .asleepCore: .core
        case .asleepDeep: .deep
        case .asleepREM: .rem
        case .awake: .awake
        default: nil
        }
    }

    /// One average per day.
    private func daily(_ identifier: HKQuantityTypeIdentifier, unit: HKUnit, from start: Date, to end: Date) async throws -> [DailyValue] {
        let query = HKStatisticsCollectionQueryDescriptor(
            predicate: .quantitySample(type: HKQuantityType(identifier), predicate: HKQuery.predicateForSamples(withStart: start, end: end)),
            options: .discreteAverage,
            anchorDate: start,
            intervalComponents: DateComponents(day: 1)
        )
        do {
            return try await query.result(for: store).statistics().compactMap { statistics in
                statistics.averageQuantity().map { DailyValue(day: statistics.startDate, value: $0.doubleValue(for: unit)) }
            }
        } catch let error as HKError where error.code == .errorNoData {
            return []
        }
    }

    private func samples(_ identifier: HKQuantityTypeIdentifier, unit: HKUnit, from start: Date, to end: Date) async throws -> [TimedValue] {
        let query = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: HKQuantityType(identifier), predicate: HKQuery.predicateForSamples(withStart: start, end: end))],
            sortDescriptors: [SortDescriptor(\.startDate)],
            limit: 5000
        )
        do {
            return try await query.result(for: store).map { TimedValue(date: $0.startDate, value: $0.quantity.doubleValue(for: unit)) }
        } catch let error as HKError where error.code == .errorNoData {
            return []
        }
    }

    private func hourlyRange(_ identifier: HKQuantityTypeIdentifier, unit: HKUnit, from start: Date, to end: Date) async throws -> [HourlyRange] {
        let query = HKStatisticsCollectionQueryDescriptor(
            predicate: .quantitySample(type: HKQuantityType(identifier), predicate: HKQuery.predicateForSamples(withStart: start, end: end)),
            options: [.discreteMin, .discreteMax],
            anchorDate: start,
            intervalComponents: DateComponents(hour: 1)
        )
        do {
            return try await query.result(for: store).statistics().compactMap { statistics in
                guard let low = statistics.minimumQuantity(), let high = statistics.maximumQuantity() else { return nil }
                return HourlyRange(start: statistics.startDate, min: low.doubleValue(for: unit), max: high.doubleValue(for: unit))
            }
        } catch let error as HKError where error.code == .errorNoData {
            return []
        }
    }

    /// State of Mind, read only: the valence (−1 unpleasant … 1 pleasant).
    private func stateOfMind(from start: Date, to end: Date) async throws -> [TimedValue] {
        let query = HKSampleQueryDescriptor(
            predicates: [.sample(type: HKSampleType.stateOfMindType(), predicate: HKQuery.predicateForSamples(withStart: start, end: end))],
            sortDescriptors: [SortDescriptor(\.startDate)],
            limit: 500
        )
        do {
            return try await query.result(for: store).compactMap { sample in
                (sample as? HKStateOfMind).map { TimedValue(date: $0.startDate, value: $0.valence) }
            }
        } catch let error as HKError where error.code == .errorNoData {
            return []
        }
    }

    private func mindfulMinutes(from start: Date, to end: Date) async throws -> Double? {
        let query = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: HKCategoryType(.mindfulSession), predicate: HKQuery.predicateForSamples(withStart: start, end: end))],
            sortDescriptors: [],
            limit: 200
        )
        do {
            let sessions = try await query.result(for: store)
            guard !sessions.isEmpty else { return nil }
            return sessions.reduce(0) { $0 + $1.endDate.timeIntervalSince($1.startDate) } / 60
        } catch let error as HKError where error.code == .errorNoData {
            return nil
        }
    }

    private func latest(_ identifier: HKQuantityTypeIdentifier, unit: HKUnit) async throws -> MeasurementSample? {
        let query = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: HKQuantityType(identifier))],
            sortDescriptors: [SortDescriptor(\.endDate, order: .reverse)],
            limit: 1
        )
        do {
            return try await query.result(for: store).first.map { MeasurementSample(value: $0.quantity.doubleValue(for: unit), measuredAt: $0.endDate) }
        } catch let error as HKError where error.code == .errorNoData {
            return nil
        }
    }

    // MARK: Queries

    private func hourly(_ identifier: HKQuantityTypeIdentifier, unit: HKUnit, from start: Date, to end: Date) async throws -> [HourlyValue] {
        let query = HKStatisticsCollectionQueryDescriptor(
            predicate: .quantitySample(type: HKQuantityType(identifier), predicate: HKQuery.predicateForSamples(withStart: start, end: end)),
            options: .cumulativeSum,
            anchorDate: start,
            intervalComponents: DateComponents(hour: 1)
        )
        do {
            return try await query.result(for: store).statistics().compactMap { statistics in
                statistics.sumQuantity().map { HourlyValue(start: statistics.startDate, value: $0.doubleValue(for: unit)) }
            }
        } catch let error as HKError where error.code == .errorNoData {
            return []
        }
    }

    private func workouts(from start: Date, to end: Date) async throws -> [Workout] {
        let query = HKSampleQueryDescriptor(
            predicates: [.workout(HKQuery.predicateForSamples(withStart: start, end: end))],
            sortDescriptors: [SortDescriptor(\.endDate, order: .reverse)],
            limit: 200
        )
        do {
            return try await query.result(for: store).map(Self.workout)
        } catch let error as HKError where error.code == .errorNoData {
            return []
        }
    }

    private func latestWeight() async throws -> BodyMassSample? {
        let query = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: HKQuantityType(.bodyMass))],
            sortDescriptors: [SortDescriptor(\.endDate, order: .reverse)],
            limit: 1
        )
        do {
            return try await query.result(for: store).first.map {
                BodyMassSample(kilograms: $0.quantity.doubleValue(for: .gramUnit(with: .kilo)), measuredAt: $0.endDate)
            }
        } catch let error as HKError where error.code == .errorNoData {
            return nil
        }
    }

    private func weights(since start: Date) async throws -> [BodyMassSample] {
        let query = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: HKQuantityType(.bodyMass), predicate: HKQuery.predicateForSamples(withStart: start, end: nil))],
            sortDescriptors: [SortDescriptor(\.endDate)],
            limit: 500
        )
        do {
            return try await query.result(for: store).map {
                BodyMassSample(kilograms: $0.quantity.doubleValue(for: .gramUnit(with: .kilo)), measuredAt: $0.endDate)
            }
        } catch let error as HKError where error.code == .errorNoData {
            return []
        }
    }

    // MARK: Mapping

    private static func workout(_ workout: HKWorkout) -> Workout {
        let type = WorkoutType(workout.workoutActivityType)
        return Workout(
            id: workout.uuid,
            name: type.rawValue,
            type: type,
            durationMinutes: Int((workout.duration / 60).rounded()),
            exercises: [],
            scheduledDate: nil,
            completedAt: workout.endDate,
            notes: nil,
            templateID: nil,
            source: .recorded,
            startedAt: workout.startDate,
            activeEnergyKilocalories: workout.statistics(for: HKQuantityType(.activeEnergyBurned))?
                .sumQuantity()?.doubleValue(for: .kilocalorie()),
            distanceMeters: workout.totalDistance?.doubleValue(for: .meter()),
            deviceName: deviceName(productType: workout.sourceRevision.productType)
        )
    }

    /// The kind of device, never its personal name ("Mark's iPhone").
    private static func deviceName(productType: String?) -> String? {
        guard let productType else { return nil }
        if productType.hasPrefix("Watch") { return "Apple Watch" }
        if productType.hasPrefix("iPhone") { return "iPhone" }
        return nil
    }
}

private extension WorkoutType {
    nonisolated init(_ type: HKWorkoutActivityType) {
        switch type {
        case .walking, .hiking: self = .walking
        case .running: self = .running
        case .cycling: self = .cycling
        case .traditionalStrengthTraining, .functionalStrengthTraining, .coreTraining: self = .strength
        case .highIntensityIntervalTraining: self = .hiit
        case .yoga, .pilates: self = .yoga
        case .flexibility, .preparationAndRecovery, .cooldown: self = .mobility
        case .swimming: self = .swimming
        default: self = .other
        }
    }
}

#if DEBUG
/// Demo data for previews and `-seedSampleData`. Never in Release.
nonisolated struct DemoHealthService: HealthService {
    let snapshot: HealthSnapshot
    /// Every read fails, for the sync error state (D07).
    var fails = false

    var isAvailable: Bool { true }

    func requestAuthorization() async throws {}

    func snapshot(now: Date, calendar: Calendar, stepsTarget: Int) async throws -> HealthSnapshot? {
        if fails { throw URLError(.cannotConnectToHost) }
        var result = snapshot
        result.stepsTarget = stepsTarget
        return result
    }
}
#endif
