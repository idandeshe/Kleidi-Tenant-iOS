import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
import TenantCore
@testable import TenantAPI

@Suite struct RentEndpointTests {
    let utc = TimeZone(identifier: "UTC")!

    @Test func rentUsesBearer() async throws {
        let transport = ScriptedTransport { _ in (200, json(rentJSON())) }
        let client = APIClient(baseURL: baseURL, clientBuild: 1, transport: transport, tokenStore: InMemoryTokenStore(storedTokens("a")))

        let rent = try await client.rent(leaseId: "l1")

        #expect(rent.months.count == 4)
        #expect(transport.requests.map { $0.url?.path } == ["/api/tenant/leases/l1/rent"])
        #expect(transport.requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "Bearer access-a" })
    }

    @Test func declareWireSendsTextFieldsBeforeTheProof() async throws {
        let transport = ScriptedTransport { _ in (201, json(declarationJSON())) }
        let client = APIClient(baseURL: baseURL, clientBuild: 1, transport: transport, tokenStore: InMemoryTokenStore(storedTokens("a")))
        let draft = WireDeclarationDraft(
            periods: ["2026-09", "2026-10"],
            declaredAmount: Decimal(string: "1612.5")!,
            transferDate: Date(timeIntervalSince1970: 1_790_985_600), // 2026-10-03T00:00:00Z
            reference: "  Rent Sep-Oct  ",
            proof: WireProofUpload(data: Data("JPEG".utf8), fileName: "Proof.jpg", mimeType: "image/jpeg"))

        let created = try await client.declareWire(leaseId: "l1", draft, boundary: "B")

        #expect(created.id == "w1")
        let request = try #require(transport.requests.first)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path == "/api/tenant/leases/l1/wire-declarations")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "multipart/form-data; boundary=B")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer access-a")
        let body = String(data: request.httpBody ?? Data(), encoding: .utf8) ?? ""
        // The server reads the text fields from the parts before the file: fields first, `proof` last.
        let fields = body.components(separatedBy: "--B\r\n").dropFirst().map { $0.components(separatedBy: "\r\n")[0] }
        #expect(fields.map { $0.replacingOccurrences(of: "Content-Disposition: form-data; name=", with: "") } == [
            "\"periods\"", "\"declaredAmount\"", "\"transferDate\"", "\"reference\"", "\"proof\"; filename=\"Proof.jpg\"",
        ])
        #expect(body.contains("name=\"periods\"\r\n\r\n[\"2026-09\",\"2026-10\"]\r\n"))
        #expect(body.contains("name=\"declaredAmount\"\r\n\r\n1612.5\r\n"))
        #expect(body.contains("name=\"reference\"\r\n\r\nRent Sep-Oct\r\n"))
        #expect(body.contains("filename=\"Proof.jpg\"\r\nContent-Type: image/jpeg\r\n\r\nJPEG\r\n--B--\r\n"))
        #expect(body.hasSuffix("--B--\r\n"))
    }

    @Test func formIsExactAndSkipsAnEmptyReference() {
        let draft = WireDeclarationDraft(
            periods: ["2026-10"],
            declaredAmount: 800,
            transferDate: Date(timeIntervalSince1970: 1_790_985_600), // 2026-10-03T00:00:00Z
            reference: "   ",
            proof: WireProofUpload(data: Data("PDF".utf8), fileName: "receipt.pdf", mimeType: "application/pdf"))

        let body = String(data: draft.form(boundary: "B", timeZone: utc).body, encoding: .utf8)

        #expect(body == "--B\r\nContent-Disposition: form-data; name=\"periods\"\r\n\r\n[\"2026-10\"]\r\n"
            + "--B\r\nContent-Disposition: form-data; name=\"declaredAmount\"\r\n\r\n800\r\n"
            + "--B\r\nContent-Disposition: form-data; name=\"transferDate\"\r\n\r\n2026-10-03\r\n"
            + "--B\r\nContent-Disposition: form-data; name=\"proof\"; filename=\"receipt.pdf\"\r\nContent-Type: application/pdf\r\n\r\nPDF\r\n"
            + "--B--\r\n")
    }

    @Test func conflictSurfacesWithStatusAndField() async {
        let transport = ScriptedTransport { _ in (409, json(["error": "October 2026 is already paid", "field": "periods"])) }
        let client = APIClient(baseURL: baseURL, clientBuild: 1, transport: transport, tokenStore: InMemoryTokenStore(storedTokens("a")))
        let draft = WireDeclarationDraft(
            periods: ["2026-10"], declaredAmount: 800, transferDate: Date(),
            proof: WireProofUpload(data: Data("x".utf8), fileName: "p.png", mimeType: "image/png"))

        await #expect(throws: APIError.http(status: 409, message: "October 2026 is already paid", code: nil, field: "periods")) {
            try await client.declareWire(leaseId: "l1", draft)
        }
    }

    @Test func proofComesBackWithItsTypeAndName() async throws {
        let transport = ScriptedTransport(responseHeaders: [
            "Content-Type": "application/pdf",
            "Content-Disposition": "inline; filename=\"Receipt%20Oct.pdf\"",
        ]) { _ in (200, Data("%PDF-1.4".utf8)) }
        let client = APIClient(baseURL: baseURL, clientBuild: 1, transport: transport, tokenStore: InMemoryTokenStore(storedTokens("a")))

        let proof = try await client.wireProof(declarationId: "w1")

        #expect(transport.requests.first?.url?.path == "/api/tenant/wire-declarations/w1/proof")
        #expect(proof.data == Data("%PDF-1.4".utf8))
        #expect(proof.mimeType == "application/pdf")
        #expect(proof.isPDF)
        #expect(!proof.isImage)
        #expect(proof.fileName == "Receipt Oct.pdf")
    }

    @Test func contentDispositionParsing() {
        #expect(APIClient.fileName(fromContentDisposition: "inline; filename=\"a%20b.jpg\"") == "a b.jpg")
        #expect(APIClient.fileName(fromContentDisposition: "attachment; filename=plain.png") == "plain.png")
        #expect(APIClient.fileName(fromContentDisposition: "inline") == nil)
        #expect(APIClient.fileName(fromContentDisposition: nil) == nil)
    }

    @Test func proofRulesMatchTheServerWhitelist() {
        #expect(WireProofRules.accepts(mimeType: "image/jpeg"))
        #expect(WireProofRules.accepts(mimeType: "Application/PDF"))
        #expect(!WireProofRules.accepts(mimeType: "image/heic"))
        #expect(WireProofRules.mimeType(forExtension: "JPG") == "image/jpeg")
        #expect(WireProofRules.mimeType(forExtension: "webp") == "image/webp")
        #expect(WireProofRules.mimeType(forExtension: "heic") == nil)
        #expect(WireProofRules.maxBytes == 15 * 1024 * 1024)
    }
}
