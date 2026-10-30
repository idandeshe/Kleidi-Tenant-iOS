import SwiftUI
import TenantAPI
import TenantCore

/// The language chosen on the first screen (changeable in Profile). Stored in
/// `UserDefaults` under `language`; empty = never chosen, so the language screen shows.
enum LanguageSetting {
    static let key = "language"

    static var current: AppLanguage? {
        AppLanguage(rawValue: UserDefaults.standard.string(forKey: key) ?? "")
    }

    static func set(_ language: AppLanguage) {
        UserDefaults.standard.set(language.rawValue, forKey: key)
    }
}

private struct L10nKey: EnvironmentKey {
    static let defaultValue = L10n(language: .deviceDefault())
}

extension EnvironmentValues {
    /// Strings in the chosen language; `RootView` sets it for the whole tree.
    var l10n: L10n {
        get { self[L10nKey.self] }
        set { self[L10nKey.self] = newValue }
    }
}

extension L10n {
    /// Text fit for an alert or inline notice, for any error a screen may catch.
    /// Known server codes (`INVALID_CODE`…) have their own copy; other server messages
    /// are shown as sent; 5xx and network failures get a generic line.
    func message(for error: Error) -> String {
        guard let apiError = error as? APIError else { return error.localizedDescription }
        switch apiError {
        case .notSignedIn:
            return self["error.notSignedIn"]
        case .updateRequired:
            return self["update.body"]
        case .transport:
            return self["error.offline"]
        case .decoding:
            return self["error.decoding"]
        case .unauthorized(let code, let message), .http(_, let message, let code, _):
            if let code, let known = knownCode(code) { return known }
            if let status = apiError.status, status >= 500 { return self["error.server"] }
            return message
        }
    }

    private func knownCode(_ code: String) -> String? {
        let key = "error.code.\(code)"
        let text = self[key]
        return text == key ? nil : text
    }
}
