import SwiftUI
import TenantCore

/// First onboarding screen: pick Ελληνικά or English. Pre-highlights the device
/// language; the copy follows the highlighted choice so both readers understand it.
struct LanguageView: View {
    @AppStorage(LanguageSetting.key) private var languageRaw = ""
    @State private var selected: AppLanguage = .deviceDefault()

    var body: some View {
        let l10n = L10n(language: selected)
        VStack(spacing: 32) {
            Spacer()
            VStack(spacing: 8) {
                Text("Kleidi")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(TenantTheme.accent)
                Text(l10n["language.title"])
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(TenantTheme.ink)
                Text(l10n["language.subtitle"])
                    .font(.subheadline)
                    .foregroundStyle(TenantTheme.muted)
                    .multilineTextAlignment(.center)
            }
            VStack(spacing: 12) {
                ForEach(AppLanguage.allCases) { language in
                    LanguageButton(language: language, isSelected: selected == language) {
                        selected = language
                    }
                }
            }
            Spacer()
            Button(l10n["language.continue"]) {
                languageRaw = selected.rawValue
            }
            .buttonStyle(PrimaryButtonStyle())
        }
        .padding(24)
        .background(TenantTheme.ground)
        .animation(.easeInOut(duration: 0.15), value: selected)
    }
}

private struct LanguageButton: View {
    let language: AppLanguage
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(language.nativeName)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(isSelected ? TenantTheme.accent : TenantTheme.ink)
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? TenantTheme.accent : TenantTheme.hairline)
            }
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, minHeight: 64)
            .background(
                (isSelected ? TenantTheme.accent.opacity(0.08) : TenantTheme.ground),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isSelected ? TenantTheme.accent : TenantTheme.hairline, lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
