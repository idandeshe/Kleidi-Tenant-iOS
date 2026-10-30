import Foundation
import Testing
@testable import TenantCore

@Suite struct AppLanguageTests {
    @Test func deviceDefaultIsGreekUnlessTheDeviceSpeaksEnglish() {
        #expect(AppLanguage.deviceDefault(preferredLanguages: ["en-US", "el-GR"]) == .en)
        #expect(AppLanguage.deviceDefault(preferredLanguages: ["en"]) == .en)
        #expect(AppLanguage.deviceDefault(preferredLanguages: ["el-GR"]) == .el)
        #expect(AppLanguage.deviceDefault(preferredLanguages: ["de-DE", "en"]) == .el)
        #expect(AppLanguage.deviceDefault(preferredLanguages: []) == .el)
    }

    @Test func decodesServerValues() throws {
        #expect(try JSONDecoder().decode(AppLanguage.self, from: Data("\"el\"".utf8)) == .el)
        #expect(try JSONDecoder().decode(AppLanguage.self, from: Data("\"en\"".utf8)) == .en)
    }
}

@Suite struct L10nTests {
    @Test func missingKeyShowsTheKey() {
        // No .lproj bundles in a package test; the lookup falls back to the key itself.
        let l10n = L10n(language: .el, bundle: Bundle(for: Marker.self))
        #expect(l10n["home.title"] == "home.title")
        #expect(l10n.format("home.rentFor", 5) == "home.rentFor")
    }

    @Test func leaseValuesFallBackToRawValue() {
        let l10n = L10n(language: .en, bundle: Bundle(for: Marker.self))
        #expect(LeaseStatus(rawValue: "brand_new").label(l10n) == "brand_new")
        #expect(LeaseStatus.active.isTerminal == false)
        #expect(LeaseStatus.terminated.isTerminal)
        #expect(PaymentMethod.bankTransfer.rawValue == "bank_transfer")
    }

    private final class Marker {}
}

@Suite struct TenantFormatterTests {
    let utc = TimeZone(identifier: "UTC")!

    @Test func dateIsDayMonthYear() {
        let date = Date(timeIntervalSince1970: 1_767_225_600) // 2026-01-01T00:00:00Z
        #expect(TenantFormatter.date(date, timeZone: utc) == "01/01/2026")
        #expect(TenantFormatter.date(nil) == "")
    }

    @Test func monthYearInEachLanguage() {
        let date = Date(timeIntervalSince1970: 1_792_195_200) // 2026-10-17T00:00:00Z
        #expect(TenantFormatter.monthYear(date, language: .en, timeZone: utc) == "October 2026")
        #expect(TenantFormatter.monthYear(date, language: .el, timeZone: utc) == "Οκτωβρίου 2026")
    }

    @Test func moneyMatchesTheMockUp() {
        #expect(TenantFormatter.money(800, currencyCode: "EUR", language: .en) == "€ 800")
        #expect(TenantFormatter.money(800, currencyCode: "EUR", language: .el) == "€ 800")
        #expect(TenantFormatter.money(812.5, currencyCode: "EUR", language: .en) == "€ 812.50")
        #expect(TenantFormatter.money(812.5, currencyCode: "EUR", language: .el) == "€ 812,50")
        #expect(TenantFormatter.money(1200, currencyCode: "EUR", language: .en) == "€ 1,200")
        #expect(TenantFormatter.money(1200, currencyCode: "EUR", language: .el) == "€ 1.200")
        #expect(TenantFormatter.money(500, currencyCode: nil, language: .en) == "500")
        #expect(TenantFormatter.money(nil, currencyCode: "EUR", language: .en) == "")
    }

    @Test(arguments: [(1, "1st"), (2, "2nd"), (3, "3rd"), (4, "4th"), (11, "11th"), (12, "12th"), (13, "13th"), (21, "21st"), (22, "22nd"), (31, "31st")])
    func englishOrdinals(n: Int, expected: String) {
        #expect(TenantFormatter.ordinal(n, language: .en) == expected)
        #expect(TenantFormatter.ordinal(n, language: .el) == "\(n)")
    }
}

@Suite struct RentValuesTests {
    private final class Marker {}

    @Test func statusLabelsFallBackToRawValue() {
        let l10n = L10n(language: .en, bundle: Bundle(for: Marker.self))
        #expect(RentMonthStatus.paid.rawValue == "paid")
        #expect(RentMonthStatus(rawValue: "brand_new").label(l10n) == "brand_new")
        #expect(WireDeclarationStatus.rejected.rawValue == "rejected")
    }

    @Test func proofLinkShowsForDeclaredConfirmedAndRejectedMonths() {
        #expect(RentProofLink.isShown(status: .declared, confirmedByWire: false, declarationStatus: .pending))
        #expect(RentProofLink.isShown(status: .paid, confirmedByWire: true, declarationStatus: .confirmed))
        #expect(RentProofLink.isShown(status: .overdue, confirmedByWire: false, declarationStatus: .rejected))
        #expect(RentProofLink.isShown(status: .due, confirmedByWire: false, declarationStatus: .rejected))
        // Paid some other way, declared nothing, or a declaration that was neither confirmed nor rejected.
        #expect(!RentProofLink.isShown(status: .paid, confirmedByWire: false, declarationStatus: .rejected))
        #expect(!RentProofLink.isShown(status: .due, confirmedByWire: false, declarationStatus: nil))
        #expect(!RentProofLink.isShown(status: .overdue, confirmedByWire: false, declarationStatus: .pending))
        #expect(!RentProofLink.isShown(status: .upcoming, confirmedByWire: false, declarationStatus: nil))
    }

    @Test func periodLabelsInEachLanguage() {
        #expect(TenantFormatter.period("2026-10", language: .en) == "October 2026")
        #expect(TenantFormatter.period("2026-10", language: .el) == "Οκτώβριος 2026")
        #expect(TenantFormatter.period("2026-01", language: .en) == "January 2026")
        #expect(TenantFormatter.period("not-a-period", language: .en) == "not-a-period")
        #expect(TenantFormatter.period("2026-13", language: .en) == "2026-13")
    }

    @Test func isoDateIsYearMonthDay() {
        let utc = TimeZone(identifier: "UTC")!
        #expect(TenantFormatter.isoDate(Date(timeIntervalSince1970: 1_767_225_600), timeZone: utc) == "2026-01-01")
        #expect(TenantFormatter.isoDate(Date(timeIntervalSince1970: 1_790_985_600), timeZone: utc) == "2026-10-03")
        // 2026-10-03T23:30Z is already the 4th in Athens.
        #expect(TenantFormatter.isoDate(Date(timeIntervalSince1970: 1_791_070_200), timeZone: TimeZone(identifier: "Europe/Athens")!) == "2026-10-04")
    }

    @Test func fileSizes() {
        #expect(TenantFormatter.fileSize(512, language: .en) == "1 KB")
        #expect(TenantFormatter.fileSize(812_000, language: .en) == "812 KB")
        #expect(TenantFormatter.fileSize(1_400_000, language: .en) == "1.4 MB")
        #expect(TenantFormatter.fileSize(1_400_000, language: .el) == "1,4 MB")
    }
}
