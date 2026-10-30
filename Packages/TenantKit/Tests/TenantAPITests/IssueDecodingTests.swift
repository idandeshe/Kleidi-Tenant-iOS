import Foundation
import Testing
import TenantCore
@testable import TenantAPI

@Suite struct IssueDecodingTests {
    let utc = TimeZone(identifier: "UTC")!

    @Test func decodesTheList() throws {
        let response = try TenantJSON.decoder().decode(TenantIssuesResponse.self, from: json(issuesListJSON()))
        let issues = response.data
        #expect(issues.count == 4)

        let inProgress = issues[0]
        #expect(inProgress.category == .plumbing)
        #expect(inProgress.status == .inProgress)
        #expect(inProgress.status.isOpen)
        #expect(inProgress.summary == "Kitchen tap dripping")
        #expect(inProgress.photoDocumentIds == ["d1", "d2"])
        #expect(inProgress.tenantUnread)
        #expect(inProgress.canReply)
        #expect(inProgress.closeReason == nil)
        #expect(inProgress.resolvedAt == nil)
        #expect(TenantFormatter.date(inProgress.createdAt, timeZone: utc) == "27/10/2026")
        #expect(TenantFormatter.dateTime(inProgress.lastActivityAt, timeZone: utc) == "28/10/2026 10:31")

        let urgent = issues[1]
        #expect(urgent.category == .electrical)
        #expect(urgent.status == .new)
        #expect(urgent.isUrgent)
        #expect(urgent.photoDocumentIds.isEmpty)

        let resolved = issues[2]
        #expect(resolved.category == .doorsLocks)
        #expect(resolved.status == .resolved)
        #expect(!resolved.status.isOpen)
        #expect(!resolved.canReply)
        #expect(TenantFormatter.date(resolved.resolvedAt, timeZone: utc) == "12/09/2026")

        let closed = issues[3]
        #expect(closed.status == .closed)
        #expect(closed.closeReason == "Not covered by the lease")
        #expect(TenantFormatter.date(closed.closedAt, timeZone: utc) == "01/08/2026")
    }

    @Test func decodesTheDetailAsIssuePlusMessages() throws {
        let detail = try TenantJSON.decoder().decode(TenantIssueDetail.self, from: json(issueDetailJSON()))
        #expect(detail.id == "i1")
        #expect(detail.issue.description.hasPrefix("The kitchen tap"))
        #expect(detail.messages.count == 3)

        let staff = detail.messages[0]
        #expect(staff.kind == .text)
        #expect(staff.author == .staff)
        #expect(!staff.isFromTenant)
        #expect(!staff.isStatusEvent)
        #expect(staff.body?.hasPrefix("A plumber") == true)
        #expect(staff.status == nil)
        #expect(TenantFormatter.dateTime(staff.createdAt, timeZone: utc) == "28/10/2026 10:15")

        let event = detail.messages[1]
        #expect(event.isStatusEvent)
        #expect(event.status == .inProgress)
        #expect(event.body == nil)

        let tenant = detail.messages[2]
        #expect(tenant.isFromTenant)
        #expect(tenant.photoDocumentIds == ["d3"])
    }

    @Test func detailWithoutMessagesDecodesToAnEmptyThread() throws {
        let detail = try TenantJSON.decoder().decode(TenantIssueDetail.self, from: json(issueJSON("i5", status: "new")))
        #expect(detail.messages.isEmpty)
        #expect(detail.issue.status == .new)
    }

    @Test func unknownCategoryStatusAndKindKeepTheirRawValues() throws {
        var raw = issueJSON("i6", category: "elevator", status: "waiting_for_parts")
        raw["messages"] = [issueMessageJSON("m9", kind: "reminder", author: "robot", body: "Beep")]
        let detail = try TenantJSON.decoder().decode(TenantIssueDetail.self, from: json(raw))

        #expect(detail.issue.category.rawValue == "elevator")
        #expect(!detail.issue.category.isKnown)
        #expect(detail.issue.category.symbolName == "questionmark.circle")
        #expect(detail.issue.status.rawValue == "waiting_for_parts")
        #expect(!detail.issue.status.isOpen)
        #expect(detail.messages[0].kind.rawValue == "reminder")
        #expect(detail.messages[0].author.rawValue == "robot")
        #expect(!detail.messages[0].isFromTenant)
    }
}
