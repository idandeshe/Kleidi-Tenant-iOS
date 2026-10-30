// Mirrors the enums of server/types/tenantIssues.types.ts (`TenantIssueCategory`,
// `TenantIssueStatus`, `TenantIssueMessageKind`, `TenantIssueActorKind`) and the tenant-side
// limits (`TENANT_ISSUES_VALIDATION`, `TENANT_ISSUE_PHOTO_MIME_TYPES`). Like RentValues, the
// values decode as open strings so a category or status added on the server never crashes an
// older app; an unknown value shows its raw value as the label and a generic icon.

import Foundation

/// What a reported issue is about — the six tiles of the "Report an issue" grid.
public struct TenantIssueCategory: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let plumbing = TenantIssueCategory(rawValue: "plumbing")
    public static let electrical = TenantIssueCategory(rawValue: "electrical")
    public static let heatingAC = TenantIssueCategory(rawValue: "heating_ac")
    public static let doorsLocks = TenantIssueCategory(rawValue: "doors_locks")
    public static let building = TenantIssueCategory(rawValue: "building")
    public static let other = TenantIssueCategory(rawValue: "other")

    /// Every category the server accepts, in the order of the report grid (`TENANT_ISSUE_CATEGORIES`).
    public static let all: [TenantIssueCategory] = [.plumbing, .electrical, .heatingAC, .doorsLocks, .building, .other]

    /// A value this build knows; a newer server's category still decodes but is drawn generically.
    public var isKnown: Bool { Self.all.contains(self) }

    /// The Localizable key of the label ("issues.category.plumbing").
    public var labelKey: String { "issues.category.\(rawValue)" }

    /// "Plumbing" / "Υδραυλικά"; an unknown value shows its raw value.
    public func label(_ l10n: L10n) -> String {
        let text = l10n[labelKey]
        return text == labelKey ? rawValue : text
    }

    /// The SF Symbol of the category tile (the approved mock-up); a question mark for an unknown value.
    public var symbolName: String {
        switch self {
        case .plumbing: return "drop.fill"
        case .electrical: return "bolt.fill"
        case .heatingAC: return "thermometer.medium"
        case .doorsLocks: return "lock.fill"
        case .building: return "building.2.fill"
        default: return "questionmark.circle"
        }
    }
}

/// Where an issue stands: `new` = received, nobody has answered yet; `in_progress` = staff are
/// on it; `resolved` = fixed; `closed` = ended without a fix (`closeReason` says why). The
/// tenant never changes it — they report again.
public struct TenantIssueStatus: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let new = TenantIssueStatus(rawValue: "new")
    public static let inProgress = TenantIssueStatus(rawValue: "in_progress")
    public static let resolved = TenantIssueStatus(rawValue: "resolved")
    public static let closed = TenantIssueStatus(rawValue: "closed")

    /// The thread is live (`TENANT_ISSUE_OPEN_STATUSES`): the "Open" list group.
    public var isOpen: Bool { self == .new || self == .inProgress }

    /// The Localizable key of the tenant wording ("issues.status.new" → "Received").
    public var labelKey: String { "issues.status.\(rawValue)" }

    /// "Received" / "Παραλήφθηκε"…; an unknown value shows its raw value.
    public func label(_ l10n: L10n) -> String {
        let text = l10n[labelKey]
        return text == labelKey ? rawValue : text
    }
}

/// A thread entry is a message (`text`) or a status change (`status`).
public struct TenantIssueMessageKind: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let text = TenantIssueMessageKind(rawValue: "text")
    public static let status = TenantIssueMessageKind(rawValue: "status")
}

/// Who wrote a thread entry. Staff are shown as "Property manager" — never a name.
public struct TenantIssueActor: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let tenant = TenantIssueActor(rawValue: "tenant")
    public static let staff = TenantIssueActor(rawValue: "staff")
}

/// Server-side limits of an issue's photos and texts (`TENANT_ISSUES_VALIDATION`,
/// `TENANT_ISSUE_PHOTO_MIME_TYPES`). Images only: the app re-encodes HEIC to JPEG.
public enum IssuePhotoRules {
    public static let maxBytes = 10 * 1024 * 1024
    public static let mimeTypes: Set<String> = ["image/jpeg", "image/png", "image/webp"]
    public static let maxReportPhotos = 5
    public static let maxReplyPhotos = 3
    public static let descriptionMaxLength = 2000
    public static let messageMaxLength = 2000

    public static func accepts(mimeType: String) -> Bool { mimeTypes.contains(mimeType.lowercased()) }

    /// MIME type for a file picked from Files; nil when the server would refuse it (PDFs included).
    public static func mimeType(forExtension ext: String) -> String? {
        switch ext.lowercased() {
        case "jpg", "jpeg": return "image/jpeg"
        case "png": return "image/png"
        case "webp": return "image/webp"
        default: return nil
        }
    }
}
