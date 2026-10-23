import Foundation

/// Supplements for a day and the presets offered when adding one (22).
/// VESS records the user's own choices: presets carry a name, a category
/// and a unit, never a dose, a recommendation or a claim.
nonisolated enum SupplementRules {
    /// A preset to pick: name, category and the unit it's usually counted in.
    struct Preset: Equatable, Sendable {
        let name: String
        let category: SupplementCategory
        let unit: SupplementUnit
    }

    /// One tap to pick; the user enters the dose.
    static let presets: [Preset] = [
        Preset(name: "Vitamin D3", category: .vitamins, unit: .internationalUnit),
        Preset(name: "Vitamin B12", category: .vitamins, unit: .microgram),
        Preset(name: "Multivitamin", category: .vitamins, unit: .tablet),
        Preset(name: "Magnesium", category: .minerals, unit: .milligram),
        Preset(name: "Zinc", category: .minerals, unit: .milligram),
        Preset(name: "Iron", category: .minerals, unit: .milligram),
        Preset(name: "Omega-3", category: .omega3, unit: .capsule),
        Preset(name: "Creatine", category: .performance, unit: .gram),
        Preset(name: "Protein powder", category: .performance, unit: .gram),
    ]

    /// Whether a supplement is due on `day`. As-needed ones never are.
    static func isScheduled(_ supplement: Supplement, on day: Date, calendar: Calendar) -> Bool {
        switch supplement.schedule {
        case .daily: return true
        case .asNeeded: return false
        case .weekdays(let days):
            return days.contains(weekday(of: day, calendar: calendar))
        }
    }

    /// The Gregorian weekday number (1 = Sunday) as a `Locale.Weekday`.
    static func weekday(of day: Date, calendar: Calendar) -> Locale.Weekday {
        let all: [Locale.Weekday] = [.sunday, .monday, .tuesday, .wednesday, .thursday, .friday, .saturday]
        return all[(calendar.component(.weekday, from: day) - 1) % 7]
    }

    /// A row in today's list: taken (with the time) or still to log.
    struct Item: Equatable, Sendable {
        let supplement: Supplement
        let takenAt: Date?
    }

    struct Today: Equatable, Sendable {
        let items: [Item]
        /// "2 of 4 taken": due today, and taken today.
        let dueCount: Int
        let takenCount: Int
    }

    /// Due today, plus anything taken today that wasn't due (as-needed, or
    /// another day's), in time-of-day order: morning, with a meal, evening.
    static func today(_ supplements: [Supplement], logs: [SupplementLog], on day: Date, calendar: Calendar) -> Today {
        let todays = logs.filter { calendar.isDate($0.takenAt, inSameDayAs: day) }
        let taken = Dictionary(todays.map { ($0.supplementID, $0.takenAt) }, uniquingKeysWith: min)
        let listed = supplements.filter { isScheduled($0, on: day, calendar: calendar) || taken[$0.id] != nil }
        let ordered = listed.enumerated().sorted { lhs, rhs in
            let left = order(lhs.element), right = order(rhs.element)
            return left == right ? lhs.offset < rhs.offset : left < right
        }.map(\.element)
        let due = listed.filter { isScheduled($0, on: day, calendar: calendar) }
        return Today(
            items: ordered.map { Item(supplement: $0, takenAt: taken[$0.id]) },
            dueCount: due.count,
            takenCount: due.filter { taken[$0.id] != nil }.count
        )
    }

    private static func order(_ supplement: Supplement) -> Int {
        switch supplement.timeOfDay {
        case .morning: 0
        case .withMeal: 1
        case .custom: 2
        case .evening: 3
        case nil: 4
        }
    }

    /// The presets of a category. The user's own supplements of the same
    /// name come first ("Recent"); matching ignores case and spacing.
    static func presets(in category: SupplementCategory, mine: [Supplement]) -> [(preset: Preset, existing: Supplement?)] {
        let list = presets.filter { $0.category == category }.map { preset in
            (preset: preset, existing: mine.first { key($0.name) == key(preset.name) })
        }
        return list.filter { $0.existing != nil } + list.filter { $0.existing == nil }
    }

    /// The user's supplements with no matching preset, shown in their category.
    static func ownOnly(in category: SupplementCategory, mine: [Supplement]) -> [Supplement] {
        let presetKeys = Set(presets.map { key($0.name) })
        return mine.filter { ($0.category ?? .other) == category && !presetKeys.contains(key($0.name)) }
    }

    /// Search across every preset and the user's own supplements.
    static func search(_ query: String, mine: [Supplement]) -> (presets: [Preset], mine: [Supplement]) {
        let needle = key(query)
        guard !needle.isEmpty else { return ([], []) }
        let mineMatches = mine.filter { key($0.name).contains(needle) }
        let mineKeys = Set(mineMatches.map { key($0.name) })
        return (presets.filter { key($0.name).contains(needle) && !mineKeys.contains(key($0.name)) }, mineMatches)
    }

    /// "Omega 3", "omega-3" and "Omega3" match.
    static func key(_ name: String) -> String {
        name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .filter { $0.isLetter || $0.isNumber }
    }
}
