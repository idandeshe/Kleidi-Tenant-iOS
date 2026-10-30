// Mirrors `TenantSessionTenant` in server/types/tenantAuth.types.ts.

import Foundation
import TenantCore

/// The signed-in tenant, as the tenant app sees itself.
public struct Tenant: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let firstName: String
    public let lastName: String
    public let fullName: String
    /// E.164, e.g. `+306912345678`.
    public let phone: String
    public let email: String?
    public let language: AppLanguage

    public init(id: String, firstName: String, lastName: String, fullName: String, phone: String, email: String?, language: AppLanguage) {
        self.id = id
        self.firstName = firstName
        self.lastName = lastName
        self.fullName = fullName
        self.phone = phone
        self.email = email
        self.language = language
    }
}

struct UpdateLanguageRequest: Encodable {
    let language: AppLanguage
}
