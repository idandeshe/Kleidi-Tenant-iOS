import SwiftUI
import TenantCore

/// Picks the screen for the app's phase. The language screen comes before everything
/// else (except a forced update) until a language has been chosen once; the chosen
/// language's `L10n` is injected here for the whole tree, so a switch in Profile
/// re-renders every screen without a restart.
struct RootView: View {
    @Environment(AppModel.self) private var app
    @AppStorage(LanguageSetting.key) private var languageRaw = ""

    var body: some View {
        let chosen = AppLanguage(rawValue: languageRaw)
        Group {
            switch app.phase {
            case .updateRequired(let url):
                UpdateRequiredView(appStoreURL: url)
            case _ where chosen == nil:
                LanguageView()
            case .launching:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .signedOut(let noticeKey):
                AuthFlowView(noticeKey: noticeKey)
            case .signedIn:
                MainTabView()
            }
        }
        .environment(\.l10n, L10n(language: chosen ?? .deviceDefault()))
        .background(TenantTheme.ground)
        // The approved design is light-only.
        .preferredColorScheme(.light)
    }
}
