import SwiftUI
import TenantAPI
import TenantCore

/// "My lease": this month's rent, the (coming) payment actions, the lease terms and the
/// issue entry point. A tenant on several leases picks which one from a menu.
struct HomeView: View {
    @Environment(AppModel.self) private var app
    @Environment(AppNavigation.self) private var navigation
    @Environment(\.l10n) private var l10n

    @State private var leases: [TenantLease]?
    @State private var error: String?
    @State private var selectedId: String?
    /// The months of the lease on screen (`rent.leaseId`); nil while loading or when the call failed.
    @State private var rent: TenantRent?

    /// Reload the months when the lease on screen changes or a declaration was sent.
    private struct RentKey: Equatable {
        let leaseId: String?
        let revision: Int
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                BrandMark(size: .small)
                if let tenant = app.tenant {
                    Text(l10n.format("home.greeting", tenant.firstName))
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(TenantTheme.ink)
                }

                if let leases {
                    if let lease = current(in: leases) {
                        if leases.count > 1 {
                            leasePicker(leases, current: lease)
                        }
                        if !lease.status.isTerminal {
                            RentCard(lease: lease, rent: rent?.leaseId == lease.id ? rent : nil)
                        }
                        PayOnlineCard()
                        LeaseDetailsCard(lease: lease)
                        ReportIssueRow(leaseId: lease.id)
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
        .navigationTitle(l10n["home.title"])
        .refreshable {
            await load()
            await loadRent()
        }
        .task { if leases == nil { await load() } }
        .task(id: RentKey(leaseId: currentLeaseId, revision: navigation.rentRevision)) { await loadRent() }
    }

    /// The selected lease, else the active one, else the next one, else the newest.
    private func current(in leases: [TenantLease]) -> TenantLease? {
        leases.first { $0.id == selectedId } ?? leases.currentLease
    }

    private var currentLeaseId: String? {
        leases.flatMap { current(in: $0)?.id }
    }

    private func leasePicker(_ leases: [TenantLease], current: TenantLease) -> some View {
        Menu {
            ForEach(leases) { lease in
                Button {
                    selectedId = lease.id
                } label: {
                    Label(LeaseAddress(property: lease.property).firstLine(l10n),
                          systemImage: lease.id == current.id ? "checkmark" : "house")
                }
            }
        } label: {
            HStack {
                Text(LeaseAddress(property: current.property).firstLine(l10n))
                    .font(.subheadline.weight(.medium))
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption)
            }
            .foregroundStyle(TenantTheme.accent)
        }
    }

    private func load() async {
        error = nil
        do {
            leases = try await app.client.leases()
        } catch {
            if leases == nil { self.error = l10n.message(for: error) }
        }
    }

    /// The rent card works without this (amount + payment day from the lease); a failure
    /// only leaves the status pill and the declare button out, like the web.
    private func loadRent() async {
        guard let leaseId = currentLeaseId else {
            rent = nil
            return
        }
        if let loaded = try? await app.client.rent(leaseId: leaseId) {
            rent = loaded
        } else if rent?.leaseId != leaseId {
            rent = nil
        }
    }
}

// MARK: - Cards

private struct RentCard: View {
    @Environment(\.l10n) private var l10n
    let lease: TenantLease
    let rent: TenantRent?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                Text(l10n["home.rent.label"])
                    .font(.caption.weight(.semibold))
                    .textCase(.uppercase)
                    .foregroundStyle(TenantTheme.muted)
                Spacer()
                if let thisMonth = rent?.months.first {
                    // The newest month's real state ("Due", "Wire confirmed by property owner"…).
                    RentMonthStatusPill(month: thisMonth)
                        .frame(maxWidth: 180, alignment: .trailing)
                } else if let day = lease.paymentDayOfMonth {
                    Text(l10n.format("home.rent.dueDay", TenantFormatter.ordinal(day, language: l10n.language)))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(TenantTheme.accent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(TenantTheme.accent.opacity(0.1), in: Capsule())
                }
            }
            Text(TenantFormatter.money(lease.monthlyRent, currencyCode: lease.currencyCode, language: l10n.language))
                .font(.system(size: 40, weight: .bold))
                .foregroundStyle(TenantTheme.ink)
            Text(l10n.format("home.rent.for", TenantFormatter.monthYear(rentMonth, language: l10n.language)))
                .font(.subheadline)
                .foregroundStyle(TenantTheme.muted)
            if let upcoming = lease.upcomingRent {
                Text(l10n.format(
                    "home.rent.upcoming",
                    TenantFormatter.money(upcoming.monthlyRent, currencyCode: lease.currencyCode, language: l10n.language),
                    TenantFormatter.date(upcoming.effectiveFrom)))
                    .font(.footnote)
                    .foregroundStyle(TenantTheme.muted)
            }
            if let rent {
                if rent.canDeclare {
                    NavigationLink(value: Route.declareWire(leaseId: lease.id)) {
                        Label(l10n["home.rent.paidByTransfer"], systemImage: "building.columns")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .padding(.top, 4)
                    Text(l10n["home.rent.paidByTransfer.soon"])
                        .font(.footnote)
                        .foregroundStyle(TenantTheme.muted)
                        .frame(maxWidth: .infinity)
                } else {
                    Text(l10n["rent.nothingToDeclare"])
                        .font(.footnote)
                        .foregroundStyle(TenantTheme.muted)
                }
            } else {
                // Months not loaded (yet): the button waits rather than promising a declaration.
                Button(l10n["home.rent.paidByTransfer"]) {}
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(true)
                    .padding(.top, 4)
            }
        }
        .card()
    }

    /// This month, or the first month of a lease that has not started yet.
    private var rentMonth: Date { max(Date(), lease.startDate) }
}

private struct LeaseDetailsCard: View {
    @Environment(\.l10n) private var l10n
    let lease: TenantLease

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(l10n["home.lease.title"])
                    .font(.headline)
                    .foregroundStyle(TenantTheme.ink)
                Spacer()
                StatusBadge(lease: lease)
            }
            LeaseDetailsGrid(lease: lease)
        }
        .card()
    }
}

/// "Something broken? Report an issue" — opens the form for the lease on screen.
private struct ReportIssueRow: View {
    @Environment(\.l10n) private var l10n
    let leaseId: String

    var body: some View {
        NavigationLink(value: Route.reportIssue(leaseId: leaseId)) {
            HStack(spacing: 14) {
                Image(systemName: "wrench.and.screwdriver")
                    .font(.title2)
                    .foregroundStyle(TenantTheme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(l10n["home.issue.title"])
                        .font(.body.weight(.semibold))
                        .foregroundStyle(TenantTheme.ink)
                    Text(l10n["home.issue.body"])
                        .font(.footnote)
                        .foregroundStyle(TenantTheme.muted)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(TenantTheme.muted)
            }
            .card()
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Lease details (shared with the Route.leaseDetails screen)

struct LeaseDetailsView: View {
    @Environment(\.l10n) private var l10n
    let lease: TenantLease

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                StatusBadge(lease: lease)
                LeaseDetailsGrid(lease: lease)
            }
            .card()
            .padding(20)
        }
        .background(TenantTheme.ground)
        .navigationTitle(l10n["home.lease.title"])
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct StatusBadge: View {
    @Environment(\.l10n) private var l10n
    let lease: TenantLease

    var body: some View {
        Text(lease.isPastEnd ? l10n["lease.status.pastEnd"] : lease.status.label(l10n))
            .font(.caption.weight(.semibold))
            .foregroundStyle(lease.status == .active && !lease.isPastEnd ? TenantTheme.accent : TenantTheme.muted)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(TenantTheme.surface, in: Capsule())
    }
}

struct LeaseDetailsGrid: View {
    @Environment(\.l10n) private var l10n
    let lease: TenantLease

    private let columns = [GridItem(.flexible(), alignment: .topLeading), GridItem(.flexible(), alignment: .topLeading)]

    var body: some View {
        let address = LeaseAddress(property: lease.property)
        VStack(alignment: .leading, spacing: 14) {
            DetailCell(label: l10n["lease.address"], value: address.firstLine(l10n), secondary: address.secondLine(l10n))
            LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
                DetailCell(label: l10n["lease.startDate"], value: TenantFormatter.date(lease.startDate))
                DetailCell(label: l10n["lease.endDate"], value: lease.endDate.map { TenantFormatter.date($0) } ?? l10n["lease.openEnded"])
                DetailCell(label: l10n["lease.monthlyRent"], value: money(lease.monthlyRent))
                DetailCell(label: l10n["lease.deposit"], value: lease.depositAmount.map(money) ?? "—")
                DetailCell(label: l10n["lease.paymentDay"], value: lease.paymentDayOfMonth.map { l10n.format("lease.paymentDay.value", TenantFormatter.ordinal($0, language: l10n.language)) } ?? "—")
                DetailCell(label: l10n["lease.paymentMethod"], value: lease.paymentMethod?.label(l10n) ?? "—")
                DetailCell(label: l10n["lease.noticePeriod"], value: lease.noticePeriodMonths.map(months) ?? "—")
                DetailCell(label: l10n["lease.noticeDeadline"], value: lease.noticeDeadline.map { TenantFormatter.date($0) } ?? "—")
            }
        }
    }

    private func money(_ amount: Double) -> String {
        TenantFormatter.money(amount, currencyCode: lease.currencyCode, language: l10n.language)
    }

    private func months(_ n: Int) -> String {
        l10n.format(n == 1 ? "lease.months.one" : "lease.months.other", n)
    }
}

private struct DetailCell: View {
    let label: String
    let value: String
    var secondary: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.caption)
                .foregroundStyle(TenantTheme.muted)
            Text(value)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(TenantTheme.ink)
            if let secondary {
                Text(secondary)
                    .font(.subheadline)
                    .foregroundStyle(TenantTheme.muted)
            }
        }
    }
}

/// "Ermou 12, 3" / "2nd floor · 10563 Athens".
struct LeaseAddress {
    let property: TenantLeaseProperty

    func firstLine(_ l10n: L10n) -> String {
        let parts = [property.street, property.unitNumber].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? l10n["lease.address.unknown"] : parts.joined(separator: ", ")
    }

    func secondLine(_ l10n: L10n) -> String? {
        var parts: [String] = []
        if let floor = property.floor { parts.append(floor.label(l10n)) }
        let place = [property.postalCode, property.cityName].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
        if !place.isEmpty { parts.append(place) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
