import Foundation
import Observation
import OSLog

/// Combines the on-device store with an online provider.
///
/// Local data always comes first and never waits for the network: the
/// starter catalog, the user's foods and cached products are searched
/// locally; the provider only adds to them. Products retrieved online are
/// cached on the device, so they keep working offline.
@Observable
final class FoodLookupService {
    private let store: LocalStore
    private let provider: RemoteFoodProvider
    private let logger = Logger(subsystem: "VESS", category: "FoodLookup")

    /// Cached products older than this are refreshed when online.
    static let cacheLifetime: TimeInterval = 30 * 24 * 60 * 60

    /// The provider's name, for attribution in the UI.
    var providerName: String { provider.name }

    init(store: LocalStore, provider: RemoteFoodProvider) {
        self.store = store
        self.provider = provider
    }

    /// Finds a product by barcode: a fresh cached copy first, then the
    /// provider. If the provider fails, a stale cached copy is still returned.
    func lookUp(barcode: String, now: Date = .now) async -> Result<Food, FoodProviderError> {
        let cached = store.food(barcode: barcode)
        if let cached, isFresh(cached, now: now) {
            return .success(cached)
        }
        do {
            let food = try await provider.product(barcode: barcode)
            cache(food)
            return .success(food)
        } catch {
            let providerError = Self.providerError(error)
            logger.info("Barcode lookup failed: \(String(describing: providerError), privacy: .public)")
            if let cached { return .success(cached) }
            return .failure(providerError)
        }
    }

    /// Online search. Callers show local results first and add these after.
    func searchOnline(_ query: String) async -> Result<[Food], FoodProviderError> {
        do {
            return .success(try await provider.search(query, limit: 20))
        } catch {
            let providerError = Self.providerError(error)
            logger.info("Online search failed: \(String(describing: providerError), privacy: .public)")
            return .failure(providerError)
        }
    }

    /// Saves a remote product on the device (when opened or logged), so it
    /// appears in Recent and works offline. Local foods need no caching.
    func cache(_ food: Food) {
        guard food.source == .openFoodFacts else { return }
        do {
            try store.save(food)
        } catch {
            logger.error("Caching a product failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func isFresh(_ food: Food, now: Date) -> Bool {
        guard let retrieved = food.sourceInfo?.retrievedAt else { return true }
        return now.timeIntervalSince(retrieved) < Self.cacheLifetime
    }

    private static func providerError(_ error: Error) -> FoodProviderError {
        (error as? FoodProviderError) ?? .invalidResponse
    }
}

#if DEBUG
extension FoodLookupService {
    /// No network, for previews.
    static func preview(store: LocalStore) -> FoodLookupService {
        FoodLookupService(store: store, provider: OfflineFoodProvider())
    }
}
#endif
