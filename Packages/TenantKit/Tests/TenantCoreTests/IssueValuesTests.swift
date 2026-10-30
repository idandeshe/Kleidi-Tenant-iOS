import Foundation
import Testing
@testable import TenantCore

@Suite struct IssueValuesTests {
    private final class Marker {}

    @Test func categoriesMatchTheServerEnumInGridOrder() {
        #expect(TenantIssueCategory.all.map(\.rawValue) == ["plumbing", "electrical", "heating_ac", "doors_locks", "building", "other"])
        #expect(TenantIssueCategory.all.allSatisfy(\.isKnown))
        #expect(!TenantIssueCategory(rawValue: "elevator").isKnown)
    }

    @Test func categoryLabelsAndSymbols() {
        let l10n = L10n(language: .en, bundle: Bundle(for: Marker.self))
        #expect(TenantIssueCategory.heatingAC.labelKey == "issues.category.heating_ac")
        // No .lproj bundles in a package test: a known key shows its raw value, like an unknown one.
        #expect(TenantIssueCategory.heatingAC.label(l10n) == "heating_ac")
        #expect(TenantIssueCategory(rawValue: "elevator").label(l10n) == "elevator")
        #expect(TenantIssueCategory.plumbing.symbolName == "drop.fill")
        #expect(TenantIssueCategory.electrical.symbolName == "bolt.fill")
        #expect(TenantIssueCategory.heatingAC.symbolName == "thermometer.medium")
        #expect(TenantIssueCategory.doorsLocks.symbolName == "lock.fill")
        #expect(TenantIssueCategory.building.symbolName == "building.2.fill")
        #expect(TenantIssueCategory.other.symbolName == "questionmark.circle")
        #expect(TenantIssueCategory(rawValue: "elevator").symbolName == "questionmark.circle")
    }

    @Test func openStatusesAreNewAndInProgress() {
        #expect(TenantIssueStatus.new.isOpen)
        #expect(TenantIssueStatus.inProgress.isOpen)
        #expect(!TenantIssueStatus.resolved.isOpen)
        #expect(!TenantIssueStatus.closed.isOpen)
        #expect(!TenantIssueStatus(rawValue: "waiting_for_parts").isOpen)
    }

    @Test func statusLabelKeysAndFallback() {
        let l10n = L10n(language: .el, bundle: Bundle(for: Marker.self))
        #expect(TenantIssueStatus.inProgress.labelKey == "issues.status.in_progress")
        #expect(TenantIssueStatus(rawValue: "waiting_for_parts").label(l10n) == "waiting_for_parts")
        #expect(TenantIssueMessageKind.status.rawValue == "status")
        #expect(TenantIssueActor.staff.rawValue == "staff")
    }

    @Test func photoRulesMatchTheServer() {
        #expect(IssuePhotoRules.maxBytes == 10 * 1024 * 1024)
        #expect(IssuePhotoRules.maxReportPhotos == 5)
        #expect(IssuePhotoRules.maxReplyPhotos == 3)
        #expect(IssuePhotoRules.descriptionMaxLength == 2000)
        #expect(IssuePhotoRules.messageMaxLength == 2000)
        #expect(IssuePhotoRules.accepts(mimeType: "image/jpeg"))
        #expect(IssuePhotoRules.accepts(mimeType: "Image/WEBP"))
        #expect(!IssuePhotoRules.accepts(mimeType: "application/pdf"))
        #expect(!IssuePhotoRules.accepts(mimeType: "image/heic"))
        #expect(IssuePhotoRules.mimeType(forExtension: "JPG") == "image/jpeg")
        #expect(IssuePhotoRules.mimeType(forExtension: "png") == "image/png")
        #expect(IssuePhotoRules.mimeType(forExtension: "pdf") == nil)
    }

    @Test func dateTimeIsDayMonthYearHourMinute() {
        let utc = TimeZone(identifier: "UTC")!
        #expect(TenantFormatter.dateTime(Date(timeIntervalSince1970: 1_793_361_720), timeZone: utc) == "30/10/2026 12:02")
        #expect(TenantFormatter.dateTime(Date(timeIntervalSince1970: 1_767_225_600), timeZone: utc) == "01/01/2026 00:00")
        // 2026-10-03T23:30Z is 02:30 on the 4th in Athens (EEST).
        #expect(TenantFormatter.dateTime(Date(timeIntervalSince1970: 1_791_070_200), timeZone: TimeZone(identifier: "Europe/Athens")!) == "04/10/2026 02:30")
        #expect(TenantFormatter.dateTime(nil) == "")
    }
}
