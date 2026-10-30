import SwiftUI

/// Home · Payments · Issues · Profile. Issues is a placeholder until its release.
struct MainTabView: View {
    @Environment(\.l10n) private var l10n
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

            NavigationStack {
                ComingSoonView(titleKey: "tab.issues", bodyKey: "issues.comingSoon", icon: "wrench.and.screwdriver")
            }
            .tabItem { Label(l10n["tab.issues"], systemImage: "wrench.and.screwdriver") }
            .tag(AppNavigation.Tab.issues)

            NavigationStack {
                ProfileView()
            }
            .tabItem { Label(l10n["tab.profile"], systemImage: "person") }
            .tag(AppNavigation.Tab.profile)
        }
        .environment(navigation)
    }
}
