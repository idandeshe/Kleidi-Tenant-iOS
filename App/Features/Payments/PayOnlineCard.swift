import SwiftUI

/// The dashed "Pay online — COMING SOON" row, drawn the same on Home and on Payments.
struct PayOnlineCard: View {
    @Environment(\.l10n) private var l10n

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "creditcard")
                .font(.title2)
                .foregroundStyle(TenantTheme.muted)
            VStack(alignment: .leading, spacing: 2) {
                Text(l10n["home.payOnline.title"])
                    .font(.body.weight(.semibold))
                    .foregroundStyle(TenantTheme.ink)
                Text(l10n["home.payOnline.body"])
                    .font(.footnote)
                    .foregroundStyle(TenantTheme.muted)
            }
            Spacer()
            PillTag(text: l10n["common.comingSoon"])
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(TenantTheme.hairline, style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
        )
    }
}
