import Foundation
import Testing
@testable import VESS

/// Answers requests in order and records them.
nonisolated final class ScriptedTransport: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var replies: [(Int, String)]
    private(set) var requests: [URLRequest] = []

    init(_ replies: [(Int, String)]) { self.replies = replies }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let reply: (Int, String) = lock.withLock {
            requests.append(request)
            return replies.isEmpty ? (500, "{}") : replies.removeFirst()
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: reply.0, httpVersion: nil, headerFields: nil)!
        return (Data(reply.1.utf8), response)
    }

    var paths: [String] { lock.withLock { requests.compactMap { $0.url?.path() } } }
}

@MainActor
@Suite("Account and backend")
struct AccountTests {
    private let config = SupabaseConfig(url: URL(string: "https://example.supabase.co")!, publishableKey: "pk", appleSignInEnabled: false)

    private func sessionJSON(access: String = "a1", refresh: String = "r1", expiresAt: Double) -> String {
        #"{"access_token":"\#(access)","refresh_token":"\#(refresh)","expires_in":3600,"expires_at":\#(expiresAt),"token_type":"bearer","user":{"id":"u1","email":"mark@example.com","app_metadata":{"provider":"email"}}}"#
    }

    @Test("GoTrue's session decodes; expires_at wins over expires_in; Apple's hidden email may be missing")
    func decodeSession() throws {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let session = try AuthClient.decodeSession(Data(sessionJSON(expiresAt: 1_003_600).utf8), now: now)
        #expect(session.accessToken == "a1" && session.refreshToken == "r1" && session.userID == "u1")
        #expect(session.expiresAt == Date(timeIntervalSince1970: 1_003_600))
        #expect(session.email == "mark@example.com" && session.provider == "email")

        let apple = #"{"access_token":"a","refresh_token":"r","expires_in":60,"user":{"id":"u2","email":"","app_metadata":{"provider":"apple"}}}"#
        let decoded = try AuthClient.decodeSession(Data(apple.utf8), now: now)
        #expect(decoded.expiresAt == now.addingTimeInterval(60) && decoded.email == nil && decoded.provider == "apple")
        #expect(throws: BackendError.invalidResponse) { try AuthClient.decodeSession(Data("{}".utf8), now: now) }
    }

    @Test("A session is refreshed a minute before it expires")
    func refreshMargin() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let session = AuthSession(accessToken: "a", refreshToken: "r", expiresAt: now.addingTimeInterval(61), userID: "u", email: nil, provider: "email")
        #expect(!session.needsRefresh(now: now))
        #expect(session.needsRefresh(now: now.addingTimeInterval(2)))
    }

    @Test("Function errors map to the app's: 401, 429, 400 bad_*, 502, 503, others; URL errors to offline")
    func errorMapping() {
        #expect(BackendError.from(status: 401, data: Data(#"{"error":"not_authenticated"}"#.utf8)) == .notSignedIn)
        #expect(BackendError.from(status: 429, data: Data(#"{"error":"daily_limit","remaining":0}"#.utf8)) == .dailyLimit)
        #expect(BackendError.from(status: 400, data: Data(#"{"error":"bad_image"}"#.utf8)) == .badRequest("bad_image"))
        #expect(BackendError.from(status: 502, data: Data(#"{"error":"upstream"}"#.utf8)) == .upstream)
        #expect(BackendError.from(status: 503, data: Data(#"{"error":"not_configured"}"#.utf8)) == .notConfigured)
        #expect(BackendError.from(status: 500, data: Data()) == .server(500))
        #expect(BackendError.from(URLError(.notConnectedToInternet)) == .offline)
        #expect(BackendError.from(URLError(.timedOut)) == .offline)
    }

    @Test("Email code: /otp, then /verify type email; the session lands in the store")
    func emailSignIn() async throws {
        let transport = ScriptedTransport([(200, "{}"), (200, sessionJSON(expiresAt: Date().timeIntervalSince1970 + 3600))])
        let store = MemorySessionStore()
        let account = AccountStore(config: config, transport: transport, store: store)
        try await account.requestEmailCode("mark@example.com")
        try await account.verifyEmailCode("123456", email: "mark@example.com")
        #expect(transport.paths == ["/auth/v1/otp", "/auth/v1/verify"])
        let body = try #require(transport.requests[1].httpBody.flatMap { try JSONSerialization.jsonObject(with: $0) as? [String: Any] })
        #expect(body["type"] as? String == "email" && body["token"] as? String == "123456")
        #expect(transport.requests[0].value(forHTTPHeaderField: "apikey") == "pk")
        #expect(account.isSignedIn && store.load()?.accessToken == "a1")
    }

    @Test("The email code: pasted spaces and dashes are dropped, exactly 6 digits, nothing else is sent")
    func emailCodeFormat() async {
        #expect(EmailCode.normalized(" 123 456 ") == "123456")
        #expect(EmailCode.normalized("123-456") == "123456")
        #expect(EmailCode.normalized("12345678") == "123456", "At most 6")
        #expect(EmailCode.normalized("Your code: 482 913") == "482913")
        #expect(EmailCode.isComplete("482913") && !EmailCode.isComplete("48291") && !EmailCode.isComplete("4829130"))
        #expect(!EmailCode.isComplete("٤٨٢٩١٣"), "ASCII digits only")
        let transport = ScriptedTransport([])
        let account = AccountStore(config: config, transport: transport, store: MemorySessionStore())
        await #expect(throws: BackendError.authRejected("invalid_code")) {
            try await account.verifyEmailCode("12345", email: "mark@example.com")
        }
        #expect(transport.paths.isEmpty, "A short code never reaches the server")
    }

    @Test("A wrong code is rejected and leaves you signed out")
    func wrongCode() async {
        let transport = ScriptedTransport([(403, #"{"error_code":"otp_expired","msg":"Token has expired or is invalid"}"#)])
        let account = AccountStore(config: config, transport: transport, store: MemorySessionStore())
        await #expect(throws: BackendError.authRejected("otp_expired")) {
            try await account.verifyEmailCode("000000", email: "mark@example.com")
        }
        #expect(!account.isSignedIn)
    }

    @Test("Apple: grant_type=id_token with provider apple and the raw nonce")
    func appleSignIn() async throws {
        let transport = ScriptedTransport([(200, sessionJSON(expiresAt: Date().timeIntervalSince1970 + 3600))])
        let account = AccountStore(config: config, transport: transport, store: MemorySessionStore())
        try await account.signInWithApple(idToken: "jwt", rawNonce: "nonce")
        let request = try #require(transport.requests.first)
        #expect(request.url?.query() == "grant_type=id_token")
        let body = try #require(request.httpBody.flatMap { try JSONSerialization.jsonObject(with: $0) as? [String: Any] })
        #expect(body["provider"] as? String == "apple" && body["id_token"] as? String == "jwt" && body["nonce"] as? String == "nonce")
    }

    @Test("An expiring session refreshes before the call; a 401 refreshes once and retries")
    func refreshAndRetry() async throws {
        struct Reply: Decodable { let deleted: Bool }
        let soon = AuthSession(accessToken: "old", refreshToken: "r0", expiresAt: Date().addingTimeInterval(10), userID: "u1", email: nil, provider: "email")
        let later = Date().timeIntervalSince1970 + 3600
        let transport = ScriptedTransport([
            (200, sessionJSON(access: "a1", refresh: "r1", expiresAt: later)),   // refresh before
            (401, #"{"error":"not_authenticated"}"#),                            // rejected once
            (200, sessionJSON(access: "a2", refresh: "r2", expiresAt: later)),   // refresh again
            (200, #"{"deleted":true}"#),                                         // retried
        ])
        let account = AccountStore(config: config, transport: transport, store: MemorySessionStore(soon))
        let reply: Reply = try await account.callFunction("delete-account", body: [String: String]())
        #expect(reply.deleted)
        #expect(transport.paths == ["/auth/v1/token", "/functions/v1/delete-account", "/auth/v1/token", "/functions/v1/delete-account"])
        #expect(transport.requests[3].value(forHTTPHeaderField: "Authorization") == "Bearer a2")
        #expect(account.session?.refreshToken == "r2")
    }

    @Test("A revoked refresh token signs you out")
    func revokedRefresh() async {
        let expired = AuthSession(accessToken: "old", refreshToken: "r0", expiresAt: .distantPast, userID: "u1", email: nil, provider: "email")
        let transport = ScriptedTransport([(400, #"{"error_code":"refresh_token_not_found"}"#)])
        let store = MemorySessionStore(expired)
        let account = AccountStore(config: config, transport: transport, store: store)
        await #expect(throws: BackendError.notSignedIn) {
            let _: [String: Bool] = try await account.callFunction("coach", body: [String: String]())
        }
        #expect(!account.isSignedIn && store.load() == nil)
    }

    @Test("Delete account calls delete-account, then signs out")
    func deleteAccount() async throws {
        let session = AuthSession(accessToken: "a", refreshToken: "r", expiresAt: Date().addingTimeInterval(3600), userID: "u1", email: nil, provider: "email")
        let transport = ScriptedTransport([(200, #"{"deleted":true}"#)])
        let account = AccountStore(config: config, transport: transport, store: MemorySessionStore(session))
        try await account.deleteAccount()
        #expect(transport.paths == ["/functions/v1/delete-account"] && !account.isSignedIn)
    }

    @Test("No keys in the build: not configured, and nothing is sent")
    func notConfigured() async {
        let transport = ScriptedTransport([])
        let account = AccountStore(config: nil, transport: transport, store: MemorySessionStore())
        #expect(!account.isConfigured)
        await #expect(throws: BackendError.notConfigured) { try await account.requestEmailCode("mark@example.com") }
        #expect(transport.requests.isEmpty)
    }
}
