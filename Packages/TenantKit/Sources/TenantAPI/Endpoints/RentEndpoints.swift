// `/api/tenant/leases/:id/rent`, `POST /api/tenant/leases/:id/wire-declarations` and
// `/api/tenant/wire-declarations/:id/proof` (server/routes/tenant/leases/_id/{rent,wire-declarations},
// server/routes/tenant/wire-declarations/_id/proof). The months carry their latest declaration,
// so the app never lists `GET …/wire-declarations`.

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import TenantCore

extension APIClient {
    /// The lease's rent months, newest first; anyone else's lease is a plain 404.
    public func rent(leaseId: String) async throws -> TenantRent {
        try await send(APIRequest(.get, "/tenant/leases/\(leaseId)/rent"))
    }

    /// "I paid by bank transfer". 400 `{ error, field }`, 404 lease, 409 a month already paid /
    /// declared, 413 proof too large, 415 unsupported type — all surface as `APIError.http`
    /// with that status (and `field`). Rate-limited to 5 per 10 minutes (429).
    public func declareWire(leaseId: String, _ draft: WireDeclarationDraft,
                            boundary: String = "kleidi-\(UUID().uuidString)") async throws -> TenantWireDeclaration {
        let form = draft.form(boundary: boundary)
        return try await send(APIRequest(
            .post, "/tenant/leases/\(leaseId)/wire-declarations", body: form.body, contentType: form.contentType))
    }

    /// The proof the tenant uploaded with a declaration ("View proof").
    public func wireProof(declarationId: String) async throws -> WireProofFile {
        try await downloadFile("/tenant/wire-declarations/\(declarationId)/proof")
    }
}
