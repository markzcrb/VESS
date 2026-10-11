import Foundation

// Copy for the Day Word and its supporting sentence. Calm and factual:
// never "over budget", never red, never cause-and-effect claims.

extension DayWord {
    var title: LocalizedStringResource {
        switch self {
        case .freshStart: "Fresh start"
        case .onTrack: "On track"
        case .lightSoFar: "Light so far"
        case .fullDay: "Full day"
        }
    }
}

extension DaySummary {
    /// One plain sentence that explains the day. The exact numbers follow
    /// directly below it, so the sentence describes rather than repeats them,
    /// for example "Eating in step with the day. Protein is behind."
    var sentence: String {
        let lead: String
        switch dayWord {
        case .freshStart:
            return String(localized: "Nothing logged yet. Start whenever you're ready.")
        case .onTrack:
            lead = String(localized: "Eating in step with the day.")
        case .lightSoFar:
            lead = String(localized: "Less than expected by this time of day.")
        case .fullDay:
            let above = consumed.calories - targets.calories
            lead = above > 25
                ? String(localized: "\(VESSFormat.calories(above)) kcal above your target.")
                : String(localized: "Right at your target.")
        }
        return [lead, lagSentence].compactMap(\.self).joined(separator: " ")
    }

    private var lagSentence: String? {
        switch (isProteinBehind, isWaterBehind) {
        case (true, true): String(localized: "Protein and water are behind.")
        case (true, false): String(localized: "Protein is behind.")
        case (false, true): String(localized: "Water is behind.")
        case (false, false): expectedPace >= 0.25 && dayWord != .fullDay
            ? String(localized: "Protein and water are on pace.")
            : nil
        }
    }
}

enum Greeting {
    static func text(for date: Date, name: String, calendar: Calendar) -> String {
        let hour = calendar.component(.hour, from: date)
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        switch (hour, trimmed.isEmpty) {
        case (5..<12, false): return String(localized: "Good morning, \(trimmed)")
        case (12..<17, false): return String(localized: "Good afternoon, \(trimmed)")
        case (_, false): return String(localized: "Good evening, \(trimmed)")
        case (5..<12, true): return String(localized: "Good morning")
        case (12..<17, true): return String(localized: "Good afternoon")
        case (_, true): return String(localized: "Good evening")
        }
    }
}
