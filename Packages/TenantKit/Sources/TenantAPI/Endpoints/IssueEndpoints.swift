// `/api/tenant/issues`, `POST /api/tenant/leases/:id/issues`, `/api/tenant/issues/:id`,
// `POST /api/tenant/issues/:id/messages` and `/api/tenant/issues/:id/photos/:documentId`
// (server/routes/tenant/issues, server/routes/tenant/leases/_id/issues). Photos are images
// only, 10 MB each: up to 5 on the report, up to 3 on a reply.

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import TenantCore

extension APIClient {
    /// The tenant's issues, open ones first, then by last activity (newest first). Pass a
    /// lease to see that lease's only.
    public func issues(leaseId: String? = nil) async throws -> [TenantIssue] {
        let query = leaseId.map { [URLQueryItem(name: "leaseId", value: $0)] } ?? []
        let response: TenantIssuesResponse = try await send(APIRequest(.get, "/tenant/issues", query: query))
        return response.data
    }

    /// "Send to property manager". 400 `{ error, field }`, 404 (not the tenant's lease),
    /// 413 a photo too large, 415 unsupported type — all `APIError.http` with that status.
    /// Rate-limited to 5 per 10 minutes (429). The 201 body is the new issue with its thread.
    public func reportIssue(leaseId: String, draft: ReportIssueDraft, photos: [UploadFile],
                            boundary: String = "kleidi-\(UUID().uuidString)") async throws -> TenantIssueDetail {
        let form = draft.form(photos: photos, boundary: boundary)
        return try await send(APIRequest(
            .post, "/tenant/leases/\(leaseId)/issues", body: form.body, contentType: form.contentType))
    }

    /// One issue with its tenant-visible thread, oldest entry first. Opening it marks the
    /// issue seen (the server clears `tenantUnread`).
    public func issue(id: String) async throws -> TenantIssueDetail {
        try await send(APIRequest(.get, "/tenant/issues/\(id)"))
    }

    /// A reply in an open thread: text, photos or both. 409 when the issue is resolved / closed
    /// (`canReply` false) — the screen then shows the closed note.
    public func replyToIssue(id: String, draft: IssueReplyDraft, photos: [UploadFile],
                             boundary: String = "kleidi-\(UUID().uuidString)") async throws -> TenantIssueMessage {
        let form = draft.form(photos: photos, boundary: boundary)
        return try await send(APIRequest(
            .post, "/tenant/issues/\(id)/messages", body: form.body, contentType: form.contentType))
    }

    /// A photo attached to the report or to a message (`Content-Type` image/*).
    public func issuePhoto(issueId: String, documentId: String) async throws -> DownloadedFile {
        try await downloadFile("/tenant/issues/\(issueId)/photos/\(documentId)")
    }
}
