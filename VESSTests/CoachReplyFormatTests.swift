import Foundation
import Testing
@testable import VESS

@Suite("Coach answers: Markdown and chart tokens")
struct CoachReplyFormatTests {
    private func text(_ block: CoachReplyFormat.Block) -> String? {
        if case .paragraph(let value) = block { return String(value.characters) }
        return nil
    }

    @Test("Bold and italic are styled; no \"**\" or \"* \" is left")
    func inline() throws {
        let blocks = CoachReplyFormat.blocks("You had **92 g** of protein, *nice*.")
        let first = try #require(blocks.first)
        #expect(text(first) == "You had 92 g of protein, nice.")
        guard case .paragraph(let attributed) = first else { return }
        let bold = attributed.runs.contains { $0.inlinePresentationIntent?.contains(.stronglyEmphasized) == true }
        #expect(bold)
    }

    @Test("\"-\" and \"*\" lines become one list; bold inside items works; unbalanced markers are removed")
    func lists() {
        let blocks = CoachReplyFormat.blocks("Ideas:\n* **Dinner:** cod with rice\n- Lentil soup\n\nEnjoy **it.")
        #expect(blocks.count == 3)
        if case .list(let items) = blocks[1] {
            #expect(items.map { String($0.characters) } == ["Dinner: cod with rice", "Lentil soup"])
        } else {
            Issue.record("Expected a list")
        }
        #expect(text(blocks[2]) == "Enjoy it.")
    }

    @Test("Valid chart tokens on their own line become charts; invalid or unknown ones disappear")
    func charts() {
        let blocks = CoachReplyFormat.blocks("Steps this week:\n[[chart:steps:7d]]\n[[chart:blood_sugar:7d]]\n[[chart:steps:90d]]\nKeep going [[chart:water:7d]] today.")
        #expect(blocks.count == 3)
        #expect(blocks[1] == .chart(CoachChartRequest(metric: .steps, days: 7)))
        #expect(text(blocks[2]) == "Keep going  today.", "An inline token is removed, not drawn")
        #expect(CoachChartRequest(token: "[[chart:resting_hr:30d]]") == CoachChartRequest(metric: .restingHeartRate, days: 30))
    }
}

@Suite("Coach: every chart token and rotating prompts")
struct CoachTokenTests {
    @Test("All 19 metrics and today / 7d / 30d parse; anything else is dropped")
    func tokens() {
        let metrics = ["steps", "active_energy", "workouts", "energy", "protein", "carbs", "fat", "fiber", "sugar", "water", "caffeine",
                       "sleep", "hrv", "resting_hr", "stress", "weight", "bmi", "habits", "supplements"]
        #expect(CoachChartRequest.Metric.allCases.count == metrics.count)
        for metric in metrics {
            for range in ["today", "7d", "30d"] {
                #expect(CoachChartRequest(token: "[[chart:\(metric):\(range)]]") != nil, "\(metric):\(range)")
            }
        }
        #expect(CoachChartRequest(token: "[[chart:sleep:today]]")?.isToday == true)
        #expect(CoachChartRequest(token: "[[chart:mood:7d]]") == nil)
        #expect(CoachChartRequest(token: "[[chart:steps:1y]]") == nil)
    }

    @Test("Lines for weight, BMI, resting heart rate, HRV and stress; bars for the rest")
    func styles() {
        let lines = CoachChartRequest.Metric.allCases.filter(\.isLine)
        #expect(Set(lines) == [.weight, .bmi, .restingHeartRate, .hrv, .stress])
    }

    @Test("Prompts: the dinner question first, then metrics with data, moving on with the rotation")
    func rotation() {
        let candidates = [CoachPrompts.Candidate(metric: .sleep, question: "Sleep?"),
                          .init(metric: .steps, question: "Steps?"),
                          .init(metric: .water, question: "Water?"),
                          .init(metric: .stress, question: "Stress?")]
        #expect(CoachPrompts.pick(first: ["Cook?"], candidates: candidates, rotation: 0) == ["Cook?", "Sleep?", "Steps?"])
        #expect(CoachPrompts.pick(first: [], candidates: candidates, rotation: 1) == ["Steps?", "Water?", "Stress?"])
        #expect(CoachPrompts.pick(first: [], candidates: candidates, rotation: 3) == ["Stress?", "Sleep?", "Steps?"], "Wraps around")
        #expect(CoachPrompts.pick(first: [], candidates: [], rotation: 5).count == 3, "General questions fill in")
    }
}
