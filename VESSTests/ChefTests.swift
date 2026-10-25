import Foundation
import Testing
@testable import VESS

@Suite("AI Chef: request, draft and limits")
struct ChefTests {
    private let calendar = TestClock.utc
    static let index = GenericFoodIndex(foods: Array(MockData.genericFoods.values))

    private let mark = NutritionPreferences(diet: .pescatarian, alsoPrefer: [.highProtein], avoidIngredients: ["Coriander", "Mushrooms"])

    private func item(_ name: String, expiresIn days: Int? = nil, now: Date, chosen: String? = nil) -> InventoryItem {
        var item = InventoryItem(
            id: UUID(), name: name, quantity: 1, unit: .piece, purchaseDate: nil,
            expirationDate: days.flatMap { calendar.date(byAdding: .day, value: $0, to: now) },
            category: .other, location: .fridge, notes: nil, status: .available, reminderSnoozedUntil: nil
        )
        item.genericFoodID = chosen
        return item
    }

    private func response(_ ingredients: [ChefResponse.Ingredient], servings: Int = 2) -> ChefResponse {
        ChefResponse(
            recipe: .init(name: "Draft", minutes: 20, servings: servings, ingredients: ingredients, steps: ["Cook."], tip: nil),
            remaining: 7
        )
    }

    private func ingredient(_ name: String, _ amount: Double, _ unit: String, grams: Double, hint: String?) -> ChefResponse.Ingredient {
        ChefResponse.Ingredient(name: name, amount: amount, unit: unit, grams: grams, fromPantry: true, usdaHint: hint)
    }

    private func build(_ response: ChefResponse, allergies: Set<Allergen> = [.nuts, .peanuts], pantry: [InventoryItem] = [], preferences: NutritionPreferences? = nil) -> ChefDraftBuilder.Outcome {
        ChefDraftBuilder.build(
            response, meal: .dinner, preferences: preferences ?? mark, allergies: allergies, pantry: pantry,
            search: { Self.index.search($0, limit: 1).first }, food: { MockData.genericFoods[$0] }
        )
    }

    // MARK: Request

    @Test("Only the listed fields are sent, in the server's names")
    func requestFields() throws {
        let now = try TestClock.date(2026, 10, 6, 18, 40)
        let pantry = [item("Baby spinach", expiresIn: 1, now: now), item("Rice", now: now), item("Old milk", expiresIn: -2, now: now)]
        let request = ChefRequest.make(
            pantry: pantry, mustUse: [pantry[0]], meal: .dinner, goal: .highProtein, servings: 12, onlyWhatIHave: true,
            preferences: mark, allergies: [.nuts, .peanuts, .soy], proteinGapGrams: 58.04, locale: "en", now: now, calendar: calendar
        )
        let json = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any])
        #expect(Set(json.keys) == ["pantry", "must_use", "meal", "goal", "servings", "only_what_i_have", "diet", "avoid", "allergens", "protein_gap_g", "locale"])
        #expect((json["pantry"] as? [[String: Any]])?.map { $0["name"] as? String } == ["Baby spinach", "Rice"], "Expired items aren't sent")
        #expect((json["pantry"] as? [[String: Any]])?.first?["use_soon"] as? Bool == true)
        #expect(json["must_use"] as? [String] == ["Baby spinach"])
        #expect(json["meal"] as? String == "dinner" && json["goal"] as? String == "high_protein")
        #expect(json["servings"] as? Int == 8, "Capped at the server's 8")
        #expect(json["diet"] as? String == "pescatarian; prefers high-protein")
        #expect(json["avoid"] as? [String] == ["Coriander", "Mushrooms"])
        #expect(json["allergens"] as? [String] == ["peanuts", "soy", "nuts"])
        #expect(json["protein_gap_g"] as? Double == 58)
        let noGoal = ChefRequest.make(
            pantry: pantry, mustUse: [], meal: .breakfast, goal: nil, servings: 2, onlyWhatIHave: false,
            preferences: NutritionPreferences(), allergies: [], proteinGapGrams: 0, locale: "sk", now: now, calendar: calendar
        )
        #expect(noGoal.goal == "none" && noGoal.diet == "no restrictions" && noGoal.proteinGapGrams == nil)
    }

    @Test("The server's reply decodes, with or without a tip")
    func decode() throws {
        let data = Data("""
        {"recipe":{"name":"Miso rice","minutes":20,"servings":2,"ingredients":[{"name":"Rice","amount":150,"unit":"g","grams":150,"from_pantry":true,"usda_hint":"Rice, white, long-grain, raw"}],"steps":["Cook."],"tip":null},"remaining":7,"estimated":true}
        """.utf8)
        let decoded = try JSONDecoder().decode(ChefResponse.self, from: data)
        #expect(decoded.recipe.name == "Miso rice" && decoded.recipe.tip == nil && decoded.remaining == 7)
        #expect(decoded.recipe.ingredients.first?.usdaHint == "Rice, white, long-grain, raw")
    }

    // MARK: Draft

    @Test("Ingredients are matched on the device; nutrition comes from USDA, not the AI")
    func matchedDraft() throws {
        let outcome = build(response([
            ingredient("Jasmine rice", 150, "g", grams: 150, hint: "Rice, white, long-grain, regular, raw"),
            ingredient("Eggs", 4, "piece", grams: 200, hint: "Egg, whole, raw, fresh"),
            ingredient("Baby spinach", 100, "g", grams: 100, hint: nil),
        ]))
        guard case .draft(let draft) = outcome else { Issue.record("Expected a draft, got \(outcome)"); return }
        #expect(draft.unmatched.isEmpty && !draft.isPartial)
        #expect(draft.recipe.origin == .ai && draft.recipe.category == .dinner)
        let rice = try #require(MockData.genericFoods["20044"]).per100g.calories
        let egg = try #require(MockData.genericFoods["01123"]).per100g.calories
        let spinach = try #require(MockData.genericFoods["11457"]).per100g.calories
        #expect(abs(draft.recipe.nutrition.calories - (rice * 1.5 + egg * 2 + spinach) / 2) < 0.01)
        #expect(draft.recipe.ingredients[2].source == .usda(ndb: "11457"), "Matched by name when there's no hint")
        #expect(draft.recipe.allergens == [.eggs])
        #expect(draft.recipe.dietTags.contains(.vegetarian))
    }

    @Test("A pantry item's chosen food wins; an ingredient USDA doesn't know makes the total partial")
    func pantryAndPartial() throws {
        let now = try TestClock.date(2026, 10, 6, 18, 40)
        let pantry = [item("Rice", now: now, chosen: "20044")]
        let outcome = build(response([
            ingredient("Rice", 150, "g", grams: 150, hint: "Rice, brown, medium-grain, raw"),
            ingredient("Skyr", 150, "g", grams: 150, hint: "Skyr"),
        ]), pantry: pantry)
        guard case .draft(let draft) = outcome else { Issue.record("Expected a draft"); return }
        #expect(draft.recipe.ingredients[0].source == .usda(ndb: "20044"))
        #expect(draft.unmatched == ["Skyr"] && draft.isPartial)
        #expect(draft.recipe.ingredients[1].per100 == nil)
        #expect(draft.recipe.allergens.contains(.milk), "Skyr is milk, from its name")
    }

    @Test("The draft is checked again on the device: soy sauce for someone allergic to soy isn't shown")
    func soySauceRejected() {
        let outcome = build(response([
            ingredient("Jasmine rice", 150, "g", grams: 150, hint: "Rice, white, long-grain, regular, raw"),
            ingredient("Soy sauce", 1, "tbsp", grams: 16, hint: "Soy sauce made from soy and wheat (shoyu)"),
        ]), allergies: [.soy])
        guard case .conflict(let fit) = outcome else { Issue.record("Soy sauce must be caught"); return }
        #expect(fit.allergens == [.soy])
        // The same draft is fine for someone without the allergy (gluten from the sauce is listed).
        guard case .draft(let draft) = build(response([
            ingredient("Soy sauce", 1, "tbsp", grams: 16, hint: "Soy sauce made from soy and wheat (shoyu)"),
        ]), allergies: []) else { Issue.record("Expected a draft"); return }
        #expect(draft.recipe.allergens.isSuperset(of: [.soy, .gluten]))
    }

    @Test("Something the user doesn't eat, or that breaks their diet, isn't shown either")
    func avoidAndDiet() {
        if case .draft = build(response([ingredient("Chestnut mushrooms", 200, "g", grams: 200, hint: "Mushrooms, white, raw")])) {
            Issue.record("Mushrooms are avoided")
        }
        if case .draft = build(response([ingredient("Chicken breast", 300, "g", grams: 300, hint: "Chicken, broilers or fryers, breast, meat only, raw")])) {
            Issue.record("Chicken breaks pescatarian")
        }
        if case .draft = build(response([ingredient("Basil pesto", 30, "g", grams: 30, hint: "Pesto")])) {
            Issue.record("Pesto has nuts")
        }
    }

    // MARK: Limits

    @Test("The limit resets at 00:00 UTC, shown in the user's time")
    func resetTime() throws {
        var bratislava = Calendar(identifier: .gregorian)
        bratislava.timeZone = TimeZone(identifier: "Europe/Bratislava")!
        // 00:30 on 7 Oct in Bratislava is still 6 Oct in UTC: resets at 02:00 Bratislava time.
        let now = try #require(bratislava.date(from: DateComponents(year: 2026, month: 10, day: 7, hour: 0, minute: 30)))
        let reset = AIQuota.resetTime(after: now)
        #expect(bratislava.dateComponents([.day, .hour, .minute], from: reset) == DateComponents(day: 7, hour: 2, minute: 0))
        #expect(AIQuota.serverDay(now) == "2026-10-06")
    }

    @Test("Before the first request, what's left comes from today's usage row and the daily limit")
    @MainActor
    func remainingBeforeFirstRequest() async throws {
        let account = AccountStore(
            config: SupabaseConfig(url: URL(string: "https://mock.vess.invalid")!, publishableKey: "key", appleSignInEnabled: false),
            transport: AIMockTransport(scenario: .ok), store: MemorySessionStore(AIMockTransport.session)
        )
        #expect(try await account.remainingToday(kind: "chef") == 8)
        let full = AccountStore(
            config: SupabaseConfig(url: URL(string: "https://mock.vess.invalid")!, publishableKey: "key", appleSignInEnabled: false),
            transport: AIMockTransport(scenario: .limit), store: MemorySessionStore(AIMockTransport.session)
        )
        #expect(try await full.remainingToday(kind: "chef") == 0)
    }

    @Test("The app only reads ai_usage (GET); the only POST is the ai_daily_limit RPC")
    @MainActor
    func usageIsReadOnly() async throws {
        let recorder = RecordingTransport()
        let account = AccountStore(
            config: SupabaseConfig(url: URL(string: "https://mock.vess.invalid")!, publishableKey: "key", appleSignInEnabled: false),
            transport: recorder, store: MemorySessionStore(AIMockTransport.session)
        )
        _ = try await account.remainingToday(kind: "chef")
        let requests = recorder.requests
        let usage = requests.filter { $0.url?.path().contains("ai_usage") == true }
        #expect(usage.count == 1 && usage.allSatisfy { $0.httpMethod == "GET" && $0.httpBody == nil })
        #expect(requests.filter { $0.httpMethod != "GET" }.compactMap { $0.url?.path() } == ["/rest/v1/rpc/ai_daily_limit"])
    }

    @Test("AI Chef has its own consent")
    func consent() {
        let defaults = UserDefaults(suiteName: "test.chef.\(UUID().uuidString)")!
        let store = AIConsentStore(defaults: defaults)
        store.grant(.coach)
        #expect(!store.isGranted(.chef))
        store.grant(.chef)
        #expect(store.isGranted(.chef) && !store.isGranted(.photo))
    }
}

/// Records what the app sends, and answers like the mock server.
private final class RecordingTransport: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [URLRequest] = []
    private let mock = AIMockTransport(scenario: .ok)

    var requests: [URLRequest] { lock.withLock { recorded } }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        lock.withLock { recorded.append(request) }
        return try await mock.send(request)
    }
}
