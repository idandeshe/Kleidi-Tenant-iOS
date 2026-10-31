import SwiftUI

/// The Houseman Brokers and Seamphony marks side by side (the web tenant-client `BrandMark`).
/// `.large` heads the sign-in screens; `.small` sits on Home and above the version on Profile.
struct BrandMark: View {
    enum Size {
        case large, small

        var houseman: CGFloat { self == .large ? 56 : 28 }
        var seamphony: CGFloat { self == .large ? 24 : 13 }
        var spacing: CGFloat { self == .large ? 16 : 10 }
    }

    let size: Size

    var body: some View {
        HStack(spacing: size.spacing) {
            Image("HousemanLogo")
                .resizable()
                .scaledToFit()
                .frame(height: size.houseman)
                .clipShape(RoundedRectangle(cornerRadius: size == .large ? 8 : 4, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: size == .large ? 8 : 4, style: .continuous)
                        .stroke(TenantTheme.hairline, lineWidth: 1)
                )
            Rectangle()
                .fill(TenantTheme.hairline)
                .frame(width: 1, height: size.houseman)
            VStack(spacing: 4) {
                Image("SeamphonyLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(height: size.seamphony)
                if size == .large {
                    Text(verbatim: "GREAT THINGS TOGETHER")
                        .font(.system(size: 6, weight: .medium))
                        .tracking(0.7)
                        .lineLimit(1)
                        .foregroundStyle(TenantTheme.ink)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "Houseman Brokers, Seamphony"))
        .accessibilityAddTraits(.isImage)
    }
}
