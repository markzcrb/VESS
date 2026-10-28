import Foundation

/// The `entitlement` function's answer: the plan and the daily AI limits
/// the server will apply. The app never decides a plan by itself.
nonisolated struct EntitlementResponse: Codable, Equatable, Sendable {
    enum Plan: String, Codable, Sendable { case free, plus, tester }

    struct Limits: Codable, Equatable, Sendable {
        var coach: Int
        var photo: Int
        var chef: Int

        func value(for feature: AIFeature) -> Int {
            switch feature {
            case .coach: coach
            case .photo: photo
            case .chef: chef
            }
        }
    }

    struct Rejection: Codable, Equatable, Sendable {
        var reason: String
    }

    var plan: Plan
    var productID: String?
    var expiresAt: Date?
    var limits: Limits
    var rejected: [Rejection]

    enum CodingKeys: String, CodingKey {
        case plan, limits, rejected
        case productID = "product_id"
        case expiresAt = "expires_at"
    }

    init(plan: Plan, productID: String? = nil, expiresAt: Date? = nil, limits: Limits, rejected: [Rejection] = []) {
        self.plan = plan
        self.productID = productID
        self.expiresAt = expiresAt
        self.limits = limits
        self.rejected = rejected
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        plan = (try? container.decode(Plan.self, forKey: .plan)) ?? .free
        productID = try container.decodeIfPresent(String.self, forKey: .productID)
        limits = try container.decode(Limits.self, forKey: .limits)
        rejected = try container.decodeIfPresent([Rejection].self, forKey: .rejected) ?? []
        // Postgres ("…+00:00") or JavaScript ("….000Z") timestamps, or a
        // date encoded by this app for its cache.
        if let text = try? container.decodeIfPresent(String.self, forKey: .expiresAt) {
            expiresAt = Self.date(from: text)
        } else {
            expiresAt = try? container.decodeIfPresent(Date.self, forKey: .expiresAt)
        }
    }

    static func date(from text: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }
}

/// What the app shows for UMEVA+, from the server's answer and what
/// StoreKit says on this iPhone. Pure.
nonisolated enum EntitlementRules {
    enum Status: Equatable, Sendable {
        case free
        case plus(expiresAt: Date?)
        case tester
        /// StoreKit has a valid purchase but the server doesn't count it
        /// (yet): "UMEVA+ is active. Updating your limits…", retrying.
        case activating
        /// The purchase was made with another UMEVA account.
        case otherAccount
    }

    static func status(response: EntitlementResponse?, storeKitHasPlus: Bool) -> Status {
        switch response?.plan {
        case .plus: return .plus(expiresAt: response?.expiresAt)
        case .tester: return .tester
        case .free, nil:
            guard storeKitHasPlus else { return .free }
            if response?.rejected.contains(where: { $0.reason == "other_account" }) == true { return .otherAccount }
            return .activating
        }
    }

    /// After a valid purchase the server still says free: try again after
    /// 2 s, 10 s and 60 s, then on the next launch.
    static let retryDelays: [TimeInterval] = [2, 10, 60]

    static func retryDelay(afterAttempt attempt: Int) -> TimeInterval? {
        retryDelays.indices.contains(attempt) ? retryDelays[attempt] : nil
    }

    /// Whether to keep retrying after this answer.
    static func shouldRetry(_ status: Status) -> Bool {
        status == .activating
    }
}
