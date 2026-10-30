// Mirrors `TenantConfigResponse` in server/types/tenantAuth.types.ts.

import Foundation

/// `GET /tenant/config` — public; read before sign-in for the forced update and the SMS state.
public struct TenantConfig: Decodable, Sendable, Equatable {
    public struct IOS: Decodable, Sendable, Equatable {
        /// 0 = no minimum.
        public let minSupportedBuild: Int
        public let appStoreUrl: String?
    }

    /// Bumped by the server only on a change that breaks native tenant clients.
    public let apiVersion: Int
    public let serverVersion: String
    /// False = no SMS provider: sign-in cannot send codes (the server answers 503).
    public let smsConfigured: Bool
    /// Web-only (Turnstile captcha); native apps skip it.
    public let turnstileSiteKey: String?
    public let ios: IOS

    public func requiresUpdate(build: Int) -> Bool {
        ios.minSupportedBuild > 0 && build < ios.minSupportedBuild
    }

    public var appStoreURL: URL? { ios.appStoreUrl.flatMap(URL.init(string:)) }
}
