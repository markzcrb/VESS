import Foundation
import Testing
@testable import VESS

// MARK: - Test doubles

/// Returns canned responses and records requests. Never touches the network.
nonisolated final class StubHTTPClient: HTTPClient, @unchecked Sendable {
    enum Reply {
        case response(status: Int, body: String, headers: [String: String] = [:])
        case failure(Error)
    }

    private let lock = NSLock()
    private var replies: [Reply]
    private var _requests: [URLRequest] = []

    init(_ replies: Reply...) {
        self.replies = replies
    }

    var requests: [URLRequest] {
        lock.withLock { _requests }
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let reply: Reply = lock.withLock {
            _requests.append(request)
            return replies.isEmpty ? .response(status: 500, body: "") : replies.removeFirst()
        }
        switch reply {
        case .response(let status, let body, let headers):
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
            return (Data(body.utf8), response)
        case .failure(let error):
            throw error
        }
    }
}

/// A provider with a fixed outcome, for lookup-service tests.
nonisolated struct StubFoodProvider: RemoteFoodProvider {
    let name = "Stub"
    var product: Result<Food, FoodProviderError>

    func product(barcode: String) async throws -> Food {
        try product.get()
    }

    func search(_ query: String, limit: Int) async throws -> [Food] {
        [try product.get()]
    }
}

private enum Fixture {
    static let retrievedAt = Date(timeIntervalSince1970: 1_800_000_000)

    static func product(_ fields: [String: Any]) -> [String: Any] {
        var product: [String: Any] = ["code": "3017620422003", "product_name": "Hazelnut spread", "brands": "Brand A, Brand B"]
        product.merge(fields) { $1 }
        return product
    }

    static let completeJSON = """
    {"code":"3017620422003","status":"success","product":{"code":"3017620422003","product_name":"Hazelnut spread",
    "brands":"Brand A","quantity":"400 g","serving_size":"15 g","serving_quantity":15,
    "nutriments":{"energy-kcal_100g":539,"proteins_100g":6.3,"carbohydrates_100g":57.5,"fat_100g":30.9,
    "sugars_100g":56.3,"saturated-fat_100g":10.6,"salt_100g":0.107},
    "allergens_tags":["en:milk","en:nuts","en:soybeans"],"nova_group":4}}
    """
}

// MARK: - Mapper

@Suite("Open Food Facts mapping")
struct OpenFoodFactsMapperTests {
    @Test("A complete product maps every field, per 100 g")
    func complete() throws {
        let json = try #require(try JSONSerialization.jsonObject(with: Data(Fixture.completeJSON.utf8)) as? [String: Any])
        let product = try #require(json["product"] as? [String: Any])
        let food = try #require(OpenFoodFactsMapper.food(from: product, code: nil, retrievedAt: Fixture.retrievedAt))

        #expect(food.name == "Hazelnut spread")
        #expect(food.brand == "Brand A")
        #expect(food.barcode == "3017620422003")
        #expect(food.servingSize == 100)
        #expect(food.servingUnit == .gram)
        #expect(food.nutrition.calories == 539)
        #expect(food.nutrition.proteinGrams == 6.3)
        #expect(food.nutrition.unreportedCoreNutrients == nil)
        #expect(food.nutrition.sugarGrams == 56.3)
        #expect(food.nutrition.fiberGrams == nil) // Not in the data: stays unknown.
        #expect(food.nutrition.sodiumMilligrams?.isApproximately(42.8) == true)
        #expect(food.nutrition.additional[.saturatedFat] == 10.6)
        #expect(food.servingOptions == [ServingOption(label: "15 g", amount: 15)])
        #expect(food.allergens == [.milk, .nuts, .soy])
        #expect(food.quality?.processingLevel == .ultraProcessed)
        #expect(food.source == .openFoodFacts)
        #expect(food.id == UUID(stableKey: "openfoodfacts.3017620422003"))
        #expect(food.sourceInfo?.isCommunityContributed == true)
        #expect(food.sourceInfo?.license == OpenFoodFactsClient.licenseName)
        #expect(food.sourceInfo?.retrievedAt == Fixture.retrievedAt)
        #expect(food.sourceInfo?.url?.absoluteString == "https://world.openfoodfacts.org/product/3017620422003")
    }

    @Test("Energy in kJ only is converted to kcal")
    func kilojoules() throws {
        let product = Fixture.product(["nutriments": ["energy-kj_100g": 418.4, "proteins_100g": 1, "carbohydrates_100g": 1, "fat_100g": 1]])
        let food = try #require(OpenFoodFactsMapper.food(from: product, code: nil, retrievedAt: .now))
        #expect(food.nutrition.calories.isApproximately(100))
        #expect(food.nutrition.canBeLogged)
    }

    @Test("Missing protein is unreported, not zero")
    func missingProtein() throws {
        let product = Fixture.product(["nutriments": ["energy-kcal_100g": 200, "carbohydrates_100g": 30, "fat_100g": 5]])
        let food = try #require(OpenFoodFactsMapper.food(from: product, code: nil, retrievedAt: .now))
        #expect(food.nutrition.unreportedCoreNutrients == [.protein])
        #expect(food.nutrition.canBeLogged)
        #expect(food.nutrition.sodiumMilligrams == nil)
    }

    @Test("Missing calories make a product unloggable")
    func missingCalories() throws {
        let food = try #require(OpenFoodFactsMapper.food(from: Fixture.product(["nutriments": [:]]), code: nil, retrievedAt: .now))
        #expect(food.nutrition.unreportedCoreNutrients == Set(CoreNutrient.allCases))
        #expect(!food.nutrition.canBeLogged)
    }

    @Test("Numbers given as strings are accepted; negative values are ignored")
    func stringNumbers() throws {
        let product = Fixture.product(["nutriments": ["energy-kcal_100g": "120", "proteins_100g": "3,5", "carbohydrates_100g": -1, "fat_100g": "2"]])
        let food = try #require(OpenFoodFactsMapper.food(from: product, code: nil, retrievedAt: .now))
        #expect(food.nutrition.calories == 120)
        #expect(food.nutrition.proteinGrams == 3.5)
        #expect(food.nutrition.unreportedCoreNutrients == [.carbohydrates])
    }

    @Test("Sodium is preferred over salt when both are present")
    func sodium() throws {
        let product = Fixture.product(["nutriments": ["energy-kcal_100g": 1, "sodium_100g": 0.2, "salt_100g": 9]])
        let food = try #require(OpenFoodFactsMapper.food(from: product, code: nil, retrievedAt: .now))
        #expect(food.nutrition.sodiumMilligrams?.isApproximately(200) == true)
    }

    @Test("Drinks are measured in milliliters", arguments: ["330 ml", "33 cl", "1 l", "1.5L"])
    func liquids(quantity: String) throws {
        let food = try #require(OpenFoodFactsMapper.food(from: Fixture.product(["quantity": quantity]), code: nil, retrievedAt: .now))
        #expect(food.servingUnit == .milliliter)
    }

    @Test("Solid package sizes stay in grams", arguments: ["400 g", "1 kg", "6 rolls"])
    func solids(quantity: String) throws {
        let food = try #require(OpenFoodFactsMapper.food(from: Fixture.product(["quantity": quantity]), code: nil, retrievedAt: .now))
        #expect(food.servingUnit == .gram)
    }

    @Test("Products without a name or code are skipped")
    func unusable() {
        #expect(OpenFoodFactsMapper.food(from: ["code": "123"], code: nil, retrievedAt: .now) == nil)
        #expect(OpenFoodFactsMapper.food(from: ["product_name": "X"], code: nil, retrievedAt: .now) == nil)
        #expect(OpenFoodFactsMapper.food(from: ["product_name": "X"], code: "12345678", retrievedAt: .now)?.barcode == "12345678")
        #expect(OpenFoodFactsMapper.food(from: ["code": "123", "product_name": "", "generic_name": "Spread"], code: nil, retrievedAt: .now)?.name == "Spread")
    }
}

// MARK: - Client

@Suite("Open Food Facts client")
struct OpenFoodFactsClientTests {
    private func client(_ http: StubHTTPClient) -> OpenFoodFactsClient {
        OpenFoodFactsClient(http: http, now: { Fixture.retrievedAt })
    }

    @Test("Product lookup calls the v3 endpoint with a User-Agent and limited fields")
    func productRequest() async throws {
        let http = StubHTTPClient(.response(status: 200, body: Fixture.completeJSON))
        let food = try await client(http).product(barcode: "3017620422003")

        #expect(food.name == "Hazelnut spread")
        let request = try #require(http.requests.first)
        let url = try #require(request.url)
        #expect(url.host() == "world.openfoodfacts.org")
        #expect(url.path() == "/api/v3/product/3017620422003")
        #expect(url.query()?.contains("fields=") == true)
        let userAgent = try #require(request.value(forHTTPHeaderField: "User-Agent"))
        #expect(userAgent.hasPrefix("UMEVA/"))
        #expect(!userAgent.contains("@")) // Never personal data.
        #expect(request.timeoutInterval == 10)
    }

    @Test("Not found: HTTP 404, v3 failure status and v2 status 0")
    func notFound() async {
        let replies: [StubHTTPClient.Reply] = [
            .response(status: 404, body: #"{"status":"failure"}"#),
            .response(status: 200, body: #"{"status":"failure","errors":[]}"#),
            .response(status: 200, body: #"{"status":0}"#),
        ]
        for reply in replies {
            await #expect(throws: FoodProviderError.notFound) {
                try await client(StubHTTPClient(reply)).product(barcode: "12345678")
            }
        }
    }

    @Test("Invalid barcodes never reach the network")
    func invalidBarcode() async {
        let http = StubHTTPClient()
        for code in ["123", "12345678901234567", "1234abcd", ""] {
            await #expect(throws: FoodProviderError.invalidBarcode) {
                try await client(http).product(barcode: code)
            }
        }
        #expect(http.requests.isEmpty)
    }

    @Test("HTTP 429 reports rate limiting with Retry-After")
    func serverRateLimit() async {
        let http = StubHTTPClient(.response(status: 429, body: "", headers: ["Retry-After": "30"]))
        await #expect(throws: FoodProviderError.rateLimited(retryAfter: 30)) {
            try await client(http).product(barcode: "12345678")
        }
    }

    @Test("Network failures map to offline or timed out")
    func networkErrors() async {
        let cases: [(URLError.Code, FoodProviderError)] = [
            (.notConnectedToInternet, .offline),
            (.networkConnectionLost, .offline),
            (.cannotFindHost, .offline),
            (.timedOut, .timedOut),
        ]
        for (code, expected) in cases {
            await #expect(throws: expected) {
                try await client(StubHTTPClient(.failure(URLError(code)))).product(barcode: "12345678")
            }
        }
        await #expect(throws: FoodProviderError.server(status: 503)) {
            try await client(StubHTTPClient(.response(status: 503, body: ""))).product(barcode: "12345678")
        }
        await #expect(throws: FoodProviderError.invalidResponse) {
            try await client(StubHTTPClient(.response(status: 200, body: "<html>"))).product(barcode: "12345678")
        }
    }

    @Test("The client stays within the published limit of 15 product reads a minute")
    func localRateLimit() async {
        // With no canned replies the stub answers 500; the status doesn't matter here.
        let http = StubHTTPClient()
        let client = client(http)
        for _ in 0..<15 {
            _ = try? await client.product(barcode: "12345678")
        }
        await #expect(throws: FoodProviderError.rateLimited(retryAfter: 60)) {
            try await client.product(barcode: "12345678")
        }
        #expect(http.requests.count == 15)
    }

    @Test("Search uses Search-a-licious and reads hits")
    func search() async throws {
        let body = #"{"hits":[{"code":"111111111","product_name":"Oat drink","quantity":"1 l","nutriments":{"energy-kcal_100g":45}},{"code":"2"}],"count":2}"#
        let http = StubHTTPClient(.response(status: 200, body: body))
        let foods = try await client(http).search("oat drink", limit: 10)

        #expect(foods.map(\.name) == ["Oat drink"])
        #expect(foods.first?.servingUnit == .milliliter)
        let url = try #require(http.requests.first?.url)
        #expect(url.host() == "search.openfoodfacts.org")
        #expect(url.path() == "/search")
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(items.first { $0.name == "q" }?.value == "oat drink")
        #expect(items.first { $0.name == "page_size" }?.value == "10")
    }

    @Test("Very short searches don't hit the network")
    func shortSearch() async throws {
        let http = StubHTTPClient()
        #expect(try await client(http).search(" a ", limit: 10).isEmpty)
        #expect(http.requests.isEmpty)
    }
}

@Suite("Rate limiter")
struct RateLimiterTests {
    @Test("Allows up to the limit per window, then reports the wait")
    func slidingWindow() {
        var limiter = RateLimiter(limit: 2, window: 60)
        let start = Date(timeIntervalSince1970: 0)
        #expect(limiter.acquire(at: start) == nil)
        #expect(limiter.acquire(at: start.addingTimeInterval(10)) == nil)
        #expect(limiter.acquire(at: start.addingTimeInterval(20)) == 40)
        // The first request leaves the window after 60 s.
        #expect(limiter.acquire(at: start.addingTimeInterval(60)) == nil)
        #expect(limiter.acquire(at: start.addingTimeInterval(61)) == 9)
    }
}

// MARK: - Lookup service

@MainActor
@Suite("Food lookup")
struct FoodLookupServiceTests {
    private func product(name: String, retrievedAt: Date) -> Food {
        OpenFoodFactsMapper.food(
            from: Fixture.product(["product_name": name, "nutriments": ["energy-kcal_100g": 100]]),
            code: nil,
            retrievedAt: retrievedAt
        )!
    }

    @Test("A fresh cached product is used without asking the provider")
    func freshCache() async throws {
        let store = try LocalStore.inMemory()
        let now = Fixture.retrievedAt
        try store.save(product(name: "Cached", retrievedAt: now.addingTimeInterval(-86_400)))
        let service = FoodLookupService(store: store, provider: StubFoodProvider(product: .success(product(name: "Online", retrievedAt: now))))

        let result = await service.lookUp(barcode: "3017620422003", now: now)
        #expect(try result.get().name == "Cached")
    }

    @Test("A food created after 'Add manually' keeps its barcode, so scanning it again finds it")
    func userFoodWithBarcode() async throws {
        let store = try LocalStore.inMemory()
        let now = Fixture.retrievedAt
        let own = Food(
            id: UUID(), name: "Market granola", brand: nil, barcode: "4000000000006",
            servingSize: 100, servingUnit: .gram,
            nutrition: NutritionFacts(calories: 450, proteinGrams: 10, carbohydrateGrams: 60, fatGrams: 18),
            ingredients: [], allergens: [], quality: nil, source: .userCreated,
            createdAt: now, updatedAt: now
        )
        try store.save(own)
        let service = FoodLookupService(store: store, provider: StubFoodProvider(product: .failure(.notFound)))

        #expect(try await service.lookUp(barcode: "4000000000006", now: now).get().name == "Market granola")
    }

    @Test("A stale cached product is refreshed when online, and kept when offline")
    func staleCache() async throws {
        let now = Fixture.retrievedAt
        let stale = product(name: "Old", retrievedAt: now.addingTimeInterval(-40 * 86_400))

        let offlineStore = try LocalStore.inMemory()
        try offlineStore.save(stale)
        let offline = FoodLookupService(store: offlineStore, provider: OfflineFoodProvider())
        #expect(try await offline.lookUp(barcode: "3017620422003", now: now).get().name == "Old")

        let onlineStore = try LocalStore.inMemory()
        try onlineStore.save(stale)
        let online = FoodLookupService(store: onlineStore, provider: StubFoodProvider(product: .success(product(name: "New", retrievedAt: now))))
        #expect(try await online.lookUp(barcode: "3017620422003", now: now).get().name == "New")
        #expect(onlineStore.food(barcode: "3017620422003")?.name == "New")
    }

    @Test("Without a cached copy, provider errors are passed on")
    func noCache() async throws {
        let service = FoodLookupService(store: try LocalStore.inMemory(), provider: StubFoodProvider(product: .failure(.notFound)))
        let result = await service.lookUp(barcode: "12345678")
        #expect(throws: FoodProviderError.notFound) { try result.get() }

        let offline = FoodLookupService(store: try LocalStore.inMemory(), provider: OfflineFoodProvider())
        let search = await offline.searchOnline("oats")
        #expect(throws: FoodProviderError.offline) { try search.get() }
    }

    @Test("Products found online are cached and searchable offline")
    func cachedProductIsLocal() async throws {
        let store = try LocalStore.inMemory()
        let service = FoodLookupService(store: store, provider: StubFoodProvider(product: .success(product(name: "Hazelnut spread", retrievedAt: .now))))
        _ = await service.lookUp(barcode: "3017620422003")

        #expect(store.searchLocalFoods("hazelnut").map(\.name) == ["Hazelnut spread"])
    }

    @Test("Only Open Food Facts products are cached")
    func cachesRemoteOnly() throws {
        let store = try LocalStore.inMemory()
        let service = FoodLookupService.preview(store: store)
        service.cache(StarterCatalog.foods[0])
        #expect(store.savedFoods().isEmpty)
        service.cache(product(name: "Remote", retrievedAt: .now))
        #expect(store.savedFoods().map(\.name) == ["Remote"])
    }
}
