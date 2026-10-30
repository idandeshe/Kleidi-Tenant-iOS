import Foundation

/// Error codes the server sends in `{ code }` (server/types/tenantAuth.types.ts
/// TENANT_AUTH_ERROR_CODES, plus the native-client update gate).
public enum ServerErrorCode {
    public static let invalidCode = "INVALID_CODE"
    public static let codeExpired = "CODE_EXPIRED"
    public static let tooManyAttempts = "TOO_MANY_ATTEMPTS"
    public static let notATenant = "NOT_A_TENANT"
    public static let tokenExpired = "TOKEN_EXPIRED"
    public static let tokenRevoked = "TOKEN_REVOKED"
    public static let smsNotConfigured = "SMS_NOT_CONFIGURED"
    public static let appUpdateRequired = "APP_UPDATE_REQUIRED"
}

public enum APIError: Error, Sendable, Equatable {
    /// No stored session: the tenant has to sign in.
    case notSignedIn
    /// 401 the session could not recover from (refresh refused, or the code was rejected).
    case unauthorized(code: String?, message: String)
    /// 426 — this build is older than the server's `TENANT_IOS_MIN_SUPPORTED_BUILD`.
    case updateRequired(minSupportedBuild: Int?)
    /// Any other non-2xx answer. `message` is the server's `message` or `error` field (English).
    case http(status: Int, message: String, code: String?, field: String?)
    /// The request never got an HTTP answer (offline, timeout, TLS…).
    case transport(String)
    /// The server answered 2xx with a body this build cannot decode.
    case decoding(String)

    public var status: Int? {
        switch self {
        case .unauthorized: return 401
        case .updateRequired: return 426
        case .http(let status, _, _, _): return status
        default: return nil
        }
    }

    /// The server's `code`, whichever case carries it.
    public var code: String? {
        switch self {
        case .unauthorized(let code, _): return code
        case .updateRequired: return ServerErrorCode.appUpdateRequired
        case .http(_, _, let code, _): return code
        default: return nil
        }
    }

    /// The server's own text, when there is one (the app localizes known codes itself).
    public var serverMessage: String? {
        switch self {
        case .unauthorized(_, let message), .http(_, let message, _, _): return message
        default: return nil
        }
    }
}

/// `{ error, message?, code?, field?, minSupportedBuild? }` — the server's error body.
struct ServerErrorBody: Decodable {
    let error: String?
    let message: String?
    let code: String?
    let field: String?
    let minSupportedBuild: Int?

    var text: String? { message ?? error }
}
