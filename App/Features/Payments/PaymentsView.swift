import SwiftUI
import TenantAPI
import TenantCore

/// Payments: "Pay online" stays a Coming-soon row; the rent months are real, each with its
/// state and its latest bank-transfer declaration (when it was declared, "View proof", the
/// rejection note). Shows the same lease as Home's default (the active one, else the next,
/// else the newest).
struct PaymentsView: View {
    @Environment(AppModel.self) private var app
    @Environment(AppNavigation.self) private var navigation
    @Environment(\.l10n) private var l10n

    @State private var leases: [TenantLease]?
    @State private var rent: TenantRent?
    @State private var error: String?
    @State private var proofOf: TenantRentMonthDeclaration?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let leases {
                    if let lease = leases.currentLease {
                        if let rent, rent.leaseId == lease.id {
                            DeclareCard(leaseId: lease.id, canDeclare: rent.canDeclare)
                            RentMonthsCard(rent: rent) { proofOf = $0 }
                        } else if let error {
                            NoticeLabel(text: error)
                            Button(l10n["common.retry"]) { Task { await load() } }
                                .buttonStyle(.bordered)
                        } else {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .padding(.top, 48)
                        }
                    } else {
                        ContentUnavailableView(
                            l10n["home.noLease.title"], systemImage: "house",
                            description: Text(l10n["home.noLease.body"]))
                    }
                } else if let error {
                    NoticeLabel(text: error)
                    Button(l10n["common.retry"]) { Task { await load() } }
                        .buttonStyle(.bordered)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 48)
                }
            }
            .padding(20)
        }
        .background(TenantTheme.ground)
        .navigationTitle(l10n["tab.payments"])
        .refreshable { await load() }
        // Runs on appear and again after a declaration was sent from the Declare screen.
        .task(id: navigation.rentRevision) { await load() }
        .sheet(item: $proofOf) { ProofViewer(declarationId: $0.id) }
    }

    private func load() async {
        error = nil
        do {
            let loaded = try await app.client.leases()
            leases = loaded
            guard let lease = loaded.currentLease else {
                rent = nil
                return
            }
            rent = try await app.client.rent(leaseId: lease.id)
        } catch {
            // Keep what is already on screen; report only when there is nothing to show.
            if rent == nil || leases == nil { self.error = l10n.message(for: error) }
        }
    }
}

// MARK: - Cards

/// "I paid by bank transfer" (or why there is nothing to declare) and the Coming-soon "Pay online" row.
private struct DeclareCard: View {
    @Environment(\.l10n) private var l10n
    let leaseId: String
    let canDeclare: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if canDeclare {
                NavigationLink(value: Route.declareWire(leaseId: leaseId)) {
                    Label(l10n["rent.declare"], systemImage: "building.columns")
                }
                .buttonStyle(PrimaryButtonStyle())
            } else {
                Text(l10n["rent.nothingToDeclare"])
                    .font(.footnote)
                    .foregroundStyle(TenantTheme.muted)
            }
            PayOnlineCard()
        }
        .card()
    }
}

private struct RentMonthsCard: View {
    @Environment(\.l10n) private var l10n
    let rent: TenantRent
    let onViewProof: (TenantRentMonthDeclaration) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(l10n["rent.title"])
                .font(.headline)
                .foregroundStyle(TenantTheme.ink)
                .padding(.bottom, 4)
            ForEach(Array(rent.months.enumerated()), id: \.element.id) { index, month in
                if index > 0 { Divider() }
                RentMonthRow(month: month, currencyCode: rent.currencyCode, leaseId: rent.leaseId) {
                    if let declaration = month.declaration { onViewProof(declaration) }
                }
            }
        }
        .card()
    }
}
