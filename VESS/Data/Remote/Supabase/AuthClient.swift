import Foundation
import Security

/// A signed-in session (GoTrue). Kept in the Keychain, nowhere else.
nonisolated struct AuthSession: Codable, Equatable, Sendable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date
    var userID: String
    var email: String?
    /// "apple" or "email".
    var provider: String

    /// Refreshed this long before it expires, so a request never races it.
    static let refreshMargin: TimeInterval = 60

    func needsRefresh(now: Date) -> Bool {
        now.addingTimeInterval(Self.refreshMargin) >= expiresAt
    }
}

/// What can go wrong talking to the VESS backend, in the app's own terms.
nonisolated enum BackendError: Error, Equatable, Sendable {
    /// Not signed in, or the session couldn't be refreshed.
    case notSignedIn
    /// 429: today's free uses are used up.
    case dailyLimit
    /// 503: the server has no AI provider configured.
    case notConfigured
    /// 502: the AI provider failed; the use was given back.
    case upstream
    /// 400 `bad_*`, with the server's code.
    case badRequest(String)
    /// Auth (GoTrue) refused: wrong or expired code, unknown provider…
    case authRejected(String)
    case offline
    /// Anything else, with the HTTP status.
    case server(Int)
    case invalidResponse
}

/// The server's error body: `{ "error": "daily_limit", "remaining": 0 }`,
/// or GoTrue's `{ "error_code": …, "msg": … }`.
nonisolated struct BackendErrorBody: Decodable, Sendable {
    let error: String?
    let errorCode: String?
    let msg: String?
    let errorDescription: String?

    enum CodingKeys: String, CodingKey {
        case error, msg
        case errorCode = "error_code"
        case errorDescription = "error_description"
    }

    var code: String { error ?? errorCode ?? msg ?? errorDescription ?? "unknown" }
}

nonisolated extension BackendError {
    /// Maps a function's HTTP status and body to an error (README: 401, 429,
    /// 400 bad_*, 502, 503).
    static func from(status: Int, data: Data) -> BackendError {
        let code = (try? JSONDecoder().decode(BackendErrorBody.self, from: data))?.code ?? ""
        switch status {
        case 401: return .notSignedIn
        case 429: return .dailyLimit
        case 503: return .notConfigured
        case 502: return .upstream
        case 400: return .badRequest(code.isEmpty ? "bad_request" : code)
        default: return .server(status)
        }
    }

    static func from(_ error: Error) -> BackendError {
        if let backend = error as? BackendError { return backend }
        if let url = error as? URLError {
            switch url.code {
            case .notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotFindHost, .cannotConnectToHost, .dataNotAllowed:
                return .offline
            default:
                return .server(url.errorCode)
            }
        }
        return .invalidResponse
    }
}

/// GoTrue REST: Sign in with Apple (id token + nonce), email one-time code,
/// refresh and sign out. No third-party SDK.
nonisolated struct AuthClient: Sendable {
    let config: SupabaseConfig
    let transport: any HTTPTransport
    var now: @Sendable () -> Date = { Date() }

    /// Native Sign in with Apple: the identity token and the raw nonce whose
    /// SHA-256 went into the Apple request.
    func signInWithApple(idToken: String, rawNonce: String) async throws -> AuthSession {
        try await session(path: "token", query: "grant_type=id_token",
                          body: ["provider": "apple", "id_token": idToken, "nonce": rawNonce])
    }

    /// Sends a 6-digit code to the address (creating the user on first use).
    func requestEmailCode(_ email: String) async throws {
        let request = try makeRequest(path: "otp", body: ["email": email, "create_user": true])
        let (data, response) = try await send(request)
        guard (200..<300).contains(response.statusCode) else { throw authError(response.statusCode, data) }
    }

    func verifyEmailCode(_ code: String, email: String) async throws -> AuthSession {
        // Never sent unless it is exactly 6 digits.
        guard EmailCode.isComplete(code) else { throw BackendError.authRejected("invalid_code") }
        return try await session(path: "verify", body: ["type": "email", "email": email, "token": code])
    }

    func refresh(_ refreshToken: String) async throws -> AuthSession {
        try await session(path: "token", query: "grant_type=refresh_token", body: ["refresh_token": refreshToken])
    }

    /// Best effort: the local session is cleared whatever the answer.
    func signOut(accessToken: String) async {
        guard var request = try? makeRequest(path: "logout", body: [String: String]()) else { return }
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        _ = try? await send(request)
    }

    // MARK: Plumbing

    private func session(path: String, query: String? = nil, body: [String: Any]) async throws -> AuthSession {
        let request = try makeRequest(path: path, query: query, body: body)
        let (data, response) = try await send(request)
        guard (200..<300).contains(response.statusCode) else { throw authError(response.statusCode, data) }
        return try Self.decodeSession(data, now: now())
    }

    private func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            return try await transport.send(request)
        } catch {
            throw BackendError.from(error)
        }
    }

    private func authError(_ status: Int, _ data: Data) -> BackendError {
        if status >= 500 { return .server(status) }
        let code = (try? JSONDecoder().decode(BackendErrorBody.self, from: data))?.code ?? "unknown"
        return .authRejected(code)
    }

    private func makeRequest(path: String, query: String? = nil, body: [String: Any]) throws -> URLRequest {
        var components = URLComponents(url: config.url.appending(path: "auth/v1/\(path)"), resolvingAgainstBaseURL: false)
        components?.percentEncodedQuery = query
        guard let url = components?.url else { throw BackendError.invalidResponse }
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.httpMethod = "POST"
        request.setValue(config.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    /// GoTrue's session JSON. `expires_at` (Unix seconds) wins over `expires_in`.
    static func decodeSession(_ data: Data, now: Date) throws -> AuthSession {
        struct Wire: Decodable {
            let access_token: String
            let refresh_token: String
            let expires_in: Double?
            let expires_at: Double?
            let user: User
            struct User: Decodable {
                let id: String
                let email: String?
                let app_metadata: Meta?
                struct Meta: Decodable { let provider: String? }
            }
        }
        guard let wire = try? JSONDecoder().decode(Wire.self, from: data) else { throw BackendError.invalidResponse }
        let expiresAt = wire.expires_at.map { Date(timeIntervalSince1970: $0) }
            ?? now.addingTimeInterval(wire.expires_in ?? 3600)
        return AuthSession(
            accessToken: wire.access_token,
            refreshToken: wire.refresh_token,
            expiresAt: expiresAt,
            userID: wire.user.id,
            email: wire.user.email?.isEmpty == false ? wire.user.email : nil,
            provider: wire.user.app_metadata?.provider ?? "email"
        )
    }
}

/// Where the session lives between launches.
nonisolated protocol SessionStore: Sendable {
    func load() -> AuthSession?
    func save(_ session: AuthSession)
    func clear()
}

/// The Keychain, this device only, readable after first unlock (so a refresh
/// can run in the background).
nonisolated struct KeychainSessionStore: SessionStore {
    var service = "VESS.supabase"
    var account = "session"

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    func load() -> AuthSession? {
        var query = query
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(AuthSession.self, from: data)
    }

    func save(_ session: AuthSession) {
        guard let data = try? JSONEncoder().encode(session) else { return }
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }

    func clear() {
        SecItemDelete(query as CFDictionary)
    }
}

/// For tests, previews and DEBUG launch flags: nothing touches the Keychain.
nonisolated final class MemorySessionStore: SessionStore, @unchecked Sendable {
    private let lock = NSLock()
    private var session: AuthSession?

    init(_ session: AuthSession? = nil) { self.session = session }

    func load() -> AuthSession? { lock.withLock { session } }
    func save(_ session: AuthSession) { lock.withLock { self.session = session } }
    func clear() { lock.withLock { session = nil } }
}

/// The sign-in code Supabase emails: exactly 6 digits (the template holds
/// only `{{ .Token }}`, no link). Typed, pasted ("123 456", "123-456") or
/// filled from Mail by iOS one-time-code autofill.
nonisolated enum EmailCode {
    static let length = 6

    /// Digits only, at most 6: spaces and dashes from a paste are dropped.
    static func normalized(_ text: String) -> String {
        String(text.filter(\.isASCII).filter(\.isNumber).prefix(length))
    }

    static func isComplete(_ code: String) -> Bool {
        code.count == length && code.allSatisfy { $0.isASCII && $0.isNumber }
    }
}
