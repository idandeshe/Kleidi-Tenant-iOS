// `/api/tenant/me` and `/api/tenant/leases` (server/routes/tenant/me, server/routes/tenant/leases).

import Foundation
import TenantCore

extension APIClient {
    public func me() async throws -> Tenant {
        try await send(APIRequest(.get, "/tenant/me"))
    }

    /// `PATCH /tenant/me { language }` — keeps the server's copy of the tenant's language
    /// (used for notifications) in step with the choice made in the app.
    public func updateLanguage(_ language: AppLanguage) async throws -> Tenant {
        let body = try TenantJSON.encoder().encode(UpdateLanguageRequest(language: language))
        return try await send(APIRequest(.patch, "/tenant/me", body: body))
    }

    /// The tenant's own leases, newest first.
    public func leases() async throws -> [TenantLease] {
        let response: TenantLeasesResponse = try await send(APIRequest(.get, "/tenant/leases"))
        return response.data
    }

    /// One own lease; anyone else's is a plain 404.
    public func lease(id: String) async throws -> TenantLease {
        try await send(APIRequest(.get, "/tenant/leases/\(id)"))
    }
}
