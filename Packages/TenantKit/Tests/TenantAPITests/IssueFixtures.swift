import Foundation

/// A nullable JSON field: the string, or `null`.
private func orNull(_ value: String?) -> Any {
    value.map { $0 as Any } ?? NSNull()
}

/// JSON the tenant issues routes answer with (server/types/tenantIssues.types.ts
/// `TenantIssueOwnResponse`, `TenantIssueOwnMessageResponse`, `TenantIssueOwnDetailResponse`).
func issueJSON(_ id: String = "i1", category: String = "plumbing", status: String = "in_progress",
               isUrgent: Bool = false, tenantUnread: Bool = false, photoDocumentIds: [String] = ["d1", "d2"],
               closeReason: String? = nil, resolvedAt: String? = nil, closedAt: String? = nil) -> [String: Any] {
    [
        "id": id,
        "leaseId": "l1",
        "category": category,
        "summary": "Kitchen tap dripping",
        "description": "The kitchen tap has been dripping since Monday, even when fully closed.",
        "isUrgent": isUrgent,
        "photoDocumentIds": photoDocumentIds,
        "status": status,
        "closeReason": orNull(closeReason),
        "resolvedAt": orNull(resolvedAt),
        "closedAt": orNull(closedAt),
        "lastActivityAt": "2026-10-28T10:31:00.000Z",
        "tenantUnread": tenantUnread,
        "canReply": status == "new" || status == "in_progress",
        "createdAt": "2026-10-27T18:42:00.000Z",
    ]
}

func issueMessageJSON(_ id: String, kind: String = "text", author: String = "staff", body: String? = nil,
                      status: String? = nil, closeReason: String? = nil, photoDocumentIds: [String] = [],
                      createdAt: String = "2026-10-28T10:15:00.000Z") -> [String: Any] {
    [
        "id": id,
        "kind": kind,
        "author": author,
        "body": orNull(body),
        "status": orNull(status),
        "closeReason": orNull(closeReason),
        "photoDocumentIds": photoDocumentIds,
        "createdAt": createdAt,
    ]
}

/// The thread of the mock-up: the staff answer, the move to "in progress", the tenant's reply with a photo.
func issueDetailJSON(_ id: String = "i1", status: String = "in_progress") -> [String: Any] {
    var detail = issueJSON(id, status: status)
    detail["messages"] = [
        issueMessageJSON("m1", author: "staff", body: "A plumber is booked for Thursday 09:00–11:00. Will someone be home?"),
        issueMessageJSON("m2", kind: "status", author: "staff", status: "in_progress", createdAt: "2026-10-28T10:16:00.000Z"),
        issueMessageJSON("m3", author: "tenant", body: "Yes, I will be home all morning.", photoDocumentIds: ["d3"],
                         createdAt: "2026-10-28T10:31:00.000Z"),
    ]
    return detail
}

func issuesListJSON() -> [String: Any] {
    [
        "data": [
            issueJSON("i1", status: "in_progress", tenantUnread: true),
            issueJSON("i2", category: "electrical", status: "new", isUrgent: true, photoDocumentIds: []),
            issueJSON("i3", category: "doors_locks", status: "resolved", photoDocumentIds: [], resolvedAt: "2026-09-12T09:00:00.000Z"),
            issueJSON("i4", category: "other", status: "closed", photoDocumentIds: [], closeReason: "Not covered by the lease",
                      closedAt: "2026-08-01T09:00:00.000Z"),
        ],
    ]
}
