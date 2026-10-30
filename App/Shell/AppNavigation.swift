import Foundation
import Observation

/// The tab bar's selection plus the cross-screen signals the app needs: a declaration was
/// sent, so Home and Payments reload the rent months; an issue was reported, answered or
/// opened, so the Issues list reloads. Lives in the environment under `MainTabView` (the
/// Declare and Report screens are pushed inside a tab and end by switching tabs).
@Observable
@MainActor
final class AppNavigation {
    enum Tab: Hashable { case home, payments, issues, profile }

    var tab: Tab = .home
    /// The Issues tab's stack, driven from here so a report can land on its new thread.
    var issuesPath: [Route] = []
    /// Bumped after a successful "I paid by bank transfer"; screens `.task(id:)` on it.
    private(set) var rentRevision = 0
    /// Bumped after a report, a reply or an opened thread (the "new reply" dot clears); the list `.task(id:)`s on it.
    private(set) var issuesRevision = 0

    func rentDidChange() {
        rentRevision += 1
    }

    func issuesDidChange() {
        issuesRevision += 1
    }

    /// Shows one issue's thread in the Issues tab, straight over the list (whatever that tab
    /// had pushed — the report form included — is replaced).
    func showIssue(id: String) {
        tab = .issues
        issuesPath = [.issue(id: id)]
    }
}
