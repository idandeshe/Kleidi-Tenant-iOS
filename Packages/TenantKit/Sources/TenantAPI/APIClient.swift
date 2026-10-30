import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Things the app shell reacts to, wherever in the app the triggering request was made.
public enum APIEvent: Sendable, Equatable {
    /// The session is gone (refresh rejected, revoked, tenant no longer eligible). Show sign-in.
    case sessionEnded(reason: String?)
    /// 426 from the server. Show the forced-update screen.
    case updateRequired(minSupportedBuild: Int?)
}

public struct APIRequest: Sendable {
    public enum Method: String, Sendable { case get = "GET", post = "POST", patch = "PATCH", delete = "DELETE" }

    public var method: Method
    /// Path under `/api`, e.g. `/tenant/leases`.
    public var path: String
    /// Query string items (`?leaseId=…`); empty for most calls.
    public var query: [URLQueryItem]
    public var body: Data?
    /// `Content-Type` of `body`; JSON unless set (a multipart upload sets its boundary here).
    public var contentType: String?
    /// Sends `Authorization: Bearer` and refreshes the session when needed.
    public var requiresAuth: Bool

    public init(_ method: Method = .get, _ path: String, query: [URLQueryItem] = [], body: Data? = nil,
                contentType: String? = nil, requiresAuth: Bool = true) {
        self.method = method
        self.path = path
        self.query = query
        self.body = body
        self.contentType = contentType
        self.requiresAuth = requiresAuth
    }
}

/// The tenant API as the native app sees it (docs/tenant-app.md in the server repo):
/// `x-client: tenant-ios` + `x-client-build` on every request, `Authorization: Bearer` for
/// the 15-minute access token, and the refresh token sent in the body of
/// `/tenant/auth/refresh` and `/tenant/auth/logout`. No cookies, no CSRF.
public actor APIClient {
    public nonisolated let baseURL: URL
    public nonisolated let clientBuild: Int
    public nonisolated let events: AsyncStream<APIEvent>

    static let clientKind = "tenant-ios"
    /// Refresh this long before the access token expires instead of waiting for a 401.
    static let refreshLeeway: TimeInterval = 60

    private let transport: HTTPTransport
    private let tokenStore: TokenStore
    private let now: @Sendable () -> Date
    private let eventSink: AsyncStream<APIEvent>.Continuation
    private var tokens: SessionTokens?
    private var refreshTask: Task<SessionTokens, Error>?

    public init(
        baseURL: URL,
        clientBuild: Int,
        transport: HTTPTransport = URLSessionTransport(),
        tokenStore: TokenStore,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.baseURL = baseURL
        self.clientBuild = clientBuild
        self.transport = transport
        self.tokenStore = tokenStore
        self.now = now
        self.tokens = try? tokenStore.load()
        (self.events, self.eventSink) = AsyncStream.makeStream(of: APIEvent.self)
    }

    /// A session was stored by an earlier launch (it may still have expired server-side).
    public var hasStoredSession: Bool { tokens != nil }

    // MARK: - Sending

    public func send<T: Decodable & Sendable>(_ request: APIRequest, as type: T.Type = T.self) async throws -> T {
        let (data, _) = try await sendData(request)
        do {
            return try TenantJSON.decoder().decode(T.self, from: data)
        } catch {
            throw APIError.decoding(String(describing: error))
        }
    }

    public func sendData(_ request: APIRequest) async throws -> (Data, HTTPURLResponse) {
        try await sendData(request, isRetry: false)
    }

    private func sendData(_ request: APIRequest, isRetry: Bool) async throws -> (Data, HTTPURLResponse) {
        var accessToken: String?
        if request.requiresAuth {
            accessToken = try await validAccessToken()
        }

        let (data, response) = try await perform(request, accessToken: accessToken)

        switch response.statusCode {
        case 200..<300:
            return (data, response)
        case 401 where request.requiresAuth && !isRetry:
            // The access token was rejected before its expiry (server restart with a new
            // secret, clock skew…). One refresh, one retry.
            _ = try await refreshSession()
            return try await sendData(request, isRetry: true)
        case 401:
            let body = decodeError(data)
            if request.requiresAuth {
                await endSession(reason: body?.code)
            }
            throw APIError.unauthorized(code: body?.code, message: body?.text ?? "Authentication required")
        case 426:
            let min = decodeError(data)?.minSupportedBuild
            eventSink.yield(.updateRequired(minSupportedBuild: min))
            throw APIError.updateRequired(minSupportedBuild: min)
        default:
            throw httpError(data, response)
        }
    }

    private func perform(_ request: APIRequest, accessToken: String?) async throws -> (Data, HTTPURLResponse) {
        var url = baseURL.appendingPathComponent("api")
        url.append(path: request.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
        if !request.query.isEmpty {
            url.append(queryItems: request.query)
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = request.method.rawValue
        urlRequest.setValue(Self.clientKind, forHTTPHeaderField: "x-client")
        urlRequest.setValue(String(clientBuild), forHTTPHeaderField: "x-client-build")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        if let accessToken {
            urlRequest.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }
        if let body = request.body {
            urlRequest.httpBody = body
            urlRequest.setValue(request.contentType ?? "application/json", forHTTPHeaderField: "Content-Type")
        }

        do {
            return try await transport.send(urlRequest)
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.transport(error.localizedDescription)
        }
    }

    // MARK: - Session

    private func validAccessToken() async throws -> String {
        guard let tokens else { throw APIError.notSignedIn }
        if tokens.accessTokenExpiresAt.timeIntervalSince(now()) > Self.refreshLeeway {
            return tokens.accessToken
        }
        return try await refreshSession().accessToken
    }

    /// Single flight: concurrent callers share one `/tenant/auth/refresh`, because the server
    /// rotates the refresh token and a second use of the old one is rejected.
    @discardableResult
    public func refreshSession() async throws -> SessionTokens {
        if let refreshTask {
            return try await refreshTask.value
        }
        guard let current = tokens else { throw APIError.notSignedIn }

        let task = Task { try await self.performRefresh(using: current.refreshToken) }
        refreshTask = task
        defer { refreshTask = nil }
        return try await task.value
    }

    private func performRefresh(using refreshToken: String) async throws -> SessionTokens {
        let body = try TenantJSON.encoder().encode(RefreshRequest(refreshToken: refreshToken))
        let request = APIRequest(.post, "/tenant/auth/refresh", body: body, requiresAuth: false)
        let (data, response) = try await perform(request, accessToken: nil)

        switch response.statusCode {
        case 200..<300:
            let decoded: RefreshResponse
            do {
                decoded = try TenantJSON.decoder().decode(RefreshResponse.self, from: data)
            } catch {
                throw APIError.decoding(String(describing: error))
            }
            store(decoded.tokens)
            return decoded.tokens
        case 426:
            let min = decodeError(data)?.minSupportedBuild
            eventSink.yield(.updateRequired(minSupportedBuild: min))
            throw APIError.updateRequired(minSupportedBuild: min)
        case 400, 401, 403:
            // The refresh token itself was refused: expired, revoked, or the tenant is no longer eligible.
            let body = decodeError(data)
            await endSession(reason: body?.code)
            throw APIError.unauthorized(code: body?.code, message: body?.text ?? "Session expired")
        default:
            // 429 / 5xx: keep the session, the next request will try again.
            throw httpError(data, response)
        }
    }

    /// Keeps new tokens in memory and in the store (used by the auth endpoints after sign-in).
    func store(_ newTokens: SessionTokens) {
        tokens = newTokens
        try? tokenStore.save(newTokens)
    }

    /// Forgets the session locally without telling anyone (sign-out already did).
    func clearSession() {
        tokens = nil
        try? tokenStore.clear()
    }

    /// The stored refresh token, for `/tenant/auth/logout`.
    var currentRefreshToken: String? { tokens?.refreshToken }

    private func endSession(reason: String?) async {
        guard tokens != nil else { return }
        clearSession()
        eventSink.yield(.sessionEnded(reason: reason))
    }

    /// Sends without the session machinery — for sign-out, which must not trigger a refresh.
    func performUnauthenticated(_ request: APIRequest) async throws -> (Data, HTTPURLResponse) {
        try await perform(request, accessToken: nil)
    }

    // MARK: - Helpers

    private func decodeError(_ data: Data) -> ServerErrorBody? {
        try? JSONDecoder().decode(ServerErrorBody.self, from: data)
    }

    private func httpError(_ data: Data, _ response: HTTPURLResponse) -> APIError {
        let body = decodeError(data)
        return .http(
            status: response.statusCode,
            message: body?.text ?? HTTPURLResponse.localizedString(forStatusCode: response.statusCode),
            code: body?.code,
            field: body?.field
        )
    }
}
