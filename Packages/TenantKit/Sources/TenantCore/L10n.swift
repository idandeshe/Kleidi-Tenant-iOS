import Foundation

/// String lookup in the chosen language, independent of the device language.
///
/// Reads `Localizable.xcstrings` through the language's own `.lproj` bundle, so a tenant
/// who picks Greek on an English phone (or switches in Profile) sees the change at once,
/// without restarting the app. Keys are stable identifiers (`home.rent.title`), never
/// English text, so both `en` and `el` need an entry in the catalog. A missing key shows
/// the key itself — easy to spot in a build.
public struct L10n: Sendable, Equatable {
    public let language: AppLanguage
    private let bundlePath: String?

    public init(language: AppLanguage, bundle: Bundle = .main) {
        self.language = language
        self.bundlePath = bundle.path(forResource: language.rawValue, ofType: "lproj")
    }

    public subscript(_ key: String) -> String { string(key) }

    public func string(_ key: String) -> String {
        // `Bundle(path:)` returns the cached instance for a path already loaded.
        let bundle = bundlePath.flatMap(Bundle.init(path:)) ?? Bundle.main
        return bundle.localizedString(forKey: key, value: key, table: "Localizable")
    }

    /// A `String(format:)` entry: `%@`, `%d` placeholders, formatted for the language's locale.
    public func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: string(key), locale: language.locale, arguments: arguments)
    }
}
