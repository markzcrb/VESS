#if DEBUG
import Foundation

/// `-aiMock`: canned answers from "the server", so captures and UI tests never
/// need the network or an account. `-aiMockScenario <name>` picks one:
/// `ok` (default), `limit` (429), `offline`, `upstream` (502),
/// `notConfigured` (503), `empty` (photo finds no food), `lowConfidence`,
/// `chefConflict` (the chef's draft uses soy sauce, for the on-device check).
/// `-aiMockSignedOut` starts signed out; any email code but 000000 works.
nonisolated struct AIMockTransport: HTTPTransport {
    enum Scenario: String, Sendable {
        case ok, limit, offline, upstream, notConfigured, empty, lowConfidence, chefConflict
    }

    let scenario: Scenario

    static func fromLaunchArguments(_ arguments: [String]) -> AIMockTransport {
        let name = arguments.firstIndex(of: "-aiMockScenario").flatMap { arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil }
        return AIMockTransport(scenario: name.flatMap(Scenario.init(rawValue:)) ?? .ok)
    }

    /// The session a signed-in mock starts with.
    static let session = AuthSession(
        accessToken: "mock-access", refreshToken: "mock-refresh",
        expiresAt: Date().addingTimeInterval(3600), userID: "00000000-0000-0000-0000-000000000001",
        email: "mark@example.com", provider: "email"
    )

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try await Task.sleep(for: .milliseconds(450))
        let path = request.url?.path() ?? ""
        if scenario == .offline, path.contains("/functions/") { throw URLError(.notConnectedToInternet) }

        switch true {
        case path.hasSuffix("/auth/v1/otp"):
            return reply(200, [:])
        case path.hasSuffix("/auth/v1/verify"):
            let body = (try? JSONSerialization.jsonObject(with: request.httpBody ?? Data())) as? [String: Any]
            if body?["token"] as? String == "000000" {
                return reply(403, ["error_code": "otp_expired", "msg": "Token has expired or is invalid"])
            }
            return reply(200, sessionJSON(email: body?["email"] as? String ?? "mark@example.com", provider: "email"))
        case path.hasSuffix("/auth/v1/token"):
            let provider = request.url?.query()?.contains("id_token") == true ? "apple" : "email"
            return reply(200, sessionJSON(email: provider == "apple" ? "privaterelay@appleid.example" : "mark@example.com", provider: provider))
        case path.hasSuffix("/auth/v1/logout"):
            return reply(204, [:])
        case path.hasSuffix("/functions/v1/delete-account"):
            return reply(200, ["deleted": true])
        case path.contains("/functions/v1/"):
            return functionReply(path)
        // Today's usage: two AI Chef recipes so far, ten a day.
        case path.hasSuffix("/rest/v1/ai_usage"):
            return rawReply(200, scenario == .limit ? #"[{"count":10}]"# : #"[{"count":2}]"#)
        case path.hasSuffix("/rest/v1/rpc/ai_daily_limit"):
            return rawReply(200, "10")
        default:
            return reply(404, ["error": "not_found"])
        }
    }

    private func functionReply(_ path: String) -> (Data, HTTPURLResponse) {
        switch scenario {
        case .limit: return reply(429, ["error": "daily_limit", "remaining": 0])
        case .upstream: return reply(502, ["error": "upstream"])
        case .notConfigured: return reply(503, ["error": "not_configured"])
        default: break
        }
        if path.hasSuffix("/coach") {
            return reply(200, [
                "reply": "Protein is a little under your target so far, with dinner still to come. The miso cod you planned would bring it close to your 140 g target. Water is a little behind your usual pace for this time of day. (Sample answer.)",
                "remaining": 17,
            ])
        }
        if path.hasSuffix("/chef") {
            func ingredient(_ name: String, _ amount: Double, _ unit: String, _ grams: Double, _ hint: String) -> [String: Any] {
                ["name": name, "amount": amount, "unit": unit, "grams": grams, "from_pantry": true, "usda_hint": hint]
            }
            var ingredients = [
                ingredient("Jasmine rice", 150, "g", 150, "Rice, white, long-grain, regular, raw"),
                ingredient("Bok choy", 2, "piece", 250, "Cabbage, chinese (pak-choi), raw"),
                ingredient("Baby spinach", 100, "g", 100, "Spinach, raw"),
                ingredient("Eggs", 4, "piece", 200, "Egg, whole, raw, fresh"),
                ingredient("White miso", 1, "tbsp", 17, "Miso"),
                ingredient("Spring onions", 2, "piece", 30, "Onions, spring or scallions, raw"),
            ]
            if scenario == .chefConflict {
                ingredients.append(ingredient("Soy sauce", 1, "tbsp", 16, "Soy sauce made from soy and wheat (shoyu)"))
            }
            return reply(200, [
                "recipe": [
                    "name": "Bok choy, spinach and miso egg rice", "minutes": 20, "servings": 2,
                    "ingredients": ingredients,
                    "steps": [
                        "Rinse and cook the rice. Meanwhile halve the bok choy.",
                        "Whisk the miso with a splash of hot water.",
                        "Fry the eggs. Wilt the bok choy and spinach in the same pan, 2 minutes.",
                        "Spoon the greens and eggs over the rice, drizzle the miso and top with spring onions.",
                    ],
                    "tip": "Day-old rice fries best.",
                ],
                "remaining": 7,
                "estimated": true,
            ])
        }
        if path.hasSuffix("/food-photo") {
            if scenario == .empty {
                return reply(200, ["items": [Any](), "note": "No food visible.", "remaining": 8, "estimated": true])
            }
            let low = scenario == .lowConfidence
            return reply(200, [
                "items": [
                    ["name": "Grilled salmon", "amount": 150, "unit": "g", "kcal": 312, "protein_g": 34, "carbs_g": 0, "fat_g": 19, "confidence": "high"],
                    ["name": "Brown rice, cooked", "amount": 180, "unit": "g", "kcal": 202, "protein_g": 4.7, "carbs_g": 42, "fat_g": 1.6, "confidence": low ? "medium" : "high"],
                    ["name": "Sesame dressing", "amount": 15, "unit": "g", "kcal": 68, "protein_g": 0.5, "carbs_g": 2.1, "fat_g": 6.4, "confidence": low ? "low" : "medium"],
                ],
                "note": low ? "The dressing is hard to see; check its amount." : "",
                "remaining": 9,
                "estimated": true,
            ])
        }
        return reply(404, ["error": "not_found"])
    }

    private func sessionJSON(email: String, provider: String) -> [String: Any] {
        [
            "access_token": "mock-access-\(UUID().uuidString)",
            "refresh_token": "mock-refresh-\(UUID().uuidString)",
            "token_type": "bearer",
            "expires_in": 3600,
            "expires_at": Date().addingTimeInterval(3600).timeIntervalSince1970,
            "user": ["id": Self.session.userID, "email": email, "app_metadata": ["provider": provider]],
        ]
    }

    private func rawReply(_ status: Int, _ body: String) -> (Data, HTTPURLResponse) {
        let response = HTTPURLResponse(url: URL(string: "https://mock.vess.invalid")!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
        return (Data(body.utf8), response)
    }

    private func reply(_ status: Int, _ body: [String: Any]) -> (Data, HTTPURLResponse) {
        let data = (try? JSONSerialization.data(withJSONObject: body)) ?? Data()
        let response = HTTPURLResponse(url: URL(string: "https://mock.vess.invalid")!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
        return (data, response)
    }
}
#endif
