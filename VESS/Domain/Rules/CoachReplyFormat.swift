import Foundation

/// A Coach answer as blocks to draw: paragraphs, lists and chart tokens.
/// Inline Markdown (bold, italic) only; lists are handled here, so raw "**"
/// and "* " never reach the screen.
nonisolated enum CoachReplyFormat {
    nonisolated enum Block: Equatable, Sendable {
        case paragraph(AttributedString)
        case list([AttributedString])
        case chart(CoachChartRequest)
    }

    static func blocks(_ reply: String) -> [Block] {
        var blocks: [Block] = []
        var paragraph: [String] = []
        var items: [String] = []

        func flushParagraph() {
            let text = paragraph.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { blocks.append(.paragraph(inline(text))) }
            paragraph = []
        }
        func flushList() {
            if !items.isEmpty { blocks.append(.list(items.map(inline))) }
            items = []
        }

        for rawLine in reply.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                flushParagraph()
                flushList()
            } else if line.hasPrefix("[[") && line.hasSuffix("]]") {
                flushParagraph()
                flushList()
                // Valid tokens become charts; anything else is dropped.
                if let chart = CoachChartRequest(token: line) { blocks.append(.chart(chart)) }
            } else if let item = listItem(line) {
                flushParagraph()
                items.append(item)
            } else {
                flushList()
                paragraph.append(line)
            }
        }
        flushParagraph()
        flushList()
        return blocks
    }

    /// "- item", "* item" or "• item"; "**bold**" at the start isn't a list.
    private static func listItem(_ line: String) -> String? {
        for marker in ["- ", "* ", "• "] where line.hasPrefix(marker) {
            return String(line.dropFirst(marker.count)).trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    /// Bold and italic from inline Markdown; any "**", "__" or tokens the
    /// parser leaves (unbalanced) are removed.
    static func inline(_ text: String) -> AttributedString {
        let cleaned = text.replacingOccurrences(of: #"\[\[[^\]]*\]\]"#, with: "", options: .regularExpression)
        var result = (try? AttributedString(
            markdown: cleaned,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace, failurePolicy: .returnPartiallyParsedIfPossible)
        )) ?? AttributedString(cleaned)
        for marker in ["**", "__"] {
            while let range = result.range(of: marker) { result.removeSubrange(range) }
        }
        return result
    }
}

/// "[[chart:steps:7d]]": a chart the app draws from the user's own data.
/// RANGE is today (a ring card), 7d or 30d (bars, or a line for weight,
/// BMI, resting heart rate, HRV and stress).
nonisolated struct CoachChartRequest: Equatable, Sendable {
    nonisolated enum Metric: String, CaseIterable, Sendable {
        case steps
        case activeEnergy = "active_energy"
        case workouts, energy, protein, carbs, fat, fiber, sugar, water, caffeine, sleep, hrv
        case restingHeartRate = "resting_hr"
        case stress, weight, bmi, habits, supplements

        /// Drawn as a line over days.
        var isLine: Bool {
            switch self {
            case .weight, .bmi, .restingHeartRate, .hrv, .stress: true
            default: false
            }
        }
    }

    let metric: Metric
    /// 1 for today, else 7 or 30.
    let days: Int

    var isToday: Bool { days == 1 }

    init?(token: String) {
        let parts = token.trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
            .split(separator: ":").map(String.init)
        guard parts.count == 3, parts[0] == "chart", let metric = Metric(rawValue: parts[1]) else { return nil }
        switch parts[2] {
        case "today": days = 1
        case "7d": days = 7
        case "30d": days = 30
        default: return nil
        }
        self.metric = metric
    }

    init(metric: Metric, days: Int) {
        self.metric = metric
        self.days = days
    }
}
