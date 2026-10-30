import SwiftUI

@main
struct KleidiTenantApp: App {
    @State private var app = AppModel(environment: .current)

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .tint(TenantTheme.accent)
                .task { await app.start() }
        }
    }
}
