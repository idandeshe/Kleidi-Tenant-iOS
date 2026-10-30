import SwiftUI

/// The approved mock-up: white ground, ink text, one accent blue, system font.
enum TenantTheme {
    static let ink = Color(red: 0x15 / 255, green: 0x20 / 255, blue: 0x2B / 255)
    static let accent = Color(red: 0x1E / 255, green: 0x5A / 255, blue: 0xA8 / 255)
    static let muted = Color(red: 0x5B / 255, green: 0x67 / 255, blue: 0x76 / 255)
    static let hairline = Color(red: 0xE3 / 255, green: 0xE7 / 255, blue: 0xEC / 255)
    static let surface = Color(red: 0xF5 / 255, green: 0xF7 / 255, blue: 0xFA / 255)
    static let error = Color(red: 0xB4 / 255, green: 0x23 / 255, blue: 0x18 / 255)
    static let ground = Color.white

    // Status pills and alerts (the web tenant-client `--t-ok-*`, `--t-warn-*`, `--t-error-*`, `--t-accent-*`).
    static let okBackground = Color(red: 0xDC / 255, green: 0xFC / 255, blue: 0xE7 / 255)
    static let okInk = Color(red: 0x16 / 255, green: 0x65 / 255, blue: 0x34 / 255)
    static let warnBackground = Color(red: 0xFE / 255, green: 0xF3 / 255, blue: 0xC7 / 255)
    static let warnInk = Color(red: 0x92 / 255, green: 0x40 / 255, blue: 0x0E / 255)
    static let errorBackground = Color(red: 0xFE / 255, green: 0xF2 / 255, blue: 0xF2 / 255)
    static let errorInk = Color(red: 0x99 / 255, green: 0x1B / 255, blue: 0x1B / 255)
    static let accentBackground = Color(red: 0xEF / 255, green: 0xF6 / 255, blue: 0xFF / 255)
    static let accentInk = Color(red: 0x1E / 255, green: 0x3A / 255, blue: 0x8A / 255)
    static let neutralBackground = Color(red: 0xF3 / 255, green: 0xF4 / 255, blue: 0xF6 / 255)
    static let neutralInk = Color(red: 0x37 / 255, green: 0x41 / 255, blue: 0x51 / 255)
}

/// Colour pair of a status pill / alert.
struct StatusTone {
    let background: Color
    let ink: Color

    static let ok = StatusTone(background: TenantTheme.okBackground, ink: TenantTheme.okInk)
    static let warn = StatusTone(background: TenantTheme.warnBackground, ink: TenantTheme.warnInk)
    static let error = StatusTone(background: TenantTheme.errorBackground, ink: TenantTheme.errorInk)
    static let accent = StatusTone(background: TenantTheme.accentBackground, ink: TenantTheme.accentInk)
    static let neutral = StatusTone(background: TenantTheme.neutralBackground, ink: TenantTheme.neutralInk)
}

/// Full-width accent button (sign-in, continue, "I paid").
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(
                TenantTheme.accent.opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.35),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
    }
}

/// A white card with a hairline border.
struct CardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(TenantTheme.ground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(TenantTheme.hairline))
    }
}

/// A text field on the light surface.
struct FieldModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.title3)
            .padding(.horizontal, 14)
            .frame(minHeight: 52)
            .background(TenantTheme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(TenantTheme.hairline))
    }
}

extension View {
    func card() -> some View { modifier(CardModifier()) }
    func field() -> some View { modifier(FieldModifier()) }
}

/// An inline error or information line.
struct NoticeLabel: View {
    let text: String
    var isError = true

    var body: some View {
        Label(text, systemImage: isError ? "exclamationmark.circle" : "info.circle")
            .font(.subheadline)
            .foregroundStyle(isError ? TenantTheme.error : TenantTheme.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Small uppercase tag ("COMING SOON").
struct PillTag: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .textCase(.uppercase)
            .foregroundStyle(TenantTheme.accent)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(TenantTheme.accent.opacity(0.1), in: Capsule())
    }
}

/// A tinted status pill ("Paid", "Wire declared, waiting for confirmation"); wraps when long.
struct StatusPill: View {
    let text: String
    let tone: StatusTone

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tone.ink)
            .multilineTextAlignment(.leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(tone.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// A tinted notice box (the web `.t-alert`): a red one for a rejected wire, a blue one for information.
struct AlertBox: View {
    let text: String
    var tone: StatusTone = .error
    var secondary: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(text)
            if let secondary {
                Text(secondary)
            }
        }
        .font(.footnote)
        .foregroundStyle(tone.ink)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tone.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(tone.ink.opacity(0.25)))
    }
}
