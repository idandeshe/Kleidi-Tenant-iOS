import Foundation
import Testing
import TenantCore
@testable import TenantAPI

@Suite struct DecodingTests {
    @Test func decodesTenantLease() throws {
        let lease = try TenantJSON.decoder().decode(TenantLease.self, from: json(leaseJSON()))
        #expect(lease.status == .active)
        #expect(lease.property.cityName == "Athens")
        #expect(lease.property.floor == FloorLevel(rawValue: "floor_2"))
        #expect(lease.monthlyRent == 800)
        #expect(lease.upcomingRent?.monthlyRent == 850)
        #expect(lease.paymentDayOfMonth == 5)
        #expect(lease.paymentMethod == .bankTransfer)
        #expect(TenantFormatter.date(lease.startDate, timeZone: TimeZone(identifier: "UTC")!) == "01/01/2026")
        #expect(lease.noticeDeadline != nil)
    }

    @Test func nullableFieldsDecodeAsNil() throws {
        var sparse = leaseJSON()
        for key in ["endDate", "upcomingRent", "currencyCode", "depositAmount", "paymentDayOfMonth", "paymentMethod", "noticePeriodMonths", "noticeDeadline"] {
            sparse[key] = NSNull()
        }
        sparse["status"] = "some_future_status"
        let lease = try TenantJSON.decoder().decode(TenantLease.self, from: json(sparse))
        #expect(lease.endDate == nil)
        #expect(lease.upcomingRent == nil)
        #expect(lease.depositAmount == nil)
        #expect(lease.paymentMethod == nil)
        #expect(lease.status.rawValue == "some_future_status")
    }

    @Test func decodesConfigAndUpdateRule() throws {
        let data = json([
            "apiVersion": 1, "serverVersion": "1.40.0", "smsConfigured": true, "turnstileSiteKey": NSNull(),
            "ios": ["minSupportedBuild": 5, "appStoreUrl": "https://apps.apple.com/app/id1"],
            "android": ["minSupportedBuild": 0, "playStoreUrl": NSNull()],
        ])
        let config = try TenantJSON.decoder().decode(TenantConfig.self, from: data)
        #expect(config.smsConfigured)
        #expect(config.turnstileSiteKey == nil)
        #expect(config.requiresUpdate(build: 4))
        #expect(!config.requiresUpdate(build: 5))
        #expect(config.appStoreURL?.host() == "apps.apple.com")
    }

    @Test func decodesSessionResponse() throws {
        let data = json(["tenant": tenantJSON(), "expiresAt": "2026-10-26T12:15:00.000Z"])
        let session = try TenantJSON.decoder().decode(TenantSessionResponse.self, from: data)
        #expect(session.tenant.id == "t1")
        #expect(session.tenant.phone == "+306912345678")
    }
}

@Suite struct RentDecodingTests {
    let utc = TimeZone(identifier: "UTC")!

    @Test func decodesRentMonths() throws {
        let rent = try TenantJSON.decoder().decode(TenantRent.self, from: json(rentJSON()))
        #expect(rent.leaseId == "l1")
        #expect(rent.currencyCode == "EUR")
        #expect(rent.months.count == 4)
        #expect(rent.months.map(\.period) == ["2026-10", "2026-09", "2026-08", "2026-07"])
        #expect(rent.canDeclare)
        #expect(rent.declarableMonths.map(\.period) == ["2026-10", "2026-08"])

        let due = rent.months[0]
        #expect(due.status == .due)
        #expect(due.expectedAmount == 800)
        #expect(due.declaration == nil)
        #expect(TenantFormatter.date(due.dueDate, timeZone: utc) == "05/10/2026")
        #expect(!due.isRejected)
        #expect(!due.showsProof)

        let declared = rent.months[1]
        #expect(declared.status == .declared)
        #expect(declared.declaration?.status == .pending)
        #expect(declared.declaration?.rejectionNote == nil)
        #expect(TenantFormatter.date(declared.declaration?.declaredAt, timeZone: utc) == "04/09/2026")
        #expect(!declared.isRejected)
        #expect(declared.showsProof)

        let rejected = rent.months[2]
        #expect(rejected.status == .overdue)
        #expect(rejected.declaration?.status == .rejected)
        #expect(rejected.declaration?.rejectionNote == "Wrong IBAN")
        #expect(rejected.isRejected)
        #expect(rejected.showsProof)

        let paid = rent.months[3]
        #expect(paid.status == .paid)
        #expect(paid.confirmedByWire)
        #expect(TenantFormatter.date(paid.paidAt, timeZone: utc) == "02/07/2026")
        #expect(paid.declaration?.id == "w0")
        #expect(paid.showsProof)
    }

    @Test func unknownStatusesDecodeAsRawValues() throws {
        var month = rentMonthJSON("2026-11", status: "partially_paid", declaration: [
            "id": "w9", "status": "under_review", "declaredAmount": 400, "transferDate": "2026-11-01T00:00:00.000Z",
            "declaredAt": "2026-11-01T10:00:00.000Z", "rejectionNote": NSNull(), "confirmedAt": NSNull(),
        ])
        month["expectedAmount"] = NSNull()
        let decoded = try TenantJSON.decoder().decode(TenantRentMonth.self, from: json(month))
        #expect(decoded.status.rawValue == "partially_paid")
        #expect(decoded.declaration?.status.rawValue == "under_review")
        #expect(decoded.expectedAmount == nil)
    }

    @Test func decodesACreatedWireDeclaration() throws {
        let rejected = try TenantJSON.decoder().decode(TenantWireDeclaration.self, from: json(declarationJSON("w2", status: "rejected")))
        #expect(rejected.status == .rejected)
        #expect(rejected.periods == ["2026-09", "2026-10"])
        #expect(rejected.declaredAmount == 1600)
        #expect(rejected.reference == "Rent Sep-Oct")
        #expect(rejected.rejectionNote == "Amount does not match")
        #expect(TenantFormatter.date(rejected.createdAt, timeZone: utc) == "03/10/2026")
        let confirmed = try TenantJSON.decoder().decode(TenantWireDeclaration.self, from: json(declarationJSON("w1", status: "confirmed")))
        #expect(confirmed.status == .confirmed)
        #expect(confirmed.rejectionNote == nil)
    }

    @Test func currentLeasePrefersActiveThenUpcomingThenNewest() throws {
        func lease(_ id: String, _ status: String) throws -> TenantLease {
            var raw = leaseJSON()
            raw["id"] = id
            raw["status"] = status
            return try TenantJSON.decoder().decode(TenantLease.self, from: json(raw))
        }
        let ended = try lease("l0", "ended")
        let upcoming = try lease("l2", "upcoming")
        let active = try lease("l1", "active")
        #expect([ended, upcoming, active].currentLease?.id == "l1")
        #expect([ended, upcoming].currentLease?.id == "l2")
        #expect([ended].currentLease?.id == "l0")
        #expect([TenantLease]().currentLease == nil)
    }
}
