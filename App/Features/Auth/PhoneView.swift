import SwiftUI
import TenantAPI
import TenantCore

/// A code was sent to this number; the code screen is pushed with it.
struct PendingCode: Hashable {
    let phone: String
    let expiresInSeconds: Int
}

/// Sign-in: phone number → SMS code.
struct AuthFlowView: View {
    let noticeKey: String?
    @State private var path: [PendingCode] = []

    var body: some View {
        NavigationStack(path: $path) {
            PhoneView(noticeKey: noticeKey) { path.append($0) }
                .navigationDestination(for: PendingCode.self) { CodeView(pending: $0) }
        }
    }
}

struct PhoneView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.l10n) private var l10n
    let noticeKey: String?
    let onCodeSent: (PendingCode) -> Void

    @State private var countryCode = "+30"
    @State private var number = ""
    @State private var isSubmitting = false
    @State private var error: String?
    @FocusState private var focused: Field?

    private enum Field { case countryCode, number }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Kleidi")
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(TenantTheme.accent)
                    Text(l10n["auth.phone.title"])
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(TenantTheme.ink)
                    Text(l10n["auth.phone.subtitle"])
                        .font(.subheadline)
                        .foregroundStyle(TenantTheme.muted)
                }
                .padding(.top, 32)

                if let notice = error ?? noticeKey.map({ l10n[$0] }) {
                    NoticeLabel(text: notice, isError: error != nil)
                }

                HStack(spacing: 12) {
                    TextField("+30", text: $countryCode)
                        .keyboardType(.phonePad)
                        .frame(width: 84)
                        .multilineTextAlignment(.center)
                        .focused($focused, equals: .countryCode)
                        .field()
                        .accessibilityLabel(l10n["auth.phone.countryCode"])
                    TextField(l10n["auth.phone.placeholder"], text: $number)
                        .keyboardType(.phonePad)
                        .textContentType(.telephoneNumber)
                        .focused($focused, equals: .number)
                        .field()
                        .accessibilityLabel(l10n["auth.phone.number"])
                }
                .onChange(of: countryCode) { _, value in
                    let digits = String(value.filter(\.isNumber).prefix(3))
                    if value != "+\(digits)" { countryCode = "+\(digits)" }
                }

                Text(l10n["auth.phone.hint"])
                    .font(.footnote)
                    .foregroundStyle(TenantTheme.muted)

                Button {
                    Task { await submit() }
                } label: {
                    if isSubmitting {
                        ProgressView().tint(.white)
                    } else {
                        Text(l10n["auth.phone.send"])
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!canSubmit)

                if app.config?.smsConfigured == false {
                    NoticeLabel(text: l10n["auth.phone.smsOff"], isError: false)
                }

                if app.environment.kind != .prod {
                    Text(l10n.format("auth.phone.server", app.environment.baseURL.host() ?? app.environment.baseURL.absoluteString))
                        .font(.caption)
                        .foregroundStyle(TenantTheme.muted)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(24)
        }
        .background(TenantTheme.ground)
        .scrollDismissesKeyboard(.interactively)
        .onAppear { focused = .number }
    }

    /// `+30` + `6912345678` → `+306912345678`. nil until both parts look like a phone number.
    private var e164: String? {
        let code = countryCode.filter(\.isNumber)
        var digits = number.filter(\.isNumber)
        // "0030 691…" or "0691…" typed into the number field.
        if digits.hasPrefix("00\(code)") { digits.removeFirst(2 + code.count) }
        if digits.hasPrefix("0") { digits.removeFirst() }
        guard (1...3).contains(code.count), (6...14).contains(digits.count) else { return nil }
        return "+\(code)\(digits)"
    }

    private var canSubmit: Bool { !isSubmitting && e164 != nil }

    private func submit() async {
        guard let phone = e164, canSubmit else { return }
        isSubmitting = true
        error = nil
        defer { isSubmitting = false }
        do {
            let response = try await app.requestCode(phone: phone)
            onCodeSent(PendingCode(phone: phone, expiresInSeconds: response.expiresInSeconds))
        } catch let apiError as APIError where apiError.status == 400 {
            error = l10n["auth.error.badPhone"]
        } catch {
            self.error = l10n.message(for: error)
        }
    }
}
