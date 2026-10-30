// Mirrors server/types/leases.types.ts (the subset the tenant sees, server/types/tenantPortal.types.ts).
// Values decode as open strings so a newer server never breaks an older app; unknown values
// fall back to the raw value as their label.

import Foundation

public struct LeaseStatus: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let upcoming = LeaseStatus(rawValue: "upcoming")
    public static let active = LeaseStatus(rawValue: "active")
    public static let ended = LeaseStatus(rawValue: "ended")
    public static let terminated = LeaseStatus(rawValue: "terminated")

    /// Ended or terminated: the lease is history.
    public var isTerminal: Bool { self == .ended || self == .terminated }

    /// Localized label, e.g. "Active" / "Ενεργή".
    public func label(_ l10n: L10n) -> String {
        let key = "lease.status.\(rawValue)"
        let text = l10n[key]
        return text == key ? rawValue : text
    }
}

public struct PaymentMethod: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let bankTransfer = PaymentMethod(rawValue: "bank_transfer")
    public static let standingOrder = PaymentMethod(rawValue: "standing_order")
    public static let cheques = PaymentMethod(rawValue: "cheques")
    public static let cash = PaymentMethod(rawValue: "cash")
    public static let other = PaymentMethod(rawValue: "other")

    public func label(_ l10n: L10n) -> String {
        let key = "lease.paymentMethod.\(rawValue)"
        let text = l10n[key]
        return text == key ? rawValue : text
    }
}

/// `basement`, `ground`, `floor_3`… (server/types/properties.types.ts `FloorLevel`).
public struct FloorLevel: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    /// "3rd floor" / "3ος όροφος"; named levels come from the catalog.
    public func label(_ l10n: L10n) -> String {
        if rawValue.hasPrefix("floor_"), let n = Int(rawValue.dropFirst("floor_".count)) {
            return l10n.format("floor.numbered", TenantFormatter.ordinal(n, language: l10n.language))
        }
        let key = "floor.\(rawValue)"
        let text = l10n[key]
        return text == key ? rawValue : text
    }
}
