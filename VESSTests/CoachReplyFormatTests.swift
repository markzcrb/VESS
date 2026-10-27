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
