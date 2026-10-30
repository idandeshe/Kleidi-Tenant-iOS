import SwiftUI
import TenantAPI
import TenantCore

/// "My issues": the current lease's reported issues — open ones (received / in progress)
/// above the resolved and closed ones — each with its category icon, status pill, urgent
/// line and the "new reply" dot. "Report an issue" opens the form; a row opens the thread.
/// Shows the same lease as Home's default (the active one, else the next, else the newest).
struct IssuesView: View {
    @Environment(AppModel.self) private var app
    @Environment(AppNavigation.self) private var navigation
    @Environment(\.l10n) private var l10n

    @State private var leases: [TenantLease]?
    @State private var issues: [TenantIssue]?
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let leases {
                    if let lease = leases.currentLease {
                        Text(LeaseAddress(property: lease.property).firstLine(l10n))
                            .font(.subheadline)
                            .foregroundStyle(TenantTheme.muted)
                        NavigationLink(value: Route.reportIssue(leaseId: lease.id)) {
                            Label(l10n["issues.report"], systemImage: "plus.circle.fill")
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        if let issues {
                            issueList(issues)
                        } else if let error {
                            NoticeLabel(text: error)
                            retryButton
                        } else {
                            loading
                        }
                    } else {
                        ContentUnavailableView(
                            l10n["home.noLease.title"], systemImage: "house",
                            description: Text(l10n["home.noLease.body"]))
                    }
                } else if let error {
                    NoticeLabel(text: error)
                    retryButton
                } else {
                    loading
                }
            }
            .padding(20)
        }
        .background(TenantTheme.ground)
        .navigationTitle(l10n["tab.issues"])
        .refreshable { await load() }
        // Runs on appear and again after a report, a reply or an opened thread.
        .task(id: navigation.issuesRevision) { await load() }
    }

    @ViewBuilder
    private func issueList(_ issues: [TenantIssue]) -> some View {
        let open = issues.filter { $0.status.isOpen }
        let settled = issues.filter { !$0.status.isOpen }
        if issues.isEmpty {
            ContentUnavailableView(
                l10n["issues.empty.title"], systemImage: "wrench.and.screwdriver",
                description: Text(l10n["issues.empty.body"]))
                .padding(.top, 24)
        }
        if !open.isEmpty {
            section(l10n["issues.section.open"], open)
        }
        if !settled.isEmpty {
            section(l10n["issues.section.resolved"], settled)
        }
    }

    private func section(_ title: String, _ items: [TenantIssue]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .foregroundStyle(TenantTheme.muted)
                .padding(.top, 4)
            ForEach(items) { issue in
                NavigationLink(value: Route.issue(id: issue.id)) {
                    IssueRow(issue: issue)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var retryButton: some View {
        Button(l10n["common.retry"]) { Task { await load() } }
            .buttonStyle(.bordered)
    }

    private var loading: some View {
        ProgressView()
            .frame(maxWidth: .infinity)
            .padding(.top, 48)
    }

    private func load() async {
        error = nil
        do {
            let loaded = try await app.client.leases()
            leases = loaded
            guard let lease = loaded.currentLease else {
                issues = nil
                navigation.issuesDidLoad([])
                return
            }
            let loadedIssues = try await app.client.issues(leaseId: lease.id)
            issues = loadedIssues
            navigation.issuesDidLoad(loadedIssues)
        } catch {
            // Keep what is already on screen; report only when there is nothing to show.
            if issues == nil || leases == nil { self.error = l10n.message(for: error) }
        }
    }
}

// MARK: - Row

/// One issue in the list: category icon tile, summary, status pill, "Plumbing · reported
/// 27/10/2026", the red "Urgent" line while open and the blue dot when staff answered.
struct IssueRow: View {
    @Environment(\.l10n) private var l10n
    let issue: TenantIssue

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            IssueCategoryIcon(category: issue.category, tone: iconTone)
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top, spacing: 8) {
                    Text(issue.summary)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(issue.status.isOpen ? TenantTheme.ink : TenantTheme.neutralInk)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    IssueStatusPill(status: issue.status)
                }
                Text(metaLine)
                    .font(.caption)
                    .foregroundStyle(TenantTheme.muted)
                if issue.isUrgent && issue.status.isOpen {
                    Label(l10n["issues.urgent"], systemImage: "exclamationmark.triangle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(TenantTheme.errorInk)
                }
                if issue.tenantUnread {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(TenantTheme.accent)
                            .frame(width: 8, height: 8)
                        Text(l10n["issues.newReply"])
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(TenantTheme.accent)
                }
            }
        }
        .card()
    }

    /// "Plumbing · reported 27/10/2026", "… · resolved 12/09/2026" or "… · closed 12/09/2026".
    private var metaLine: String {
        let category = issue.category.label(l10n)
        if issue.status == .resolved, let date = issue.resolvedAt {
            return l10n.format("issues.resolvedOn", category, TenantFormatter.date(date))
        }
        if issue.status == .closed, let date = issue.closedAt {
            return l10n.format("issues.closedOn", category, TenantFormatter.date(date))
        }
        return l10n.format("issues.reportedOn", category, TenantFormatter.date(issue.createdAt))
    }

    /// Blue while open, red when urgent, grey once resolved or closed (the mock-up's tiles).
    private var iconTone: StatusTone {
        guard issue.status.isOpen else { return .neutral }
        return issue.isUrgent ? .error : .accent
    }
}

/// The category's SF Symbol on a tinted rounded square.
struct IssueCategoryIcon: View {
    let category: TenantIssueCategory
    var tone: StatusTone = .accent
    var size: CGFloat = 40

    var body: some View {
        Image(systemName: category.symbolName)
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(tone.ink)
            .frame(width: size, height: size)
            .background(tone.background, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

/// The issue's status pill — also the pill in the thread header.
struct IssueStatusPill: View {
    @Environment(\.l10n) private var l10n
    let status: TenantIssueStatus

    var body: some View {
        StatusPill(text: status.label(l10n), tone: IssueTones.tone(for: status))
    }
}

/// Pill colours per status (the mock-up: Received blue, In progress amber, Resolved green,
/// Closed grey); unknown values are neutral.
enum IssueTones {
    static func tone(for status: TenantIssueStatus) -> StatusTone {
        switch status {
        case .new: return .accent
        case .inProgress: return .warn
        case .resolved: return .ok
        default: return .neutral
        }
    }
}
