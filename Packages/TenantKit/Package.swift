// swift-tools-version: 6.0
//
// TenantKit — everything in the Kleidi Tenant iOS app that is not the app target itself.
//
// - TenantCore: pure model code (app language, localized string lookup, lease values and
//               display formatting). Foundation only.
// - TenantAPI:  networking against `/api/tenant/*` (phone + SMS-code session, endpoints,
//               Codable models, Keychain token store). Foundation only.
//
// Both build and test on Linux (`swift test`), e.g. in the Kleidi server's dev container.
import PackageDescription

let package = Package(
    name: "TenantKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "TenantCore", targets: ["TenantCore"]),
        .library(name: "TenantAPI", targets: ["TenantAPI"]),
    ],
    targets: [
        .target(name: "TenantCore"),
        .target(name: "TenantAPI", dependencies: ["TenantCore"]),
        .testTarget(name: "TenantCoreTests", dependencies: ["TenantCore"]),
        .testTarget(name: "TenantAPITests", dependencies: ["TenantAPI"]),
    ],
    swiftLanguageModes: [.v6]
)
