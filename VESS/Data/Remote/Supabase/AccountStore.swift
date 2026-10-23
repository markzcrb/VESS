import Foundation

/// The VESS account: only for Coach and photo estimates. The food log never
/// leaves the iPhone. Owns the session (Keychain), refreshes it before it
/// expires and once more on a 401, and calls the edge functions with it.
@Observable
final class AccountStore {
    private(set) var session: AuthSession?
    /// Set when the build has no backend keys; every AI feature then says so.
    let isConfigured: Bool
    let appleSignInEnabled: Bool

    private let auth: AuthClient?
    private let config: SupabaseConfig?
    private let transport: any HTTPTransport
    private let store: any SessionStore
    private var refreshTask: Task<AuthSession, Error>?

    init(config: SupabaseConfig?, transport: any HTTPTransport, store: any SessionStore) {
        self.config = config
        self.transport = transport
        self.store = store
        self.isConfigured = config != nil
        self.appleSignInEnabled = config?.appleSignInEnabled ?? false
        self.auth = config.map { AuthClient(config: $0, transport: transport) }
        self.session = store.load()
    }

    var isSignedIn: Bool { session != nil }

    // MARK: Sign in

    func signInWithApple(idToken: String, rawNonce: String) async throws {
        guard let auth else { throw BackendError.notConfigured }
        adopt(try await auth.signInWithApple(idToken: idToken, rawNonce: rawNonce))
    }

    func requestEmailCode(_ email: String) async throws {
        guard let auth else { throw BackendError.notConfigured }
        try await auth.requestEmailCode(email)
    }

    func verifyEmailCode(_ code: String, email: String) async throws {
        guard let auth else { throw BackendError.notConfigured }
        adopt(try await auth.verifyEmailCode(code, email: email))
    }

    /// Clears the session here at once; tells the server when it can.
    func signOut() async {
        let token = session?.accessToken
        forget()
        if let token { await auth?.signOut(accessToken: token) }
    }

    /// Deletes the account on the server, then signs out. Data on this
    /// iPhone stays (Delete all data is a separate choice).
    func deleteAccount() async throws {
        struct Deleted: Decodable { let deleted: Bool }
        let result: Deleted = try await callFunction("delete-account", body: [String: String]())
        guard result.deleted else { throw BackendError.invalidResponse }
        forget()
    }

    // MARK: Functions

    /// POSTs JSON to an edge function with a fresh token; on a 401, refreshes
    /// once and tries again.
    func callFunction<Response: Decodable, Body: Encodable>(_ name: String, body: Body) async throws -> Response {
        guard let config else { throw BackendError.notConfigured }
        let payload = try JSONEncoder().encode(body)
        var token = try await validAccessToken()
        for attempt in 0..<2 {
            var request = URLRequest(url: config.url.appending(path: "functions/v1/\(name)"), timeoutInterval: 60)
            request.httpMethod = "POST"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue(config.publishableKey, forHTTPHeaderField: "apikey")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = payload
            let (data, response): (Data, HTTPURLResponse)
            do {
                (data, response) = try await transport.send(request)
            } catch {
                throw BackendError.from(error)
            }
            if response.statusCode == 401, attempt == 0 {
                token = try await refreshedToken()
                continue
            }
            guard (200..<300).contains(response.statusCode) else {
                let error = BackendError.from(status: response.statusCode, data: data)
                if error == .notSignedIn { forget() }
                throw error
            }
            do {
                return try JSONDecoder().decode(Response.self, from: data)
            } catch {
                throw BackendError.invalidResponse
            }
        }
        throw BackendError.notSignedIn
    }

    /// The access token, refreshed first if it expires within a minute.
    func validAccessToken() async throws -> String {
        guard let session else { throw BackendError.notSignedIn }
        if session.needsRefresh(now: Date()) { return try await refreshedToken() }
        return session.accessToken
    }

    /// One refresh at a time; concurrent callers share it.
    private func refreshedToken() async throws -> String {
        if let refreshTask { return try await refreshTask.value.accessToken }
        guard let auth, let refreshToken = session?.refreshToken else { throw BackendError.notSignedIn }
        let task = Task { try await auth.refresh(refreshToken) }
        refreshTask = task
        defer { refreshTask = nil }
        do {
            let fresh = try await task.value
            adopt(fresh)
            return fresh.accessToken
        } catch BackendError.authRejected {
            // The refresh token was revoked or used up: sign in again.
            forget()
            throw BackendError.notSignedIn
        }
    }

    private func adopt(_ session: AuthSession) {
        self.session = session
        store.save(session)
    }

    private func forget() {
        session = nil
        store.clear()
    }
}

extension AccountStore {
    /// The live backend, or the canned one with `-aiMock` (DEBUG), which
    /// never touches the network or the Keychain.
    static func make() -> AccountStore {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-aiMock") {
            let signedIn = !arguments.contains("-aiMockSignedOut")
            return AccountStore(
                config: SupabaseConfig(url: URL(string: "https://mock.vess.invalid")!, publishableKey: "mock", appleSignInEnabled: true),
                transport: AIMockTransport.fromLaunchArguments(arguments),
                store: MemorySessionStore(signedIn ? AIMockTransport.session : nil)
            )
        }
        if arguments.contains("-uiTesting") {
            return AccountStore(config: SupabaseConfig.fromBundle(), transport: URLSessionTransport(), store: MemorySessionStore())
        }
        #endif
        return AccountStore(config: SupabaseConfig.fromBundle(), transport: URLSessionTransport(), store: KeychainSessionStore())
    }
}
