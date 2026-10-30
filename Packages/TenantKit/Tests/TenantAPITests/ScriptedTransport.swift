import Foundation
import Testing
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import TenantAPI

/// A fake server: routes each request to a handler and records what was sent.
final class ScriptedTransport: HTTPTransport, @unchecked Sendable {
    typealias Handler = @Sendable (URLRequest) async throws -> (Int, Data)

    private let lock = NSLock()
    private var _requests: [URLRequest] = []
    private let handler: Handler
    /// Headers every scripted response carries (e.g. `Content-Type` of a file download).
    let responseHeaders: [String: String]

    init(responseHeaders: [String: String] = [:], _ handler: @escaping Handler) {
        self.responseHeaders = responseHeaders
        self.handler = handler
    }

    var requests: [URLRequest] { lock.withLock { _requests } }

    func requests(to path: String) -> [URLRequest] {
        requests.filter { $0.url?.path == path }
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        lock.withLock { _requests.append(request) }
        let (status, data) = try await handler(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil,
                                       headerFields: responseHeaders.isEmpty ? nil : responseHeaders)!
        return (data, response)
    }
}

func json(_ object: Any) -> Data {
    try! JSONSerialization.data(withJSONObject: object)
}

func bodyJSON(_ request: URLRequest) -> [String: Any]? {
    guard let body = request.httpBody else { return nil }
    return try? JSONSerialization.jsonObject(with: body) as? [String: Any]
}

func tokensJSON(_ suffix: String, accessExpires: String = "2099-01-01T00:00:00.000Z") -> [String: Any] {
    [
        "accessToken": "access-\(suffix)",
        "accessTokenExpiresAt": accessExpires,
        "refreshToken": "refresh-\(suffix)",
        "refreshTokenExpiresAt": "2099-02-01T00:00:00.000Z",
    ]
}

func tenantJSON() -> [String: Any] {
    [
        "id": "t1",
        "firstName": "Maria",
        "lastName": "Papadopoulou",
        "fullName": "Maria Papadopoulou",
        "phone": "+306912345678",
        "email": NSNull(),
        "language": "el",
    ]
}

func leaseJSON() -> [String: Any] {
    [
        "id": "l1",
        "property": [
            "id": "p1", "street": "Ermou 12", "unitNumber": "3", "floor": "floor_2",
            "postalCode": "10563", "cityName": "Athens",
        ],
        "status": "active",
        "startDate": "2026-01-01T00:00:00.000Z",
        "endDate": "2027-12-31T00:00:00.000Z",
        "isPastEnd": false,
        "monthlyRent": 800,
        "upcomingRent": ["monthlyRent": 850, "effectiveFrom": "2027-01-01T00:00:00.000Z"],
        "currencyCode": "EUR",
        "depositAmount": 1600,
        "paymentDayOfMonth": 5,
        "paymentMethod": "bank_transfer",
        "noticePeriodMonths": 2,
        "noticeDeadline": "2027-10-31T00:00:00.000Z",
    ]
}

func rentMonthJSON(_ period: String, status: String, declaration: [String: Any]? = nil, canDeclare: Bool = false,
                   paidAt: String? = nil, confirmedByWire: Bool = false) -> [String: Any] {
    var month: [String: Any] = [
        "period": period,
        "dueDate": "\(period)-05T00:00:00.000Z",
        "expectedAmount": 800,
        "status": status,
        "paidAt": NSNull(),
        "confirmedByWire": confirmedByWire,
        "declaration": NSNull(),
        "canDeclare": canDeclare,
    ]
    if let paidAt { month["paidAt"] = paidAt }
    if let declaration { month["declaration"] = declaration }
    return month
}

func rentJSON() -> [String: Any] {
    [
        "leaseId": "l1",
        "currencyCode": "EUR",
        "monthlyRent": 800,
        "paymentDayOfMonth": 5,
        "months": [
            rentMonthJSON("2026-10", status: "due", canDeclare: true),
            rentMonthJSON("2026-09", status: "declared", declaration: [
                "id": "w2", "status": "pending", "declaredAmount": 800, "transferDate": "2026-09-03T00:00:00.000Z",
                "declaredAt": "2026-09-04T09:30:00.000Z", "rejectionNote": NSNull(), "confirmedAt": NSNull(),
            ]),
            rentMonthJSON("2026-08", status: "overdue", declaration: [
                "id": "w1", "status": "rejected", "declaredAmount": 800, "transferDate": "2026-08-04T00:00:00.000Z",
                "declaredAt": "2026-08-05T08:00:00.000Z", "rejectionNote": "Wrong IBAN", "confirmedAt": NSNull(),
            ], canDeclare: true),
            rentMonthJSON("2026-07", status: "paid", declaration: [
                "id": "w0", "status": "confirmed", "declaredAmount": 800, "transferDate": "2026-07-01T00:00:00.000Z",
                "declaredAt": "2026-07-01T12:00:00.000Z", "rejectionNote": NSNull(), "confirmedAt": "2026-07-02T00:00:00.000Z",
            ], paidAt: "2026-07-02T00:00:00.000Z", confirmedByWire: true),
        ],
    ]
}

func declarationJSON(_ id: String = "w1", status: String = "pending") -> [String: Any] {
    var declaration: [String: Any] = [
        "id": id,
        "leaseId": "l1",
        "periods": ["2026-09", "2026-10"],
        "status": status,
        "declaredAmount": 1600,
        "currencyCode": "EUR",
        "transferDate": "2026-10-03T00:00:00.000Z",
        "reference": "Rent Sep-Oct",
        "rejectionNote": NSNull(),
        "confirmedAt": NSNull(),
        "createdAt": "2026-10-03T10:15:00.000Z",
    ]
    if status == "rejected" { declaration["rejectionNote"] = "Amount does not match" }
    return declaration
}

let farFuture = Date(timeIntervalSince1970: 4_070_908_800) // 2099-01-01

func storedTokens(_ suffix: String, accessExpiresAt: Date = farFuture) -> SessionTokens {
    SessionTokens(
        accessToken: "access-\(suffix)", accessTokenExpiresAt: accessExpiresAt,
        refreshToken: "refresh-\(suffix)", refreshTokenExpiresAt: farFuture.addingTimeInterval(86_400))
}

let baseURL = URL(string: "https://kleidi.test")!
