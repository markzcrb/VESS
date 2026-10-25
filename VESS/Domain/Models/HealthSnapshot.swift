import Foundation

/// What Apple Health reported most recently. Read-only: VESS never writes
/// to Health yet, and never estimates steps.
nonisolated struct HealthSnapshot: Equatable, Sendable {
    var steps: Int
    /// The user's step goal.
    var stepsTarget: Int
    var activeEnergyKilocalories: Double?
    /// When Health last delivered these values.
    var updatedAt: Date
    /// Steps per hour, oldest first, for history and comparisons. Hours
    /// without samples are absent, so a day with no entries has no data.
    var hourlySteps: [HourlyValue] = []
    /// Active energy (kcal) per hour, like `hourlySteps`.
    var hourlyActiveEnergy: [HourlyValue] = []
    /// Workouts recorded in Apple Health, newest first.
    var workouts: [Workout] = []
    /// The latest body mass in Apple Health.
    var latestWeight: BodyMassSample? = nil
    /// Body mass over the last 12 weeks, oldest first.
    var weights: [BodyMassSample] = []
    /// Sleep analysis over the last six weeks, from every source.
    var sleep: [SleepSample] = []
    /// Resting heart rate per day (bpm), oldest first.
    var restingHeartRate: [DailyValue] = []
    /// Heart rate variability (SDNN, ms) samples, oldest first.
    var heartRateVariability: [TimedValue] = []
    /// Walking heart rate average per day (bpm).
    var walkingHeartRate: [DailyValue] = []
    /// Today's heart rate, lowest and highest per hour.
    var heartRateToday: [HourlyRange] = []
    /// State of Mind entries (read only), oldest first.
    var stateOfMind: [TimedValue] = []
    /// Mindful minutes today; `nil` when Health has none.
    var mindfulMinutesToday: Double? = nil
    /// The latest body fat, in percent.
    var bodyFat: MeasurementSample? = nil
    /// The latest waist circumference, in cm.
    var waist: MeasurementSample? = nil

    /// 0...1 of the step goal.
    var stepsFraction: Double {
        stepsTarget > 0 ? min(Double(steps) / Double(stepsTarget), 1) : 0
    }
}

/// A sum over one hour, starting at `start`.
nonisolated struct HourlyValue: Equatable, Sendable {
    let start: Date
    let value: Double
}

nonisolated struct BodyMassSample: Equatable, Sendable {
    let kilograms: Double
    let measuredAt: Date
}

/// One sleep analysis sample from Apple Health.
nonisolated struct SleepSample: Equatable, Sendable {
    nonisolated enum Stage: String, Sendable {
        case inBed, asleep, core, deep, rem, awake

        /// Counts toward time asleep.
        var isAsleep: Bool { self == .asleep || self == .core || self == .deep || self == .rem }
    }

    let start: Date
    let end: Date
    let stage: Stage
    /// Recorded by an Apple Watch; preferred where sources overlap.
    let isWatch: Bool
}

/// One value for a day (its start).
nonisolated struct DailyValue: Equatable, Sendable {
    let day: Date
    let value: Double
}

/// One value at a moment.
nonisolated struct TimedValue: Equatable, Sendable {
    let date: Date
    let value: Double
}

/// The lowest and highest value within an hour.
nonisolated struct HourlyRange: Equatable, Sendable {
    let start: Date
    let min: Double
    let max: Double
}

/// A body measurement with when it was taken.
nonisolated struct MeasurementSample: Equatable, Sendable {
    let value: Double
    let measuredAt: Date
}

/// The state of the Apple Health connection, as screens show it.
nonisolated enum HealthSyncState: Equatable, Sendable {
    /// No permission yet: steps show "—" (S4).
    case notConnected
    /// Asked, but Health shared nothing: either access was turned off or
    /// there is no data. Health doesn't say which, so screens show "—".
    case nothingShared
    /// The first read is in progress (S2).
    case syncing
    case available(HealthSnapshot)
    /// The last read failed; the last known values stay visible (D07).
    case failed(lastKnown: HealthSnapshot?)

    /// The values to show, if any.
    var snapshot: HealthSnapshot? {
        switch self {
        case .available(let snapshot): snapshot
        case .failed(let lastKnown): lastKnown
        case .notConnected, .nothingShared, .syncing: nil
        }
    }
}
