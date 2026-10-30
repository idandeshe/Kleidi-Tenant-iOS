import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// The one thing APIClient needs from the network. Tests swap in a scripted fake.
public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

/// Production transport over a foreground, cookie-less URLSession (the tenant API never
/// sets cookies for a native client; the session lives in the Bearer token).
public struct URLSessionTransport: HTTPTransport {
    private let session: URLSession

    public init(session: URLSession = URLSession(configuration: .ephemeral)) {
        self.session = session
    }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        return (data, http)
    }
}
