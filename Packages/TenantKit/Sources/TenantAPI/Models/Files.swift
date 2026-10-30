// Files that travel with the tenant API: the proof of a bank transfer and the photos of a
// reported issue go up as multipart parts; both come back down as raw bytes with their
// `Content-Type` (the URL alone is not openable — the tenant API has no cookies).

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// A file as it goes on the wire — already JPEG when it started as a HEIC / camera photo.
public struct UploadFile: Sendable, Hashable {
    public let data: Data
    public let fileName: String
    public let mimeType: String

    public init(data: Data, fileName: String, mimeType: String) {
        self.data = data
        self.fileName = fileName
        self.mimeType = mimeType
    }
}

/// A file the server sent back — the bytes with the type they were uploaded as.
public struct DownloadedFile: Sendable, Equatable {
    public let data: Data
    /// `image/jpeg`, `image/png`, `image/webp` or `application/pdf`.
    public let mimeType: String
    public let fileName: String?

    public init(data: Data, mimeType: String, fileName: String?) {
        self.data = data
        self.mimeType = mimeType
        self.fileName = fileName
    }

    public var isPDF: Bool { mimeType.lowercased().hasPrefix("application/pdf") }
    public var isImage: Bool { mimeType.lowercased().hasPrefix("image/") }
}

extension APIClient {
    /// `GET` of a file: the bytes, the `Content-Type` (parameters stripped) and the name from
    /// `Content-Disposition`, when the server sends one.
    func downloadFile(_ path: String) async throws -> DownloadedFile {
        let (data, response) = try await sendData(APIRequest(.get, path))
        let contentType = response.value(forHTTPHeaderField: "Content-Type") ?? "application/octet-stream"
        let mimeType = contentType.split(separator: ";").first.map { $0.trimmingCharacters(in: .whitespaces) } ?? contentType
        return DownloadedFile(
            data: data,
            mimeType: mimeType,
            fileName: Self.fileName(fromContentDisposition: response.value(forHTTPHeaderField: "Content-Disposition")))
    }

    /// `inline; filename="Receipt%20Oct.pdf"` → "Receipt Oct.pdf".
    static func fileName(fromContentDisposition header: String?) -> String? {
        guard let header else { return nil }
        for part in header.split(separator: ";") {
            let piece = part.trimmingCharacters(in: .whitespaces)
            guard piece.lowercased().hasPrefix("filename=") else { continue }
            var value = String(piece.dropFirst("filename=".count))
            if value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 {
                value = String(value.dropFirst().dropLast())
            }
            let decoded = value.removingPercentEncoding ?? value
            return decoded.isEmpty ? nil : decoded
        }
        return nil
    }
}
