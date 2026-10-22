#if DEBUG
import Foundation

extension MockData {
    /// SAMPLE cycle history for captures (`-cycleOn`). Relative to `now`:
    /// the current period started five days ago, so today is cycle day 6,
    /// after six completed cycles of 28–31 days (average 29). Today has
    /// bloating logged and no flow, like reference 13.
    static func cycleDays(now: Date, calendar: Calendar) -> [CycleDay] {
        let today = calendar.startOfDay(for: now)
        let lastStart = calendar.date(byAdding: .day, value: -5, to: today) ?? today
        // Oldest first, then the current cycle's period.
        let lengths = [28, 30, 29, 31, 28, 29]
        let periodLengths = [5, 6, 5, 5, 6, 5, 5]
        var starts = [lastStart]
        for length in lengths.reversed() {
            starts.insert(calendar.date(byAdding: .day, value: -length, to: starts[0]) ?? lastStart, at: 0)
        }

        var days: [CycleDay] = []
        for (index, start) in starts.enumerated() {
            for offset in 0..<periodLengths[index] {
                guard let day = calendar.date(byAdding: .day, value: offset, to: start) else { continue }
                let flow: CycleFlow = switch offset {
                case 0: .medium
                case 1: .heavy
                case 2: .medium
                default: .light
                }
                let symptoms: Set<CycleSymptom> = offset == 0 ? [.cramps, .fatigue] : (offset == 1 ? [.cramps] : [])
                days.append(CycleDay(id: UUID(), day: day, flow: flow, symptoms: symptoms, note: nil))
            }
        }
        days.append(CycleDay(id: UUID(), day: today, flow: .none, symptoms: [.bloating], note: nil))
        return days
    }
}
#endif
