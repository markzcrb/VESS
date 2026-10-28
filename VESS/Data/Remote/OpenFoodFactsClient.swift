import Foundation

/// Open Food Facts, read-only.
///
/// - Product lookup: `GET https://world.openfoodfacts.org/api/v3/product/{barcode}`
/// - Text search: `GET https://search.openfoodfacts.org/search?q=…` (Search-a-licious;
///   the product server has no full-text search).
///
/// Reads need no account or key, only a descriptive User-Agent. Published
/// limits are 15 product reads and 10 searches per minute per IP; the client
/// stays within them locally and also honors HTTP 429.
///
/// Data is © Open Food Facts contributors, under the Open Database License
/// (ODbL). It is community-contributed and not verified; VESS shows it as such.
/// Product images are not used, so their separate CC BY-SA terms don't apply.
actor OpenFoodFactsClient: RemoteFoodProvider {
    nonisolated let name = "Open Food Facts"

    nonisolated struct Configuration: Sendable {
        var productHost = "world.openfoodfacts.org"
        var searchHost = "search.openfoodfacts.org"
        /// Identifies the app to Open Food Facts, as their API terms require.
        /// Add a public contact URL or address here before release. Never a
        /// user's personal data.
        var userAgent = "UMEVA/\(OpenFoodFactsClient.appVersion) (iOS)"
        var timeout: TimeInterval = 10
        var productReadsPerMinute = 15
        var searchesPerMinute = 10
    }

    nonisolated static let licenseName = "Open Database License (ODbL)"
    nonisolated static let attribution = "Product data from Open Food Facts, available under the Open Database License."

    private let configuration: Configuration
    private let http: HTTPClient
    private let now: @Sendable () -> Date
    private var productLimiter: RateLimiter
    private var searchLimiter: RateLimiter

    init(
        configuration: Configuration = Configuration(),
        http: HTTPClient = URLSessionHTTPClient(),
        now: @escaping @Sendable () -> Date = { .now }
    ) {
        self.configuration = configuration
        self.http = http
        self.now = now
        self.productLimiter = RateLimiter(limit: configuration.productReadsPerMinute)
        self.searchLimiter = RateLimiter(limit: configuration.searchesPerMinute)
    }

    nonisolated static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    /// Fields requested from the API. Keeping the list short keeps responses small.
    nonisolated static let fields = [
        "code", "product_name", "product_name_en", "generic_name", "brands", "quantity",
        "serving_size", "serving_quantity", "nutriments", "nutrition_data_per",
        "allergens_tags", "nova_group", "ingredients_text",
    ].joined(separator: ",")

    // MARK: RemoteFoodProvider

    func product(barcode: String) async throws -> Food {
        let code = barcode.filter(\.isNumber)
        guard (8...14).contains(code.count), code.count == barcode.trimmingCharacters(in: .whitespaces).count else {
            throw FoodProviderError.invalidBarcode
        }
        if let wait = productLimiter.acquire(at: now()) {
            throw FoodProviderError.rateLimited(retryAfter: wait)
        }

        var components = URLComponents()
        components.scheme = "https"
        components.host = configuration.productHost
        components.path = "/api/v3/product/\(code)"
        components.queryItems = [URLQueryItem(name: "fields", value: Self.fields)]

        let (data, response) = try await send(components)
        switch response.statusCode {
        case 200:
            break
        case 404:
            throw FoodProviderError.notFound
        default:
            throw Self.error(for: response)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw FoodProviderError.invalidResponse
        }
        // v3 reports "success" / "success_with_warnings" / "failure"; v2 used 1 / 0.
        if let status = json["status"] as? String, status == "failure" { throw FoodProviderError.notFound }
        if let status = json["status"] as? Int, status == 0 { throw FoodProviderError.notFound }
        guard let product = json["product"] as? [String: Any],
              let food = OpenFoodFactsMapper.food(from: product, code: code, retrievedAt: now())
        else {
            throw FoodProviderError.notFound
        }
        return food
    }

    func search(_ query: String, limit: Int) async throws -> [Food] {
        let trimmed = InputLimits.clamp(query.trimmingCharacters(in: .whitespacesAndNewlines), to: InputLimits.foodSearch)
        guard trimmed.count >= 2 else { return [] }
        if let wait = searchLimiter.acquire(at: now()) {
            throw FoodProviderError.rateLimited(retryAfter: wait)
        }

        var components = URLComponents()
        components.scheme = "https"
        components.host = configuration.searchHost
        components.path = "/search"
        components.queryItems = [
            URLQueryItem(name: "q", value: trimmed),
            URLQueryItem(name: "page_size", value: String(min(max(limit, 1), 50))),
            URLQueryItem(name: "fields", value: Self.fields),
        ]

        let (data, response) = try await send(components)
        guard response.statusCode == 200 else { throw Self.error(for: response) }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hits = json["hits"] as? [[String: Any]]
        else {
            throw FoodProviderError.invalidResponse
        }
        let retrievedAt = now()
        return hits.compactMap { OpenFoodFactsMapper.food(from: $0, code: nil, retrievedAt: retrievedAt) }
    }

    // MARK: Networking

    private func send(_ components: URLComponents) async throws -> (Data, HTTPURLResponse) {
        guard let url = components.url else { throw FoodProviderError.invalidResponse }
        var request = URLRequest(url: url, timeoutInterval: configuration.timeout)
        request.setValue(configuration.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await http.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else { throw FoodProviderError.invalidResponse }
            return (data, httpResponse)
        } catch let error as FoodProviderError {
            throw error
        } catch let error as URLError {
            throw Self.error(for: error)
        } catch {
            throw FoodProviderError.invalidResponse
        }
    }

    nonisolated static func error(for response: HTTPURLResponse) -> FoodProviderError {
        switch response.statusCode {
        case 404: .notFound
        case 429: .rateLimited(retryAfter: (response.value(forHTTPHeaderField: "Retry-After")).flatMap(TimeInterval.init))
        case 500...599: .server(status: response.statusCode)
        default: .invalidResponse
        }
    }

    nonisolated static func error(for error: URLError) -> FoodProviderError {
        switch error.code {
        case .timedOut: .timedOut
        case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost,
             .dataNotAllowed, .internationalRoamingOff, .dnsLookupFailed:
            .offline
        default: .invalidResponse
        }
    }
}
