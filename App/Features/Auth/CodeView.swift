import SwiftUI
import TenantAPI
import TenantCore

/// Six-digit code entry. A hidden text field drives the boxes so the number pad and
/// the Messages one-time-code suggestion both work; six digits submit automatically.
struct CodeView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.l10n) private var l10n
    let pending: PendingCode

    @State private var code = ""
    @State private var isSubmitting = false
    @State private var error: String?
    @State private var infoKey: String?
    @State private var secondsLeft: Int
    @State private var resendCooldown = CodeView.resendInterval
    @FocusState private var focused: Bool

    static let length = 6
    /// The server sends at most one code a minute (TENANT_AUTH_CONFIG.CODE_RESEND_INTERVAL_MS).
    static let resendInterval = 60

    init(pending: PendingCode) {
        self.pending = pending
        _secondsLeft = State(initialValue: pending.expiresInSeconds)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(l10n["auth.code.title"])
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(TenantTheme.ink)
                    Text(l10n.format("auth.code.subtitle", pending.phone))
                        .font(.subheadline)
                        .foregroundStyle(TenantTheme.muted)
                }
                .padding(.top, 16)

                ZStack {
                    HStack(spacing: 10) {
                        ForEach(0..<Self.length, id: \.self) { index in
                            CodeBox(digit: digit(at: index), isActive: focused && code.count == index)
                        }
                    }
                    TextField("", text: $code)
                        .keyboardType(.numberPad)
                        .textContentType(.oneTimeCode)
                        .focused($focused)
                        .frame(width: 1, height: 1)
                        .opacity(0.02)
                        .accessibilityLabel(l10n["auth.code.title"])
                }
                .contentShape(Rectangle())
                .onTapGesture { focused = true }
                .onChange(of: code) { _, value in
                    let digits = String(value.filter(\.isNumber).prefix(Self.length))
                    if digits != value {
                        code = digits
                        return
                    }
                    if digits.count == Self.length { Task { await submit() } }
                }

                if let error {
                    NoticeLabel(text: error)
                } else if let infoKey {
                    NoticeLabel(text: l10n[infoKey], isError: false)
                }

                Text(secondsLeft > 0
                     ? l10n.format("auth.code.expiresIn", countdown(secondsLeft))
                     : l10n["auth.code.expired"])
                    .font(.footnote)
                    .foregroundStyle(TenantTheme.muted)
                    .monospacedDigit()

                Button {
                    Task { await submit() }
                } label: {
                    if isSubmitting {
                        ProgressView().tint(.white)
                    } else {
                        Text(l10n["auth.code.verify"])
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(isSubmitting || code.count < Self.length)

                Button {
                    Task { await resend() }
                } label: {
                    Text(resendCooldown > 0
                         ? l10n.format("auth.code.resendIn", resendCooldown)
                         : l10n["auth.code.resend"])
                        .font(.body.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .monospacedDigit()
                }
                .disabled(resendCooldown > 0 || isSubmitting)
            }
            .padding(24)
        }
        .background(TenantTheme.ground)
        .scrollDismissesKeyboard(.interactively)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { focused = true }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                if secondsLeft > 0 { secondsLeft -= 1 }
                if resendCooldown > 0 { resendCooldown -= 1 }
            }
        }
    }

    private func digit(at index: Int) -> String {
        guard index < code.count else { return "" }
        return String(code[code.index(code.startIndex, offsetBy: index)])
    }

    private func countdown(_ seconds: Int) -> String {
        let s = seconds % 60
        return "\(seconds / 60):\(s < 10 ? "0" : "")\(s)"
    }

    private func submit() async {
        guard !isSubmitting, code.count == Self.length else { return }
        isSubmitting = true
        error = nil
        infoKey = nil
        defer { isSubmitting = false }
        do {
            try await app.verifyCode(phone: pending.phone, code: code)
        } catch {
            self.error = l10n.message(for: error)
            code = ""
            focused = true
        }
    }

    private func resend() async {
        guard resendCooldown == 0, !isSubmitting else { return }
        error = nil
        do {
            let response = try await app.requestCode(phone: pending.phone)
            secondsLeft = response.expiresInSeconds
            resendCooldown = Self.resendInterval
            code = ""
            infoKey = "auth.code.resent"
            focused = true
        } catch {
            self.error = l10n.message(for: error)
        }
    }
}

private struct CodeBox: View {
    let digit: String
    let isActive: Bool

    var body: some View {
        Text(digit)
            .font(.system(size: 28, weight: .semibold, design: .rounded))
            .foregroundStyle(TenantTheme.ink)
            .frame(maxWidth: .infinity, minHeight: 60)
            .background(TenantTheme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isActive ? TenantTheme.accent : TenantTheme.hairline, lineWidth: isActive ? 2 : 1)
            )
    }
}
