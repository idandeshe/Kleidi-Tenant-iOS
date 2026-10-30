// Mirrors the rent section of server/types/tenantPortal.types.ts (`TenantRentResponse`,
// `TenantRentMonth`) and `TenantWireDeclarationResponse` in server/types/wireDeclarations.types.ts:
// the tenant's months, each with its latest "I paid by bank transfer" declaration. No staff analysis here.

import Foundation
import TenantCore

/// The latest declaration covering a month (any status, so a rejection stays visible).
public struct TenantRentMonthDeclaration: Decodable, Sendable, Hashable, Identifiable {
    public let id: String
    public let status: WireDeclarationStatus
    public let declaredAmount: Double
    public let transferDate: Date
    /// When the tenant submitted it ("Declared 03/09/2026" on the month row).
    public let declaredAt: Date
    public let rejectionNote: String?
    public let confirmedAt: Date?
}

public struct TenantRentMonth: Decodable, Sendable, Hashable, Identifiable {
    /// `YYYY-MM`
    public let period: String
    /// UTC midnight of the day the rent is owed.
    public let dueDate: Date
    public let expectedAmount: Double?
    public let status: RentMonthStatus
    public let paidAt: Date?
    /// Paid through a confirmed declaration ("Wire confirmed by property owner").
    public let confirmedByWire: Bool
    public let declaration: TenantRentMonthDeclaration?
    /// The tenant may declare a bank transfer for this month.
    public let canDeclare: Bool

    public var id: String { period }

    /// The web `rentMonthStatusLabel`: a month paid through a wire says so, otherwise the status.
    public func statusLabel(_ l10n: L10n) -> String {
        status == .paid && confirmedByWire ? l10n["rent.confirmedByWire"] : status.label(l10n)
    }

    /// The last declaration on an unpaid, undeclared month was rejected — show the red note.
    public var isRejected: Bool {
        status != .paid && status != .declared && declaration?.status == .rejected
    }

    /// The month row shows its declaration's "View proof" link (the web `showDeclaration`).
    public var showsProof: Bool {
        RentProofLink.isShown(status: status, confirmedByWire: confirmedByWire, declarationStatus: declaration?.status)
    }
}

/// `GET /tenant/leases/:id/rent`.
public struct TenantRent: Decodable, Sendable, Equatable {
    public let leaseId: String
    public let currencyCode: String?
    /// The rent that applies today.
    public let monthlyRent: Double
    public let paymentDayOfMonth: Int?
    /// Newest month first.
    public let months: [TenantRentMonth]

    /// The months a bank transfer can still be declared for, newest first.
    public var declarableMonths: [TenantRentMonth] { months.filter(\.canDeclare) }
    public var canDeclare: Bool { months.contains { $0.canDeclare } }
}

/// The declaration a `POST /tenant/leases/:id/wire-declarations` created (its 201 body).
public struct TenantWireDeclaration: Decodable, Sendable, Hashable, Identifiable {
    public let id: String
    public let leaseId: String
    /// `YYYY-MM`, the months this transfer covers.
    public let periods: [String]
    public let status: WireDeclarationStatus
    public let declaredAmount: Double
    public let currencyCode: String?
    public let transferDate: Date
    public let reference: String?
    public let rejectionNote: String?
    public let confirmedAt: Date?
    public let createdAt: Date
}

/// Server-side limits of a declaration (`WIRE_DECLARATIONS_VALIDATION`, `WIRE_PROOF_MIME_TYPES`).
public enum WireProofRules {
    public static let maxBytes = 15 * 1024 * 1024
    public static let mimeTypes: Set<String> = ["application/pdf", "image/jpeg", "image/png", "image/webp"]
    public static let referenceMaxLength = 140
    public static let maxPeriods = 12

    public static func accepts(mimeType: String) -> Bool { mimeTypes.contains(mimeType.lowercased()) }

    /// MIME type for a file picked from Files; nil when the server would refuse it.
    public static func mimeType(forExtension ext: String) -> String? {
        switch ext.lowercased() {
        case "pdf": return "application/pdf"
        case "jpg", "jpeg": return "image/jpeg"
        case "png": return "image/png"
        case "webp": return "image/webp"
        default: return nil
        }
    }
}

/// The proof file as it goes on the wire — already JPEG when it started as a HEIC / camera photo.
public typealias WireProofUpload = UploadFile

/// What the tenant fills in on the Declare screen (`DeclareWireDto` + the proof).
public struct WireDeclarationDraft: Sendable, Equatable {
    /// `YYYY-MM`, in the order they are sent.
    public var periods: [String]
    public var declaredAmount: Decimal
    /// The calendar day of the transfer, sent as `YYYY-MM-DD` in the viewer's time zone.
    public var transferDate: Date
    public var reference: String?
    public var proof: WireProofUpload

    public init(periods: [String], declaredAmount: Decimal, transferDate: Date, reference: String? = nil, proof: WireProofUpload) {
        self.periods = periods
        self.declaredAmount = declaredAmount
        self.transferDate = transferDate
        self.reference = reference
        self.proof = proof
    }

    /// The multipart body: text fields first (the server reads them before the file), then `proof`.
    public func form(boundary: String = "kleidi-\(UUID().uuidString)", timeZone: TimeZone = .current) -> MultipartForm {
        var form = MultipartForm(boundary: boundary)
        let periodsJSON = "[" + periods.map { "\"\($0)\"" }.joined(separator: ",") + "]"
        form.addField("periods", periodsJSON)
        form.addField("declaredAmount", "\(declaredAmount)")
        form.addField("transferDate", TenantFormatter.isoDate(transferDate, timeZone: timeZone))
        if let reference = reference?.trimmingCharacters(in: .whitespacesAndNewlines), !reference.isEmpty {
            form.addField("reference", reference)
        }
        form.addFile("proof", fileName: proof.fileName, mimeType: proof.mimeType, contents: proof.data)
        return form
    }
}

/// `GET /tenant/wire-declarations/:id/proof` — the bytes with the type they were uploaded as.
public typealias WireProofFile = DownloadedFile
