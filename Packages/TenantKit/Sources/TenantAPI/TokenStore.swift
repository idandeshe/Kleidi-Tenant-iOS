import Foundation
#if canImport(Security)
import Security
#endif

/// Where the session tokens live between launches.
public protocol TokenStore: Sendable {
    func load() throws -> SessionTokens?
    func save(_ tokens: SessionTokens) throws
    func clear() throws
}

/// For tests and previews.
public final class InMemoryTokenStore: TokenStore, @unchecked Sendable {
    private let lock = NSLock()
    private var tokens: SessionTokens?

    public init(_ tokens: SessionTokens? = nil) { self.tokens = tokens }

    public func load() throws -> SessionTokens? { lock.withLock { tokens } }
    public func save(_ tokens: SessionTokens) throws { lock.withLock { self.tokens = tokens } }
    public func clear() throws { lock.withLock { tokens = nil } }
}

#if canImport(Security)
/// Keychain item readable only on this device after its first unlock: excluded
/// from backups and from moving to a new phone.
public struct KeychainTokenStore: TokenStore {
    private let service: String
    private let account: String

    /// `account` separates environments (dev / stage / prod) so switching server never reuses a token.
    public init(service: String = "app.kleidi.tenant.session", account: String) {
        self.service = service
        self.account = account
    }

    private var query: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    public func load() throws -> SessionTokens? {
        var q = query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else { throw KeychainError(status: status) }
        return try TenantJSON.decoder().decode(SessionTokens.self, from: data)
    }

    public func save(_ tokens: SessionTokens) throws {
        let data = try TenantJSON.encoder().encode(tokens)
        let update: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var add = query
            add.merge(update) { $1 }
            let addStatus = SecItemAdd(add as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainError(status: addStatus) }
        } else if status != errSecSuccess {
            throw KeychainError(status: status)
        }
    }

    public func clear() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError(status: status) }
    }
}

public struct KeychainError: Error, Sendable {
    public let status: OSStatus
}
#endif
