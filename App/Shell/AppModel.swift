import Foundation
import Observation
import TenantAPI
import TenantCore

/// Owns the API client and the session lifecycle: launch checks, phone + code sign-in,
/// sign-out, forced update, language sync, and reacting to `APIEvent`s from any screen.
@Observable
@MainActor
final class AppModel {
    enum Phase: Equatable {
        case launching
        /// `noticeKey` is a Localizable key shown above the phone field (why the user is here).
        case signedOut(noticeKey: String?)
        case signedIn(Tenant)
        case updateRequired(appStoreURL: URL?)
    }

    private(set) var phase: Phase = .launching
    private(set) var environment: ServerEnvironment
    private(set) var client: APIClient
    private(set) var config: TenantConfig?
    private var eventsTask: Task<Void, Never>?

    init(environment: ServerEnvironment) {
        self.environment = environment
        self.client = Self.makeClient(for: environment)
    }

    var tenant: Tenant? {
        if case .signedIn(let tenant) = phase { return tenant }
        return nil
    }

    // MARK: Lifecycle

    func start() async {
        listenToEvents()
        // Version gate first: an unsupported build must not try to sign in.
        if let config = try? await client.config() {
            self.config = config
            if config.requiresUpdate(build: ServerEnvironment.clientBuild) {
                phase = .updateRequired(appStoreURL: config.appStoreURL)
                return
            }
        }
        guard await client.hasStoredSession else {
            phase = .signedOut(noticeKey: nil)
            return
        }
        do {
            let session = try await client.session()
            await didSignIn(session.tenant)
        } catch APIError.transport {
            // Offline at launch with a stored session: say so, the tokens stay for the next launch.
            phase = .signedOut(noticeKey: "error.offline")
        } catch let error as APIError {
            if case .updateRequired = error { return }
            phase = .signedOut(noticeKey: noticeKey(forEndedSession: error.code))
        } catch {
            phase = .signedOut(noticeKey: nil)
        }
    }

    // MARK: Sign-in

    func requestCode(phone: String) async throws -> RequestCodeResponse {
        try await client.requestCode(phone: phone)
    }

    func verifyCode(phone: String, code: String) async throws {
        let tenant = try await client.verifyCode(phone: phone, code: code)
        await didSignIn(tenant)
    }

    private func didSignIn(_ tenant: Tenant) async {
        phase = .signedIn(tenant)
        // The language chosen on this phone wins: tell the server once so its copy
        // (used for notifications) follows. A failure is silent; Profile can retry.
        guard let local = LanguageSetting.current, local != tenant.language else { return }
        if let updated = try? await client.updateLanguage(local), case .signedIn = phase {
            phase = .signedIn(updated)
        }
    }

    // MARK: Sign-out

    func signOut() async {
        await client.logout()
        phase = .signedOut(noticeKey: nil)
    }

    /// Revokes every session of this tenant (other phones and the web included).
    @discardableResult
    func signOutEverywhere() async throws -> Int {
        let count = try await client.logoutAll()
        phase = .signedOut(noticeKey: nil)
        return count
    }

    // MARK: Language

    /// Stores the choice locally (the UI switches at once) and, when signed in, PATCHes the tenant.
    func updateLanguage(_ language: AppLanguage) async throws {
        LanguageSetting.set(language)
        guard case .signedIn(let tenant) = phase, tenant.language != language else { return }
        let updated = try await client.updateLanguage(language)
        if case .signedIn = phase { phase = .signedIn(updated) }
    }

    // MARK: Server (dev / stage)

    /// Points the app at another server. Signs out of the current one.
    func switchServer(to url: URL?) async {
        guard environment.allowsServerOverride else { return }
        await client.logout()
        ServerEnvironment.setOverride(url)
        environment = .current
        client = Self.makeClient(for: environment)
        phase = .launching
        await start()
    }

    // MARK: Events

    private func listenToEvents() {
        eventsTask?.cancel()
        let events = client.events
        eventsTask = Task { [weak self] in
            for await event in events {
                await self?.handle(event)
            }
        }
    }

    private func handle(_ event: APIEvent) async {
        switch event {
        case .sessionEnded(let reason):
            if case .signedIn = phase { phase = .signedOut(noticeKey: noticeKey(forEndedSession: reason)) }
        case .updateRequired:
            phase = .updateRequired(appStoreURL: config?.appStoreURL)
        }
    }

    /// A tenant whose lease closed (or who was deactivated) is told why; anything else is "session ended".
    private func noticeKey(forEndedSession code: String?) -> String {
        code == ServerErrorCode.notATenant ? "auth.notice.notATenant" : "auth.notice.sessionEnded"
    }

    private static func makeClient(for environment: ServerEnvironment) -> APIClient {
        APIClient(
            baseURL: environment.baseURL,
            clientBuild: ServerEnvironment.clientBuild,
            tokenStore: KeychainTokenStore(account: environment.tokenAccount)
        )
    }
}
