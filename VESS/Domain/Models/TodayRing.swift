import Foundation

/// One ring the user can show in Today's strip, in their order.
nonisolated enum TodayRing: String, CaseIterable, Codable, Sendable {
    case fuel, energy, protein, carbs, fat, fiber, water, caffeine
    case steps, activeEnergy
    case sleep, restingHeartRate, hrv, cycleDay
    case stress, habits

    /// The groups of the Edit rings sheet's Add list.
    nonisolated enum Group: CaseIterable, Sendable {
        case nutrition, activity, body, mind
    }

    var group: Group {
        switch self {
        case .fuel, .energy, .protein, .carbs, .fat, .fiber, .water, .caffeine: .nutrition
        case .steps, .activeEnergy: .activity
        case .sleep, .restingHeartRate, .hrv, .cycleDay: .body
        case .stress, .habits: .mind
        }
    }

    /// Read from Apple Health: "—" until Health has data.
    var isHealth: Bool {
        switch self {
        case .steps, .activeEnergy, .sleep, .restingHeartRate, .hrv, .stress: true
        default: false
        }
    }
}

/// The strip's rules: which rings, in what order, within 1…12.
nonisolated enum TodayRingRules {
    static let defaultRings: [TodayRing] = [.fuel, .energy, .protein, .water, .steps]
    static let minimum = 1
    static let maximum = 12
    /// No fibre target is set anywhere yet; 30 g a day is the usual adult
    /// guideline (DGE), used for the Fiber ring only.
    static let fiberTargetGrams = 30.0

    /// Rings that can be chosen; Cycle day only while cycle tracking is on.
    static func available(cycleTrackingOn: Bool) -> [TodayRing] {
        TodayRing.allCases.filter { $0 != .cycleDay || cycleTrackingOn }
    }

    /// The stored choice made safe to show: unknown or repeated rings and
    /// Cycle day (while tracking is off) dropped, at most 12, and the
    /// default when nothing is left. `nil` (every profile from before) is
    /// the default.
    static func rings(stored: [String]?, cycleTrackingOn: Bool) -> [TodayRing] {
        guard let stored else { return defaultRings }
        var seen: Set<TodayRing> = []
        let rings = stored.compactMap(TodayRing.init(rawValue:)).filter { ring in
            guard ring != .cycleDay || cycleTrackingOn else { return false }
            return seen.insert(ring).inserted
        }
        return rings.isEmpty ? defaultRings : Array(rings.prefix(maximum))
    }

    static func canAdd(_ rings: [TodayRing]) -> Bool { rings.count < maximum }
    static func canRemove(_ rings: [TodayRing]) -> Bool { rings.count > minimum }

    static func adding(_ ring: TodayRing, to rings: [TodayRing]) -> [TodayRing] {
        guard canAdd(rings), !rings.contains(ring) else { return rings }
        return rings + [ring]
    }

    static func removing(_ ring: TodayRing, from rings: [TodayRing]) -> [TodayRing] {
        guard canRemove(rings) else { return rings }
        return rings.filter { $0 != ring }
    }
}
