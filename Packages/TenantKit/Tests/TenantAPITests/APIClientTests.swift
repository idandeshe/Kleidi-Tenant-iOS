import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
import TenantCore
@testable import TenantAPI

@Suite struct APIClientTests {
    @Test func requestCodeSendsTenantHeadersWithoutAuth() async throws {
        let transport = ScriptedTransport { _ in (200, json(["message": "Code sent", "expiresInSeconds": 300])) }
        let client = APIClient(baseURL: baseURL, clientBuild: 42, transport: transport, tokenStore: InMemoryTokenStore())

        let response = try await client.requestCode(phone: "+306912345678")

        #expect(response.expiresInSeconds == 300)
        let request = try #require(transport.requests.first)
        #expect(request.url?.absoluteString == "https://kleidi.test/api/tenant/auth/request-code")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "x-client") == "tenant-ios")
        #expect(request.value(forHTTPHeaderField: "x-client-build") == "42")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(bodyJSON(request)?["phone"] as? String == "+306912345678")
    }

    @Test func verifyCodeStoresTokensFromBody() async throws {
        let transport = ScriptedTransport { _ in
            (200, json(["tenant": tenantJSON(), "message": "Signed in", "tokens": tokensJSON("1")]))
        }
        let store = InMemoryTokenStore()
        let client = APIClient(baseURL: baseURL, clientBuild: 1, transport: transport, tokenStore: store)

        let tenant = try await client.verifyCode(phone: "+306912345678", code: "123456")

        #expect(tenant.fullName == "Maria Papadopoulou")
        #expect(tenant.language == .el)
        #expect(tenant.email == nil)
        #expect(bodyJSON(transport.requests[0])?["code"] as? String == "123456")
        #expect(try store.load()?.refreshToken == "refresh-1")
        #expect(await client.hasStoredSession)
    }

    @Test func wrongCodeIsAnErrorWithTheServerCode() async throws {
        let transport = ScriptedTransport { _ in (401, json(["error": "Invalid code", "code": "INVALID_CODE"])) }
        let client = APIClient(baseURL: baseURL, clientBuild: 1, transport: transport, tokenStore: InMemoryTokenStore())

        await #expect(throws: APIError.unauthorized(code: "INVALID_CODE", message: "Invalid code")) {
            try await client.verifyCode(phone: "+306912345678", code: "000000")
        }
        #expect(await !client.hasStoredSession)
    }

    @Test func notATenantIsA403WithCode() async throws {
        let transport = ScriptedTransport { _ in (403, json(["error": "Not a tenant", "code": "NOT_A_TENANT"])) }
        let client = APIClient(baseURL: baseURL, clientBuild: 1, transport: transport, tokenStore: InMemoryTokenStore())
        do {
            _ = try await client.verifyCode(phone: "+306912345678", code: "123456")
            Issue.record("expected an error")
        } catch let error as APIError {
            #expect(error.status == 403)
            #expect(error.code == ServerErrorCode.notATenant)
        }
    }

    @Test func authenticatedRequestUsesBearer() async throws {
        let transport = ScriptedTransport { _ in (200, json(["data": [leaseJSON()]])) }
        let client = APIClient(baseURL: baseURL, clientBuild: 1, transport: transport, tokenStore: InMemoryTokenStore(storedTokens("a")))

        let leases = try await client.leases()

        #expect(leases.count == 1)
        let request = try #require(transport.requests.first)
        #expect(request.url?.absoluteString == "https://kleidi.test/api/tenant/leases")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer access-a")
    }

    @Test func notSignedInWithoutStoredTokens() async {
        let transport = ScriptedTransport { _ in (200, Data()) }
        let client = APIClient(baseURL: baseURL, clientBuild: 1, transport: transport, tokenStore: InMemoryTokenStore())
        await #expect(throws: APIError.notSignedIn) { try await client.me() }
        #expect(transport.requests.isEmpty)
    }

    @Test func refreshesProactivelyBeforeExpiry() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let transport = ScriptedTransport { request in
            if request.url?.path == "/api/tenant/auth/refresh" {
                return (200, json(["message": "ok", "tokens": tokensJSON("b")]))
            }
            return (200, json(tenantJSON()))
        }
        let store = InMemoryTokenStore(storedTokens("a", accessExpiresAt: now.addingTimeInterval(30)))
        let client = APIClient(baseURL: baseURL, clientBuild: 1, transport: transport, tokenStore: store, now: { now })

        _ = try await client.me()

        let refresh = try #require(transport.requests(to: "/api/tenant/auth/refresh").first)
        #expect(bodyJSON(refresh)?["refreshToken"] as? String == "refresh-a")
        #expect(refresh.value(forHTTPHeaderField: "Authorization") == nil)
        let call = try #require(transport.requests(to: "/api/tenant/me").first)
        #expect(call.value(forHTTPHeaderField: "Authorization") == "Bearer access-b")
        #expect(try store.load()?.refreshToken == "refresh-b")
    }

    @Test func concurrent401sShareOneRefresh() async throws {
        let transport = ScriptedTransport { request in
            if request.url?.path == "/api/tenant/auth/refresh" {
                try await Task.sleep(for: .milliseconds(50))
                return (200, json(["message": "ok", "tokens": tokensJSON("b")]))
            }
            if request.value(forHTTPHeaderField: "Authorization") == "Bearer access-a" {
                return (401, json(["error": "Invalid or expired token"]))
            }
            return (200, json(leaseJSON()))
        }
        let client = APIClient(baseURL: baseURL, clientBuild: 1, transport: transport, tokenStore: InMemoryTokenStore(storedTokens("a")))

        try await withThrowingTaskGroup(of: TenantLease.self) { group in
            for _ in 0..<5 { group.addTask { try await client.lease(id: "l1") } }
            for try await lease in group { #expect(lease.id == "l1") }
        }

        #expect(transport.requests(to: "/api/tenant/auth/refresh").count == 1)
    }

    @Test func rejectedRefreshEndsSession() async throws {
        let transport = ScriptedTransport { request in
            if request.url?.path == "/api/tenant/auth/refresh" {
                return (401, json(["error": "Token revoked", "code": "TOKEN_REVOKED"]))
            }
            return (401, json(["error": "Invalid or expired token"]))
        }
        let store = InMemoryTokenStore(storedTokens("a"))
        let client = APIClient(baseURL: baseURL, clientBuild: 1, transport: transport, tokenStore: store)
        var events = client.events.makeAsyncIterator()

        await #expect(throws: APIError.unauthorized(code: "TOKEN_REVOKED", message: "Token revoked")) {
            try await client.me()
        }

        #expect(await events.next() == .sessionEnded(reason: "TOKEN_REVOKED"))
        #expect(try store.load() == nil)
        await #expect(throws: APIError.notSignedIn) { try await client.me() }
    }

    @Test func serverErrorDuringRefreshKeepsSession() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let transport = ScriptedTransport { _ in (503, json(["error": "Service unavailable"])) }
        let store = InMemoryTokenStore(storedTokens("a", accessExpiresAt: now))
        let client = APIClient(baseURL: baseURL, clientBuild: 1, transport: transport, tokenStore: store, now: { now })

        await #expect(throws: APIError.http(status: 503, message: "Service unavailable", code: nil, field: nil)) {
            try await client.me()
        }
        #expect(try store.load() != nil)
    }

    @Test func updateRequiredIsAnEventAndAnError() async throws {
        let transport = ScriptedTransport { _ in
            (426, json(["error": "App update required", "code": "APP_UPDATE_REQUIRED", "minSupportedBuild": 7]))
        }
        let client = APIClient(baseURL: baseURL, clientBuild: 3, transport: transport, tokenStore: InMemoryTokenStore(storedTokens("a")))
        var events = client.events.makeAsyncIterator()

        await #expect(throws: APIError.updateRequired(minSupportedBuild: 7)) { try await client.leases() }
        #expect(await events.next() == .updateRequired(minSupportedBuild: 7))
    }

    @Test func smsNotConfiguredIsA503() async throws {
        let transport = ScriptedTransport { _ in (503, json(["error": "SMS not configured", "code": "SMS_NOT_CONFIGURED"])) }
        let client = APIClient(baseURL: baseURL, clientBuild: 1, transport: transport, tokenStore: InMemoryTokenStore())
        await #expect(throws: APIError.http(status: 503, message: "SMS not configured", code: "SMS_NOT_CONFIGURED", field: nil)) {
            try await client.requestCode(phone: "+306912345678")
        }
    }

    @Test func logoutRevokesRefreshTokenAndClearsLocally() async throws {
        let transport = ScriptedTransport { _ in (200, json(["message": "Logged out"])) }
        let store = InMemoryTokenStore(storedTokens("a"))
        let client = APIClient(baseURL: baseURL, clientBuild: 1, transport: transport, tokenStore: store)

        await client.logout()

        let request = try #require(transport.requests(to: "/api/tenant/auth/logout").first)
        #expect(bodyJSON(request)?["refreshToken"] as? String == "refresh-a")
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(try store.load() == nil)
        #expect(await !client.hasStoredSession)
    }

    @Test func logoutClearsLocallyEvenWhenOffline() async throws {
        let transport = ScriptedTransport { _ in throw URLError(.notConnectedToInternet) }
        let store = InMemoryTokenStore(storedTokens("a"))
        let client = APIClient(baseURL: baseURL, clientBuild: 1, transport: transport, tokenStore: store)

        await client.logout()
        #expect(try store.load() == nil)
    }

    @Test func updateLanguagePatchesMe() async throws {
        var patched = tenantJSON()
        patched["language"] = "en"
        let patchedData = json(patched)
        let transport = ScriptedTransport { _ in (200, patchedData) }
        let client = APIClient(baseURL: baseURL, clientBuild: 1, transport: transport, tokenStore: InMemoryTokenStore(storedTokens("a")))

        let tenant = try await client.updateLanguage(.en)

        #expect(tenant.language == .en)
        let request = try #require(transport.requests.first)
        #expect(request.httpMethod == "PATCH")
        #expect(request.url?.path == "/api/tenant/me")
        #expect(bodyJSON(request)?["language"] as? String == "en")
    }
}
