import SwiftUI

/// Shown when the server answers 426 or `/tenant/config` says this build is too old.
struct UpdateRequiredView: View {
    @Environment(\.l10n) private var l10n
    let appStoreURL: URL?

    var body: some View {
        ContentUnavailableView {
            Label(l10n["update.title"], systemImage: "arrow.down.app")
        } description: {
            Text(l10n["update.body"])
        } actions: {
            if let appStoreURL {
                Link(l10n["update.action"], destination: appStoreURL)
                    .buttonStyle(.borderedProminent)
            }
        }
    }
}
