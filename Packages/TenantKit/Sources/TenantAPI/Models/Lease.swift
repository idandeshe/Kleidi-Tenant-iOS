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

/// One rent of the lease, from the first day of the Rental Month that first charges it.
public struct RentTimelineEntry: Codable, Sendable, Hashable {
    public let effectiveFrom: Date
    public let monthlyRent: Double
}

public struct TenantLease: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let property: TenantLeaseProperty
    public let status: LeaseStatus
    public let startDate: Date
    public let endDate: Date?
    /// The end date has passed while the lease is still open.
    public let isPastEnd: Bool
    /// The rent of today's row.
    public let monthlyRent: Double
    public let upcomingRent: UpcomingRent?
    /// Every rent of the lease, oldest first; nil on older servers.
    public let rentTimeline: [RentTimelineEntry]?
    public let currencyCode: String?
    public let depositAmount: Double?
    public let paymentDayOfMonth: Int?
    public let paymentMethod: PaymentMethod?
    public let noticePeriodMonths: Int?
    /// Last day the tenant can give notice; null without an end date + notice period.
    public let noticeDeadline: Date?

    /// The timeline entry today's row falls in: the last one whose calendar month (UTC) has
    /// arrived, matching the server's rule that a row carries its month's rent.
    public func currentRentIndex(today: Date = Date()) -> Int? {
        guard let rentTimeline else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        func month(_ date: Date) -> Int {
            let parts = calendar.dateComponents([.year, .month], from: date)
            return (parts.year ?? 0) * 12 + (parts.month ?? 0)
        }
        return rentTimeline.lastIndex { month($0.effectiveFrom) <= month(today) }
    }
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
