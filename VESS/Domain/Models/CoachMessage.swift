import Foundation

/// One turn in the Coach conversation. Kept on this iPhone only; the server
/// gets the last 20 with each question and keeps none of them.
nonisolated struct CoachMessage: Identifiable, Codable, Hashable, Sendable {
    enum Role: String, Codable, Sendable { case user, assistant }

    let id: UUID
    var role: Role
    var text: String
    var createdAt: Date
}
