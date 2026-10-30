import SwiftUI
import TenantAPI

/// Home · Payments · Issues · Profile. The Issues tab shows how many threads have a reply from
/// the property manager the tenant has not opened yet; the count is read at launch and whenever
/// the app comes back to the foreground, and the Issues list keeps it current while it is used.
struct MainTabView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.l10n) private var l10n
    @Environment(\.scenePhase) private var scenePhase
    @State private var navigation = AppNavigation()

    var body: some View {
        @Bindable var navigation = navigation
        TabView(selection: $navigation.tab) {
            NavigationStack {
                HomeView().withTenantDestinations()
            }
            .tabItem { Label(l10n["tab.home"], systemImage: "house") }
            .tag(AppNavigation.Tab.home)

            NavigationStack {
                PaymentsView().withTenantDestinations()
            }
            .tabItem { Label(l10n["tab.payments"], systemImage: "creditcard") }
            .tag(AppNavigation.Tab.payments)

            // Path-driven: a report sent from Home or from the list lands on its new thread.
            NavigationStack(path: $navigation.issuesPath) {
                IssuesView().withTenantDestinations()
            }
            .tabItem { Label(l10n["tab.issues"], systemImage: "wrench.and.screwdriver") }
            .badge(navigation.unreadIssueCount)
            .tag(AppNavigation.Tab.issues)

            NavigationStack {
                ProfileView()
            }
            .tabItem { Label(l10n["tab.profile"], systemImage: "person") }
            .tag(AppNavigation.Tab.profile)
        }
        .environment(navigation)
        .task { await refreshUnreadIssues() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await refreshUnreadIssues() } }
        }
    }

    /// The same issues the Issues tab lists (the current lease's); best effort — a failure
    /// leaves the badge as it was, the list itself reports errors.
    private func refreshUnreadIssues() async {
        guard let lease = try? await app.client.leases().currentLease,
              let issues = try? await app.client.issues(leaseId: lease.id) else { return }
        navigation.issuesDidLoad(issues)
    }
}
