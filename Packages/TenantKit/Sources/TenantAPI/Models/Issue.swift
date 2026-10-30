// Mirrors the tenant responses of server/types/tenantIssues.types.ts (`TenantIssueOwnResponse`,
// `TenantIssueOwnMessageResponse`, `TenantIssueOwnDetailResponse`) and the multipart bodies of
// `POST /tenant/leases/:id/issues` and `POST /tenant/issues/:id/messages`. Deliberately narrow:
// no staff identity ever reaches the app — staff are "Property manager".

import Foundation
import TenantCore

/// One reported issue as the tenant sees it in the list and at the top of its thread.
public struct TenantIssue: Decodable, Sendable, Hashable, Identifiable {
    public let id: String
    public let leaseId: String
    public let category: TenantIssueCategory
    /// First line of the description, cut by the server (the list title).
    public let summary: String
    public let description: String
    public let isUrgent: Bool
    /// Lease documents attached to the report (0–5); fetched with `issuePhoto(issueId:documentId:)`.
    public let photoDocumentIds: [String]
    public let status: TenantIssueStatus
    /// Why the issue was closed without a fix — only with `status: closed`.
    public let closeReason: String?
    public let resolvedAt: Date?
    public let closedAt: Date?
    /// Last tenant-visible event: the report, a message, a status change.
    public let lastActivityAt: Date
    /// Staff did something since the tenant last opened the issue (the dot in the list).
    public let tenantUnread: Bool
    /// The issue is open: the tenant may post.
    public let canReply: Bool
    public let createdAt: Date

    public init(id: String, leaseId: String, category: TenantIssueCategory, summary: String, description: String,
                isUrgent: Bool, photoDocumentIds: [String], status: TenantIssueStatus, closeReason: String?,
                resolvedAt: Date?, closedAt: Date?, lastActivityAt: Date, tenantUnread: Bool, canReply: Bool, createdAt: Date) {
        self.id = id
        self.leaseId = leaseId
        self.category = category
        self.summary = summary
        self.description = description
        self.isUrgent = isUrgent
        self.photoDocumentIds = photoDocumentIds
        self.status = status
        self.closeReason = closeReason
        self.resolvedAt = resolvedAt
        self.closedAt = closedAt
        self.lastActivityAt = lastActivityAt
        self.tenantUnread = tenantUnread
        self.canReply = canReply
        self.createdAt = createdAt
    }
}

/// A thread entry: a tenant or staff message (`kind: text`) or a status change (`kind: status`).
public struct TenantIssueMessage: Decodable, Sendable, Hashable, Identifiable {
    public let id: String
    public let kind: TenantIssueMessageKind
    /// `staff` is shown as "Property manager" — never a name.
    public let author: TenantIssueActor
    public let body: String?
    /// For `kind: status`: the status the issue moved to.
    public let status: TenantIssueStatus?
    /// For a `closed` status event: the reason shown to the tenant.
    public let closeReason: String?
    /// Tenant photos attached to a text message (0–3). Staff messages carry none.
    public let photoDocumentIds: [String]
    public let createdAt: Date

    public init(id: String, kind: TenantIssueMessageKind, author: TenantIssueActor, body: String?, status: TenantIssueStatus?,
                closeReason: String?, photoDocumentIds: [String], createdAt: Date) {
        self.id = id
        self.kind = kind
        self.author = author
        self.body = body
        self.status = status
        self.closeReason = closeReason
        self.photoDocumentIds = photoDocumentIds
        self.createdAt = createdAt
    }

    public var isStatusEvent: Bool { kind == .status }
    public var isFromTenant: Bool { author == .tenant }
}

/// `GET /tenant/issues/:id` (and the 201 of a report): the issue's own fields plus `messages`,
/// tenant-visible entries oldest first. Decoded from the flat object the server sends.
public struct TenantIssueDetail: Decodable, Sendable, Hashable, Identifiable {
    public let issue: TenantIssue
    public let messages: [TenantIssueMessage]

    public var id: String { issue.id }

    public init(issue: TenantIssue, messages: [TenantIssueMessage]) {
        self.issue = issue
        self.messages = messages
    }

    private enum CodingKeys: String, CodingKey { case messages }

    public init(from decoder: Decoder) throws {
        issue = try TenantIssue(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        messages = try container.decodeIfPresent([TenantIssueMessage].self, forKey: .messages) ?? []
    }
}

/// `GET /tenant/issues` → `{ data }`.
struct TenantIssuesResponse: Decodable, Sendable {
    let data: [TenantIssue]
}

/// What the tenant fills in on "Report an issue" (`ReportTenantIssueDto`); the photos travel beside it.
public struct ReportIssueDraft: Sendable, Equatable {
    public var category: TenantIssueCategory
    public var description: String
    public var isUrgent: Bool

    public init(category: TenantIssueCategory, description: String, isUrgent: Bool = false) {
        self.category = category
        self.description = description
        self.isUrgent = isUrgent
    }

    /// The multipart body: text fields first (the server reads them before the files), then
    /// every photo as a `photo` part, in the order given.
    public func form(photos: [UploadFile], boundary: String = "kleidi-\(UUID().uuidString)") -> MultipartForm {
        var form = MultipartForm(boundary: boundary)
        form.addField("category", category.rawValue)
        form.addField("description", description.trimmingCharacters(in: .whitespacesAndNewlines))
        form.addField("isUrgent", isUrgent ? "true" : "false")
        for photo in photos {
            form.addFile("photo", fileName: photo.fileName, mimeType: photo.mimeType, contents: photo.data)
        }
        return form
    }
}

/// A tenant reply in an open thread (`TenantIssueReplyDto`): a text, photos, or both.
public struct IssueReplyDraft: Sendable, Equatable {
    public var body: String?

    public init(body: String? = nil) {
        self.body = body
    }

    /// The trimmed text, nil when there is none.
    public var trimmedBody: String? {
        let text = body?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return text.isEmpty ? nil : text
    }

    /// The multipart body: `body` (only when there is text) before the `photo` parts.
    public func form(photos: [UploadFile], boundary: String = "kleidi-\(UUID().uuidString)") -> MultipartForm {
        var form = MultipartForm(boundary: boundary)
        if let text = trimmedBody {
            form.addField("body", text)
        }
        for photo in photos {
            form.addFile("photo", fileName: photo.fileName, mimeType: photo.mimeType, contents: photo.data)
        }
        return form
    }
}
