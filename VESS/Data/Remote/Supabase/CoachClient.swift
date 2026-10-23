import Foundation

/// `200 { reply, remaining }` from the coach function.
nonisolated struct CoachReply: Decodable, Equatable, Sendable {
    let reply: String
    let remaining: Int?
}

/// The coach request: the last 20 messages (starting with a question and
/// ending with the new one), the context summary and the language.
nonisolated enum CoachRequest {
    static let maxMessages = 20

    static func messages(_ history: [CoachMessage]) -> [CoachMessage] {
        var recent = Array(history.suffix(maxMessages))
        // The server wants the first and last turns to be the user's.
        while recent.first?.role == .assistant { recent.removeFirst() }
        while recent.last?.role == .assistant { recent.removeLast() }
        return recent
    }

    static func body(history: [CoachMessage], context: CoachContext, locale: String) -> Data {
        let messages = messages(history).map { ["role": $0.role.rawValue, "content": $0.text] }
        let contextObject = (try? JSONSerialization.jsonObject(with: CoachContextBuilder.json(context))) ?? [String: Any]()
        let body: [String: Any] = ["messages": messages, "context": contextObject, "locale": locale]
        return (try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])) ?? Data("{}".utf8)
    }

    /// "en", "de", "sk"…: the language Coach answers in.
    static var locale: String {
        Locale.current.language.languageCode?.identifier ?? "en"
    }
}
