import Foundation

/// Longest text the app sends off the iPhone. The server trims too (Coach
/// keeps 4 000 characters a message); these keep requests small and
/// predictable before they leave.
nonisolated enum InputLimits {
    static let coachQuestion = 2_000
    static let foodSearch = 100
    /// RFC 5321's limit for an address.
    static let email = 254

    static func clamp(_ text: String, to limit: Int) -> String {
        text.count > limit ? String(text.prefix(limit)) : text
    }
}
