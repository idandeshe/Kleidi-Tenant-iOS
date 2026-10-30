import SwiftUI
import TenantAPI

/// Screens one feature opens in another feature's folder. Each case has a fixed
/// destination view whose initializer is the contract between the two features.
enum Route: Hashable {
    /// The full terms of one lease (Home → another lease of the tenant).
    case leaseDetails(TenantLease)
    /// "Report an issue" for this lease (Home, the Issues list and a closed thread → the form).
    case reportIssue(leaseId: String)
    /// "I paid by bank transfer" for this lease (Home and Payments → Declare).
    case declareWire(leaseId: String)
    /// One issue's thread (the Issues list, and the form right after a report).
    case issue(id: String)
}

/// The view for a `Route` — used by every navigation stack.
struct RouteDestination: View {
    let route: Route

    var body: some View {
        switch route {
        case .leaseDetails(let lease): LeaseDetailsView(lease: lease)
        case .reportIssue(let leaseId): ReportIssueView(leaseId: leaseId)
        case .declareWire(let leaseId): DeclareWireView(leaseId: leaseId)
        case .issue(let id): IssueDetailView(id: id)
        }
    }
}

extension View {
    func withTenantDestinations() -> some View {
        navigationDestination(for: Route.self) { RouteDestination(route: $0) }
    }
}
