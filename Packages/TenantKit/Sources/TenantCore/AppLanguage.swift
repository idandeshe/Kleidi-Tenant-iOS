import Foundation

/// The language of the tenant app's copy. Mirrors `TenantLanguage` on the server
/// (server/types/tenants.types.ts): Greek or English, nothing else.
public enum AppLanguage: String, CaseIterable, Codable, Sendable, Identifiable {
    case el
    case en

    public var id: String { rawValue }

    /// The language's own name, as shown on the language screen.
    public var nativeName: String {
        switch self {
        case .el: return "Ελληνικά"
        case .en: return "English"
        }
    }

    /// Locale for month names, number grouping and ordinals in this language.
    public var locale: Locale {
        switch self {
        case .el: return Locale(identifier: "el_GR")
        case .en: return Locale(identifier: "en_GB")
        }
    }

    /// What the language screen pre-highlights: Greek unless the device speaks English.
    public static func deviceDefault(preferredLanguages: [String] = Locale.preferredLanguages) -> AppLanguage {
        guard let first = preferredLanguages.first?.lowercased() else { return .el }
        return first.hasPrefix("en") ? .en : .el
    }
}
