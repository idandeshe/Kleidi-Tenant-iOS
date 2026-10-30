import Foundation
import Observation

/// The tab bar's selection plus the one cross-screen signal the app needs: a declaration
/// was sent, so Home and Payments reload the rent months. Lives in the environment under
/// `MainTabView` (the Declare screen is pushed inside a tab and ends by switching tabs).
@Observable
@MainActor
final class AppNavigation {
    enum Tab: Hashable { case home, payments, issues, profile }

    var tab: Tab = .home
    /// Bumped after a successful "I paid by bank transfer"; screens `.task(id:)` on it.
    private(set) var rentRevision = 0

    func rentDidChange() {
        rentRevision += 1
    }
}
