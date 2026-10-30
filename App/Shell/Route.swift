import SwiftUI
import TenantAPI

/// Screens one feature opens in another feature's folder. Each case has a fixed
/// destination view whose initializer is the contract between the two features.
enum Route: Hashable {
    /// The full terms of one lease (Home → another lease of the tenant).
    case leaseDetails(TenantLease)
    /// "Something broken? Report an issue" — a placeholder until the issues release.
    case reportIssue
    /// "I paid by bank transfer" for this lease (Home and Payments → Declare).
    case declareWire(leaseId: String)
}

/// The view for a `Route` — used by every navigation stack.
struct RouteDestination: View {
    let route: Route

    var body: some View {
        switch route {
        case .leaseDetails(let lease): LeaseDetailsView(lease: lease)
        case .reportIssue: ComingSoonView(titleKey: "home.issue.title", bodyKey: "issues.comingSoon", icon: "wrench.and.screwdriver")
        case .declareWire(let leaseId): DeclareWireView(leaseId: leaseId)
        }
    }
}

extension View {
    func withTenantDestinations() -> some View {
        navigationDestination(for: Route.self) { RouteDestination(route: $0) }
    }
}
