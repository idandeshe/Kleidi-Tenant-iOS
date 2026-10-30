import Foundation

/// Which Kleidi server this build talks to. The base URL comes from Info.plist
/// (`KleidiAPIBaseURL`, set per build configuration in Config/*.xcconfig).
/// Dev and stage builds may override it from the Profile screen.
struct ServerEnvironment: Equatable {
    enum Kind: String { case dev, stage, prod }

    let kind: Kind
    let baseURL: URL

    /// Build number sent as `x-client-build`; the server's forced-update gate compares against it.
    static var clientBuild: Int {
        Int(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "") ?? 0
    }

    static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }

    var allowsServerOverride: Bool { kind != .prod }

    /// Keychain account: one stored session per server, so switching server never reuses a token.
    var tokenAccount: String { baseURL.absoluteString }

    private static let overrideKey = "serverOverrideURL"

    static var current: ServerEnvironment {
        let info = Bundle.main.infoDictionary ?? [:]
        let kind = Kind(rawValue: info["KleidiEnvironment"] as? String ?? "") ?? .prod
        let configured = URL(string: info["KleidiAPIBaseURL"] as? String ?? "") ?? URL(string: "http://localhost:3000")!
        if kind != .prod,
           let override = UserDefaults.standard.string(forKey: overrideKey),
           let url = URL(string: override) {
            return ServerEnvironment(kind: kind, baseURL: url)
        }
        return ServerEnvironment(kind: kind, baseURL: configured)
    }

    /// Dev / stage only. `nil` goes back to the configured server.
    static func setOverride(_ url: URL?) {
        if let url {
            UserDefaults.standard.set(url.absoluteString, forKey: overrideKey)
        } else {
            UserDefaults.standard.removeObject(forKey: overrideKey)
        }
    }
}
