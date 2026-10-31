import SwiftUI
import TenantAPI
import TenantCore

struct ProfileView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.l10n) private var l10n
    @AppStorage(LanguageSetting.key) private var languageRaw = ""

    @State private var isBusy = false
    @State private var isConfirmingSignOutAll = false
    @State private var error: String?
    @State private var serverField = ""

    var body: some View {
        Form {
            if let tenant = app.tenant {
                Section {
                    LabeledContent(l10n["profile.name"], value: tenant.fullName)
                    LabeledContent(l10n["profile.phone"], value: tenant.phone)
                    if let email = tenant.email, !email.isEmpty {
                        LabeledContent(l10n["profile.email"], value: email)
                    }
                }
            }

            Section {
                Picker(l10n["profile.language"], selection: languageSelection) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.nativeName).tag(language)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } header: {
                Text(l10n["profile.language"])
            } footer: {
                Text(l10n["profile.language.footer"])
            }

            Section {
                Button(l10n["profile.signOut"], role: .destructive) {
                    Task { await run { await app.signOut() } }
                }
                Button(l10n["profile.signOutEverywhere"], role: .destructive) {
                    isConfirmingSignOutAll = true
                }
            } footer: {
                VStack(spacing: 12) {
                    BrandMark(size: .small)
                    Text(l10n.format("profile.version", ServerEnvironment.appVersion, ServerEnvironment.clientBuild))
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 16)
            }
            .disabled(isBusy)

            if app.environment.allowsServerOverride {
                Section {
                    TextField("http://192.168.1.10:3000", text: $serverField)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button(l10n["profile.server.use"]) {
                        guard let url = URL(string: serverField.trimmingCharacters(in: .whitespaces)), url.host() != nil else { return }
                        Task { await app.switchServer(to: url) }
                    }
                    Button(l10n["profile.server.reset"]) {
                        Task { await app.switchServer(to: nil) }
                    }
                } header: {
                    Text(l10n["profile.server"])
                } footer: {
                    Text(l10n.format("profile.server.current", app.environment.baseURL.absoluteString))
                }
            }
        }
        .navigationTitle(l10n["tab.profile"])
        .confirmationDialog(l10n["profile.signOutEverywhere.confirm"], isPresented: $isConfirmingSignOutAll, titleVisibility: .visible) {
            Button(l10n["profile.signOutEverywhere"], role: .destructive) {
                Task { await run { try await app.signOutEverywhere() } }
            }
        }
        .alert(l10n["common.error"], isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button(l10n["common.ok"], role: .cancel) {}
        } message: {
            Text(error ?? "")
        }
        .onAppear { serverField = app.environment.baseURL.absoluteString }
    }

    /// Switches the copy at once and tells the server; a failed PATCH is reported, the local choice stays.
    private var languageSelection: Binding<AppLanguage> {
        Binding(
            get: { AppLanguage(rawValue: languageRaw) ?? l10n.language },
            set: { language in
                Task {
                    do {
                        try await app.updateLanguage(language)
                    } catch {
                        self.error = L10n(language: language).message(for: error)
                    }
                }
            }
        )
    }

    private func run(_ action: () async throws -> Void) async {
        isBusy = true
        defer { isBusy = false }
        do {
            try await action()
        } catch {
            self.error = l10n.message(for: error)
        }
    }
}
