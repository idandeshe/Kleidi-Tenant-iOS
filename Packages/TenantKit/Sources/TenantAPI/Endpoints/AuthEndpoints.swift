// `/api/tenant/auth/*` and `/api/tenant/config` (server/routes/tenant/auth, server/routes/tenant/config).

import Foundation

extension APIClient {
    /// `GET /tenant/config` — public; exempt from the 426 gate, so it is safe to call first.
    public func config() async throws -> TenantConfig {
        try await send(APIRequest(.get, "/tenant/config", requiresAuth: false))
    }

    /// Asks for a 6-digit SMS code. The answer is the same for any well-formed number, so a
    /// 200 does not mean the number belongs to a tenant. 400 = bad phone, 503 = SMS off.
    public func requestCode(phone: String) async throws -> RequestCodeResponse {
        let body = try TenantJSON.encoder().encode(RequestCodeRequest(phone: phone))
        return try await send(APIRequest(.post, "/tenant/auth/request-code", body: body, requiresAuth: false))
    }

    /// Exchanges the code for a session. 401 `INVALID_CODE` / `CODE_EXPIRED` / `TOO_MANY_ATTEMPTS`,
    /// 403 `NOT_A_TENANT` — all surface as `APIError` with that `code`.
    public func verifyCode(phone: String, code: String) async throws -> Tenant {
        let body = try TenantJSON.encoder().encode(VerifyCodeRequest(phone: phone, code: code))
        let response: VerifyCodeResponse = try await send(
            APIRequest(.post, "/tenant/auth/verify-code", body: body, requiresAuth: false))
        store(response.tokens)
        return response.tenant
    }

    public func session() async throws -> TenantSessionResponse {
        try await send(APIRequest(.get, "/tenant/auth/session"))
    }

    /// Revokes this device's refresh token. Local sign-out happens even when offline.
    public func logout() async {
        if let refreshToken = currentRefreshToken,
           let body = try? TenantJSON.encoder().encode(RefreshRequest(refreshToken: refreshToken)) {
            _ = try? await performUnauthenticated(
                APIRequest(.post, "/tenant/auth/logout", body: body, requiresAuth: false))
        }
        clearSession()
    }

    /// Revokes every session of this tenant — other phones and the web included.
    @discardableResult
    public func logoutAll() async throws -> Int {
        let response: LogoutAllResponse = try await send(APIRequest(.post, "/tenant/auth/logout-all"))
        clearSession()
        return response.revokedCount
    }
}
