// Mirrors server/types/tenantPortal.types.ts — the deliberately narrow view a tenant gets
// of their own lease. A field is added here only when the server adds it there.

import Foundation
import TenantCore

public struct TenantLeaseProperty: Codable, Sendable, Hashable {
    public let id: String
    public let street: String?
    public let unitNumber: String?
    public let floor: FloorLevel?
    public let postalCode: String?
    public let cityName: String?
}

public struct UpcomingRent: Codable, Sendable, Hashable {
    public let monthlyRent: Double
    public let effectiveFrom: Date
}

public struct TenantLease: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let property: TenantLeaseProperty
    public let status: LeaseStatus
    public let startDate: Date
    public let endDate: Date?
    /// The end date has passed while the lease is still open.
    public let isPastEnd: Bool
    /// The rent that applies today.
    public let monthlyRent: Double
    public let upcomingRent: UpcomingRent?
    public let currencyCode: String?
    public let depositAmount: Double?
    public let paymentDayOfMonth: Int?
    public let paymentMethod: PaymentMethod?
    public let noticePeriodMonths: Int?
    /// Last day the tenant can give notice; null without an end date + notice period.
    public let noticeDeadline: Date?
}

struct TenantLeasesResponse: Decodable, Sendable {
    let data: [TenantLease]
}

extension Array where Element == TenantLease {
    /// The lease the Home and Payments screens show by default: the active one, else the
    /// next one, else the newest (the web `currentLease`).
    public var currentLease: TenantLease? {
        first { $0.status == .active } ?? first { $0.status == .upcoming } ?? first
    }
}
