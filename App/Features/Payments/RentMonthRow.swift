import SwiftUI
import TenantAPI
import TenantCore

/// One rent month as the tenant sees it (the web `RentMonthRow`): the month and its expected
/// rent, the status pill ("Wire confirmed by property owner" for a month paid through a
/// declaration), the paid / declared / due date, the declaration folded in (when it was
/// declared and "View proof"), and the red note with "Declare again" when the last
/// declaration on an unpaid month was rejected.
struct RentMonthRow: View {
    @Environment(\.l10n) private var l10n
    let month: TenantRentMonth
    let currencyCode: String?
    /// "Declare again" opens the Declare screen of this lease.
    let leaseId: String
    /// "View proof" of `month.declaration`.
    let onViewProof: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(TenantFormatter.period(month.period, language: l10n.language))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(TenantTheme.ink)
                Spacer()
                Text(month.expectedAmount.map { TenantFormatter.money($0, currencyCode: currencyCode, language: l10n.language) } ?? "—")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(TenantTheme.ink)
            }
            HStack(alignment: .center, spacing: 12) {
                RentMonthStatusPill(month: month)
                Spacer(minLength: 0)
                Text(dateLine)
                    .font(.caption)
                    .foregroundStyle(TenantTheme.muted)
                    .multilineTextAlignment(.trailing)
            }
            if month.showsProof, let declaration = month.declaration {
                HStack(spacing: 4) {
                    // A declared month already shows its date on the right.
                    if month.status != .declared {
                        Text(l10n.format("rent.declaredOn", TenantFormatter.date(declaration.declaredAt)))
                        Text("·")
                    }
                    Button(l10n["rent.viewProof"], action: onViewProof)
                        .buttonStyle(.plain)
                        .foregroundStyle(TenantTheme.accent)
                }
                .font(.caption)
                .foregroundStyle(TenantTheme.muted)
            }
            if month.isRejected {
                AlertBox(
                    text: l10n["rent.rejected"],
                    secondary: month.declaration?.rejectionNote.map { l10n.format("rent.rejectedNote", $0) })
                if month.canDeclare {
                    NavigationLink(value: Route.declareWire(leaseId: leaseId)) {
                        Text(l10n["rent.declareAgain"])
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(TenantTheme.accent)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.vertical, 12)
    }

    /// "Paid 02/07/2026" / "Declared 03/09/2026" / "Due 05/10/2026".
    private var dateLine: String {
        if month.status == .paid, let paidAt = month.paidAt {
            return l10n.format("rent.paidOn", TenantFormatter.date(paidAt))
        }
        if month.status == .declared, let declaration = month.declaration {
            return l10n.format("rent.declaredOn", TenantFormatter.date(declaration.declaredAt))
        }
        return l10n.format("home.rent.due", TenantFormatter.date(month.dueDate))
    }
}

/// The month's status pill — also the pill on the Home rent card.
struct RentMonthStatusPill: View {
    @Environment(\.l10n) private var l10n
    let month: TenantRentMonth

    var body: some View {
        StatusPill(text: month.statusLabel(l10n), tone: RentTones.tone(for: month.status))
    }
}

/// Pill colours per status (the web `STATUS_STYLE`); unknown values are neutral.
enum RentTones {
    static func tone(for status: RentMonthStatus) -> StatusTone {
        switch status {
        case .paid: return .ok
        case .declared: return .accent
        case .due: return .warn
        case .overdue: return .error
        default: return .neutral
        }
    }
}
