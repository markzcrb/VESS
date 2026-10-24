import Foundation

/// An online source of food products: Open Food Facts today, USDA FoodData
/// Central (or others) later. Providers only fetch and map; caching and
/// offline fallback live in `FoodLookupService`.
nonisolated protocol RemoteFoodProvider: Sendable {
    /// Human-readable name for attribution, for example "Open Food Facts".
    var name: String { get }
    func product(barcode: String) async throws -> Food
    func search(_ query: String, limit: Int) async throws -> [Food]
}

/// Failures a provider reports, phrased for the app rather than for HTTP.
nonisolated enum FoodProviderError: Error, Equatable, Sendable {
    /// No connection. Local foods keep working.
    case offline
    case timedOut
    /// Too many requests; try again after the given number of seconds, if known.
    case rateLimited(retryAfter: TimeInterval?)
    case notFound
    case invalidBarcode
    case server(status: Int)
    case invalidResponse
}

/// The minimal HTTP surface providers need, so tests can supply responses
/// without the network.
nonisolated protocol HTTPClient: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

nonisolated struct URLSessionHTTPClient: HTTPClient {
    /// `nil` uses `.shared`, looked up at the first request: touching it at
    /// launch set up the networking stack before the first frame (~120 ms).
    var session: URLSession?

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await (session ?? .shared).data(for: request)
    }
}

/// A provider that is never reachable. Used for UI tests and previews so they
/// are deterministic and never touch the network.
nonisolated struct OfflineFoodProvider: RemoteFoodProvider {
    let name = "Offline"

    func product(barcode: String) async throws -> Food {
        throw FoodProviderError.offline
    }

    func search(_ query: String, limit: Int) async throws -> [Food] {
        throw FoodProviderError.offline
    }
}

/// A sliding one-minute window of request timestamps, used to stay within a
/// provider's published rate limits before the server has to refuse us.
nonisolated struct RateLimiter: Sendable {
    let limit: Int
    var window: TimeInterval = 60
    private(set) var timestamps: [Date] = []

    init(limit: Int, window: TimeInterval = 60) {
        self.limit = limit
        self.window = window
    }

    /// Records a request at `now` if allowed. Returns `nil` when allowed, or
    /// the seconds to wait before the next request is allowed.
    mutating func acquire(at now: Date) -> TimeInterval? {
        timestamps.removeAll { now.timeIntervalSince($0) >= window }
        guard timestamps.count < limit else {
            let oldest = timestamps.min() ?? now
            return max(window - now.timeIntervalSince(oldest), 0)
        }
        timestamps.append(now)
        return nil
    }
}
