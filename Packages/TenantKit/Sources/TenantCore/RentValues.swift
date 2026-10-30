// Mirrors `TenantRentMonthStatus` (server/types/tenantPortal.types.ts) and
// `WireDeclarationStatus` (server/types/wireDeclarations.types.ts). Like LeaseValues, the
// values decode as open strings so a status added on the server never crashes an older app;
// an unknown value shows its raw value as the label.

import Foundation

/// How a rent month stands for the tenant: paid, declared (a bank transfer waits for staff),
/// due, overdue, or not due yet.
public struct RentMonthStatus: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let paid = RentMonthStatus(rawValue: "paid")
    public static let declared = RentMonthStatus(rawValue: "declared")
    public static let due = RentMonthStatus(rawValue: "due")
    public static let overdue = RentMonthStatus(rawValue: "overdue")
    public static let upcoming = RentMonthStatus(rawValue: "upcoming")

    /// "Paid" / "Πληρωμένο"… (the web `t.rent.status[status]`).
    public func label(_ l10n: L10n) -> String {
        let key = "rent.status.\(rawValue)"
        let text = l10n[key]
        return text == key ? rawValue : text
    }
}

/// A bank-transfer declaration's state in the staff review queue.
public struct WireDeclarationStatus: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let pending = WireDeclarationStatus(rawValue: "pending")
    public static let confirmed = WireDeclarationStatus(rawValue: "confirmed")
    public static let rejected = WireDeclarationStatus(rawValue: "rejected")
}

/// Whether a rent month's row shows the "View proof" link of its declaration (the web
/// `RentMonthRow`'s `showDeclaration`): a declared month (the wire waits for staff), a month
/// paid through its confirmed wire, or an unpaid month whose last declaration was rejected.
/// Never without a declaration.
public enum RentProofLink {
    public static func isShown(status: RentMonthStatus, confirmedByWire: Bool,
                               declarationStatus: WireDeclarationStatus?) -> Bool {
        guard let declarationStatus else { return false }
        if status == .declared { return true }
        if status == .paid { return confirmedByWire }
        return declarationStatus == .rejected
    }
}
