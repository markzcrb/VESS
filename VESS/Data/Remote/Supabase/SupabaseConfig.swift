import Foundation

/// The VESS backend, read from Info.plist (filled from Config/Supabase.xcconfig).
/// Both values are publishable; no secret ever ships in the app.
nonisolated struct SupabaseConfig: Sendable {
    let url: URL
    let publishableKey: String
    /// Sign in with Apple is offered only when the capability is on
    /// (`VESS_APPLE_SIGN_IN = YES` plus the entitlement; paid team only).
    let appleSignInEnabled: Bool

    init(url: URL, publishableKey: String, appleSignInEnabled: Bool) {
        self.url = url
        self.publishableKey = publishableKey
        self.appleSignInEnabled = appleSignInEnabled
    }

    /// `nil` when the keys are missing (a build without the xcconfig).
    static func fromBundle(_ bundle: Bundle = .main) -> SupabaseConfig? {
        guard let urlString = bundle.object(forInfoDictionaryKey: "VESSSupabaseURL") as? String,
              let url = URL(string: urlString), url.host() != nil,
              let key = bundle.object(forInfoDictionaryKey: "VESSSupabasePublishableKey") as? String,
              !key.isEmpty, !key.contains("$(")
        else { return nil }
        let apple = (bundle.object(forInfoDictionaryKey: "VESSAppleSignIn") as? String)?.uppercased() == "YES"
        return SupabaseConfig(url: url, publishableKey: key, appleSignInEnabled: apple)
    }
}

/// Sends a request. URLSession in the app; canned responses in tests and
/// with `-aiMock`.
nonisolated protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

nonisolated struct URLSessionTransport: HTTPTransport {
    var session: URLSession = .shared

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return (data, http)
    }
}
