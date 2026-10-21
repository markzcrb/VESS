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

    private var readTypes: Set<HKObjectType> {
        [HKQuantityType(.stepCount), HKQuantityType(.activeEnergyBurned), HKQuantityType(.bodyMass), HKObjectType.workoutType()]
    }

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
        let (hourlySteps, hourlyEnergy, recorded, latestWeight) = try await (steps, energy, workouts, weight)

        guard !hourlySteps.isEmpty || !hourlyEnergy.isEmpty || !recorded.isEmpty else { return nil }
        return HealthSnapshot(
            steps: Int(ActivityTrends.total(hourlySteps, on: now, calendar: calendar) ?? 0),
            stepsTarget: stepsTarget,
            activeEnergyKilocalories: ActivityTrends.total(hourlyEnergy, on: now, calendar: calendar),
            updatedAt: now,
            hourlySteps: hourlySteps,
            hourlyActiveEnergy: hourlyEnergy,
            workouts: recorded,
            latestWeight: latestWeight
        )
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
