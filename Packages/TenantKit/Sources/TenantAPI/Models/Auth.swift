// Mirrors server/types/tenantAuth.types.ts (native transport: tokens in the body).

import Foundation

public struct SessionTokens: Codable, Sendable, Equatable {
    public let accessToken: String
    public let accessTokenExpiresAt: Date
    public let refreshToken: String
    public let refreshTokenExpiresAt: Date

    public init(accessToken: String, accessTokenExpiresAt: Date, refreshToken: String, refreshTokenExpiresAt: Date) {
        self.accessToken = accessToken
        self.accessTokenExpiresAt = accessTokenExpiresAt
        self.refreshToken = refreshToken
        self.refreshTokenExpiresAt = refreshTokenExpiresAt
    }
}

/// `POST /tenant/auth/request-code` — the same answer whether or not the number is a tenant's.
public struct RequestCodeResponse: Decodable, Sendable, Equatable {
    public let message: String
    /// How long the code stays valid (300), for the countdown on the code screen.
    public let expiresInSeconds: Int
}

public struct TenantSessionResponse: Decodable, Sendable, Equatable {
    public let tenant: Tenant
    public let expiresAt: Date
}

struct RequestCodeRequest: Encodable {
    let phone: String
}

struct VerifyCodeRequest: Encodable {
    let phone: String
    let code: String
}

struct VerifyCodeResponse: Decodable, Sendable {
    let tenant: Tenant
    let message: String
    let tokens: SessionTokens
}

struct RefreshRequest: Encodable {
    let refreshToken: String
}

struct RefreshResponse: Decodable, Sendable {
    let message: String
    let tokens: SessionTokens
}

struct LogoutAllResponse: Decodable, Sendable {
    let message: String
    let revokedCount: Int
}
