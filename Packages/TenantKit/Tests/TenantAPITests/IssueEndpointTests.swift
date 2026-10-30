import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
import TenantCore
@testable import TenantAPI

@Suite struct IssueEndpointTests {
    private func client(_ transport: ScriptedTransport) -> APIClient {
        APIClient(baseURL: baseURL, clientBuild: 1, transport: transport, tokenStore: InMemoryTokenStore(storedTokens("a")))
    }

    /// The `name=` of each part, in order, as the server will read them.
    private func partNames(_ request: URLRequest, boundary: String) -> [String] {
        let body = String(data: request.httpBody ?? Data(), encoding: .utf8) ?? ""
        return body.components(separatedBy: "--\(boundary)\r\n").dropFirst()
            .map { $0.components(separatedBy: "\r\n")[0].replacingOccurrences(of: "Content-Disposition: form-data; name=", with: "") }
    }

    @Test func listUsesBearerAndFiltersByLease() async throws {
        let transport = ScriptedTransport { _ in (200, json(issuesListJSON())) }
        let client = client(transport)

        let issues = try await client.issues(leaseId: "l1")

        #expect(issues.map(\.id) == ["i1", "i2", "i3", "i4"])
        let request = try #require(transport.requests.first)
        #expect(request.httpMethod == "GET")
        #expect(request.url?.path == "/api/tenant/issues")
        #expect(request.url?.query == "leaseId=l1")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer access-a")
    }

    @Test func listWithoutALeaseHasNoQuery() async throws {
        let transport = ScriptedTransport { _ in (200, json(["data": []])) }

        let issues = try await client(transport).issues()

        #expect(issues.isEmpty)
        #expect(transport.requests.first?.url?.query == nil)
        #expect(transport.requests.first?.url?.absoluteString == "https://kleidi.test/api/tenant/issues")
    }

    @Test func reportSendsTextPartsBeforeThePhotos() async throws {
        let transport = ScriptedTransport { _ in (201, json(issueDetailJSON("i9", status: "new"))) }
        let client = client(transport)
        let draft = ReportIssueDraft(category: .plumbing, description: "  Tap dripping  ", isUrgent: true)
        let photos = [
            UploadFile(data: Data("JPEG1".utf8), fileName: "Photo 1.jpg", mimeType: "image/jpeg"),
            UploadFile(data: Data("PNG2".utf8), fileName: "Photo 2.png", mimeType: "image/png"),
            UploadFile(data: Data("WEBP3".utf8), fileName: "Photo 3.webp", mimeType: "image/webp"),
        ]

        let created = try await client.reportIssue(leaseId: "l1", draft: draft, photos: photos, boundary: "B")

        #expect(created.id == "i9")
        #expect(created.issue.status == .new)
        #expect(created.messages.count == 3)
        let request = try #require(transport.requests.first)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path == "/api/tenant/leases/l1/issues")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "multipart/form-data; boundary=B")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer access-a")
        // The server reads the text fields from the parts before the files: fields first, every photo after.
        #expect(partNames(request, boundary: "B") == [
            "\"category\"", "\"description\"", "\"isUrgent\"",
            "\"photo\"; filename=\"Photo 1.jpg\"", "\"photo\"; filename=\"Photo 2.png\"", "\"photo\"; filename=\"Photo 3.webp\"",
        ])
        let body = String(data: request.httpBody ?? Data(), encoding: .utf8) ?? ""
        #expect(body.contains("name=\"category\"\r\n\r\nplumbing\r\n"))
        #expect(body.contains("name=\"description\"\r\n\r\nTap dripping\r\n"))
        #expect(body.contains("name=\"isUrgent\"\r\n\r\ntrue\r\n"))
        #expect(body.contains("filename=\"Photo 2.png\"\r\nContent-Type: image/png\r\n\r\nPNG2\r\n"))
        #expect(body.hasSuffix("WEBP3\r\n--B--\r\n"))
    }

    @Test func reportFormWithoutPhotosIsExact() {
        let draft = ReportIssueDraft(category: .doorsLocks, description: "Front door lock sticking")

        let body = String(data: draft.form(photos: [], boundary: "B").body, encoding: .utf8)

        #expect(body == "--B\r\nContent-Disposition: form-data; name=\"category\"\r\n\r\ndoors_locks\r\n"
            + "--B\r\nContent-Disposition: form-data; name=\"description\"\r\n\r\nFront door lock sticking\r\n"
            + "--B\r\nContent-Disposition: form-data; name=\"isUrgent\"\r\n\r\nfalse\r\n"
            + "--B--\r\n")
    }

    @Test func detailMarksSeenAndDecodesTheThread() async throws {
        let transport = ScriptedTransport { _ in (200, json(issueDetailJSON())) }

        let detail = try await client(transport).issue(id: "i1")

        #expect(transport.requests.first?.url?.path == "/api/tenant/issues/i1")
        #expect(detail.issue.summary == "Kitchen tap dripping")
        #expect(detail.messages.map(\.id) == ["m1", "m2", "m3"])
    }

    @Test func replySendsTheBodyBeforeThePhotos() async throws {
        let transport = ScriptedTransport { _ in
            (201, json(issueMessageJSON("m4", author: "tenant", body: "Still leaking", photoDocumentIds: ["d4"])))
        }
        let client = client(transport)
        let photo = UploadFile(data: Data("JPEG".utf8), fileName: "Photo.jpg", mimeType: "image/jpeg")

        let message = try await client.replyToIssue(id: "i1", draft: IssueReplyDraft(body: " Still leaking "), photos: [photo], boundary: "B")

        #expect(message.id == "m4")
        #expect(message.isFromTenant)
        #expect(message.photoDocumentIds == ["d4"])
        let request = try #require(transport.requests.first)
        #expect(request.url?.path == "/api/tenant/issues/i1/messages")
        #expect(partNames(request, boundary: "B") == ["\"body\"", "\"photo\"; filename=\"Photo.jpg\""])
        let body = String(data: request.httpBody ?? Data(), encoding: .utf8) ?? ""
        #expect(body.contains("name=\"body\"\r\n\r\nStill leaking\r\n"))
    }

    @Test func replyFormSkipsAnEmptyBody() {
        let photo = UploadFile(data: Data("x".utf8), fileName: "p.png", mimeType: "image/png")

        let body = String(data: IssueReplyDraft(body: "   ").form(photos: [photo], boundary: "B").body, encoding: .utf8)

        #expect(body == "--B\r\nContent-Disposition: form-data; name=\"photo\"; filename=\"p.png\"\r\nContent-Type: image/png\r\n\r\nx\r\n"
            + "--B--\r\n")
        #expect(IssueReplyDraft(body: nil).trimmedBody == nil)
        #expect(IssueReplyDraft(body: " ok ").trimmedBody == "ok")
    }

    @Test func replyOnASettledIssueIsAConflict() async {
        let transport = ScriptedTransport { _ in (409, json(["error": "The issue is resolved; replies are closed"])) }
        let client = client(transport)

        await #expect(throws: APIError.http(status: 409, message: "The issue is resolved; replies are closed", code: nil, field: nil)) {
            try await client.replyToIssue(id: "i3", draft: IssueReplyDraft(body: "Hello"), photos: [])
        }
    }

    @Test func photoTooLargeAndWrongTypeKeepTheirStatuses() async {
        let transport = ScriptedTransport { request in
            request.url?.path.hasSuffix("/issues") == true
                ? (413, json(["error": "Photo too large", "field": "photo"]))
                : (415, json(["error": "Unsupported type", "field": "photo"]))
        }
        let client = client(transport)
        let photo = UploadFile(data: Data("x".utf8), fileName: "p.gif", mimeType: "image/gif")

        await #expect(throws: APIError.http(status: 413, message: "Photo too large", code: nil, field: "photo")) {
            try await client.reportIssue(leaseId: "l1", draft: ReportIssueDraft(category: .other, description: "x"), photos: [photo])
        }
        await #expect(throws: APIError.http(status: 415, message: "Unsupported type", code: nil, field: "photo")) {
            try await client.replyToIssue(id: "i1", draft: IssueReplyDraft(), photos: [photo])
        }
    }

    @Test func photoComesBackWithItsType() async throws {
        let transport = ScriptedTransport(responseHeaders: ["Content-Type": "image/jpeg"]) { _ in (200, Data("JFIF".utf8)) }

        let photo = try await client(transport).issuePhoto(issueId: "i1", documentId: "d1")

        #expect(transport.requests.first?.url?.path == "/api/tenant/issues/i1/photos/d1")
        #expect(transport.requests.first?.value(forHTTPHeaderField: "Authorization") == "Bearer access-a")
        #expect(photo.data == Data("JFIF".utf8))
        #expect(photo.mimeType == "image/jpeg")
        #expect(photo.isImage)
        #expect(!photo.isPDF)
        #expect(photo.fileName == nil)
    }
}
