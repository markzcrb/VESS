import Foundation

/// Daily AI uses, free and with UMEVA+, for display only: the paywall and
/// its comparison sheet, and when the app is offline before the server
/// has answered. What the app actually allows comes from the server
/// (`PlanStore`, from the `entitlement` function), never from here. Keep
/// these equal to the server's `ai_user_daily_limit`.
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
