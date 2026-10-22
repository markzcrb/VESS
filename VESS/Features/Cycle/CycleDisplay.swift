import SwiftUI

// Names and shared copy for cycle tracking.

extension CycleFlow {
    var title: LocalizedStringResource {
        switch self {
        case .none: "None"
        case .spotting: "Spotting"
        case .light: "Light"
        case .medium: "Medium"
        case .heavy: "Heavy"
        }
    }
}

extension CycleSymptom {
    var title: LocalizedStringResource {
        switch self {
        case .cramps: "Cramps"
        case .headache: "Headache"
        case .bloating: "Bloating"
        case .fatigue: "Fatigue"
        case .lowMood: "Low mood"
        case .backPain: "Back pain"
        case .cravings: "Cravings"
        }
    }
}

enum CycleCopy {
    /// Shown on the Cycle screen, always.
    static let disclaimer: LocalizedStringResource = "Estimates can be off. This is not medical advice and not contraception. Cycle data stays on this iPhone."
    /// Shown under the day form.
    static let storage: LocalizedStringResource = "Saved only on this iPhone. Not shared with Apple Health."
    /// Fewer than two completed cycles.
    static let needsMore: LocalizedStringResource = "Log two periods to see an estimate"
    /// The Today row and Cycle screen icon.
    static let symbol = "calendar"

    /// "4–7 November", or "29 October – 1 November" across months.
    static func window(_ estimate: CyclePrediction.Estimate, calendar: Calendar) -> String {
        let start = estimate.windowStart
        let end = estimate.windowEnd
        let sameMonth = calendar.isDate(start, equalTo: end, toGranularity: .month)
        let startText = sameMonth
            ? start.formatted(.dateTime.day())
            : start.formatted(.dateTime.day().month(.wide))
        // Non-breaking spaces keep "29 October" on one line.
        return "\(startText)–\(end.formatted(.dateTime.day().month(.wide)))".replacingOccurrences(of: " ", with: "\u{00A0}")
    }

    /// The Today row and the ring caption.
    static func nextText(_ summary: CyclePrediction.Summary) -> Text {
        guard summary.estimate != nil, let days = summary.daysUntilExpected else { return Text(needsMore) }
        if summary.isPastWindow { return Text("Later than the estimate") }
        if days <= 0 { return Text("Next period likely around now") }
        return Text("Next period in about ^[\(days) day](inflect: true)")
    }
}

/// Flow chips: one choice.
struct CycleFlowChips: View {
    @Binding var flow: CycleFlow

    var body: some View {
        VESSChipFlow {
            ForEach(CycleFlow.allCases, id: \.self) { option in
                VESSChip(title: option.title, isSelected: flow == option) { flow = option }
                    .accessibilityIdentifier("cycle.flow.\(option.rawValue)")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Flow")
    }
}

/// Symptom chips: any number.
struct CycleSymptomChips: View {
    @Binding var symptoms: Set<CycleSymptom>

    var body: some View {
        VESSChipFlow {
            ForEach(CycleSymptom.allCases, id: \.self) { symptom in
                VESSChip(title: symptom.title, isSelected: symptoms.contains(symptom)) {
                    if symptoms.contains(symptom) { symptoms.remove(symptom) } else { symptoms.insert(symptom) }
                }
                .accessibilityIdentifier("cycle.symptom.\(symptom.rawValue)")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Symptoms")
    }
}
