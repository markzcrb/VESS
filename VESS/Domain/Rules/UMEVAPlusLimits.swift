import Foundation

/// Daily AI uses, free and with UMEVA+. The one place these numbers live:
/// the paywall, its comparison sheet and the UMEVA+ welcome read them.
/// They must match the server's `ai_daily_limit` per tier, which Mark sets.
/// (The server has no paid tier yet; today it gives everyone its beta
/// limits, so these are what the app promises, not what it enforces.)
nonisolated enum UMEVAPlusLimits {
    struct Tier: Equatable, Sendable {
        let coachQuestions: Int
        let photoEstimates: Int
        let chefRecipes: Int
    }

    static let free = Tier(coachQuestions: 3, photoEstimates: 1, chefRecipes: 1)
    static let plus = Tier(coachQuestions: 15, photoEstimates: 10, chefRecipes: 5)
    /// Insights history without UMEVA+, in days.
    static let freeInsightsDays = 30
}
