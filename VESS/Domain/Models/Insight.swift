import Foundation

/// A short, data-backed observation shown to the user.
///
/// Insights come from deterministic rules over logged data. AI may rephrase
/// them, but never invents the numbers. Copy describes patterns ("On days
/// when…", "You tend to…") and never claims causation.
nonisolated struct Insight: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    /// Stable identifier of the rule that produced this insight, such as
    /// "nutrition.protein_target_streak". Used for de-duplication and analytics.
    var ruleID: String
    var title: String
    var body: String
    var severity: InsightSeverity
    var category: InsightCategory
    var dataSource: InsightDataSource
    let createdAt: Date
    /// After this date the insight is no longer relevant and is hidden.
    var expiresAt: Date?
}

nonisolated enum InsightSeverity: String, Codable, Sendable {
    /// Neutral information.
    case informational
    /// Progress worth acknowledging.
    case positive
    /// Something the user may want to act on, such as food expiring.
    case attention
}

nonisolated enum InsightCategory: String, Codable, CaseIterable, Sendable {
    case nutrition
    case hydration
    case activity
    case energy
    case food
    case budget
    case consistency
}

nonisolated enum InsightDataSource: String, Codable, Sendable {
    /// Produced on device by a deterministic rule.
    case rule
    /// A rule-produced insight rephrased by `AIService`.
    case aiAssisted
    /// Derived from Apple Health data.
    case appleHealth
}
