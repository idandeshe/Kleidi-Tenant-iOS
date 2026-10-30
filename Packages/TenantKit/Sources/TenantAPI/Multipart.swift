// `multipart/form-data` body for the proof upload. Same builder as the staff app
// (kleidi-ios KleidiAPI/Multipart.swift): the server reads the text fields from the parts
// *before* the file, so add every field first and the file last.

import Foundation

public struct MultipartForm: Sendable {
    public let boundary: String
    private var data = Data()

    public init(boundary: String = "kleidi-\(UUID().uuidString)") {
        self.boundary = boundary
    }

    public var contentType: String { "multipart/form-data; boundary=\(boundary)" }

    public mutating func addField(_ name: String, _ value: String) {
        data.append("--\(boundary)\r\n")
        data.append("Content-Disposition: form-data; name=\"\(escape(name))\"\r\n\r\n")
        data.append(value)
        data.append("\r\n")
    }

    public mutating func addFile(_ name: String, fileName: String, mimeType: String, contents: Data) {
        data.append("--\(boundary)\r\n")
        data.append("Content-Disposition: form-data; name=\"\(escape(name))\"; filename=\"\(escape(fileName))\"\r\n")
        data.append("Content-Type: \(mimeType)\r\n\r\n")
        data.append(contents)
        data.append("\r\n")
    }

    /// The finished body (closing boundary appended).
    public var body: Data {
        var result = data
        result.append("--\(boundary)--\r\n")
        return result
    }

    private func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "\"", with: "%22").replacingOccurrences(of: "\r\n", with: " ")
    }
}

private extension Data {
    mutating func append(_ string: String) {
        append(Data(string.utf8))
    }
}
