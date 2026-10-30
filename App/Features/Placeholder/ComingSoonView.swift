import SwiftUI

/// Payments, Issues and "Report an issue" until their release.
struct ComingSoonView: View {
    @Environment(\.l10n) private var l10n
    let titleKey: String
    let bodyKey: String
    let icon: String

    var body: some View {
        ContentUnavailableView {
            Label(l10n[titleKey], systemImage: icon)
        } description: {
            Text(l10n[bodyKey])
        }
        .navigationTitle(l10n[titleKey])
        .navigationBarTitleDisplayMode(.inline)
    }
}
