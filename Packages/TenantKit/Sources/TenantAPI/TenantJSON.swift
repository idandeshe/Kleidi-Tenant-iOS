import Foundation

/// Decoder / encoder for the tenant API. Server dates are `Date#toISOString()`
/// strings (with milliseconds); `YYYY-MM-DD` is accepted too.
public enum TenantJSON {
    public static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            guard let date = parseDate(string) else {
                throw DecodingError.dataCorruptedError(
                    in: container, debugDescription: "Unrecognised date: \(string)")
            }
            return date
        }
        return decoder
    }

    public static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(date.formatted(withFractions))
        }
        return encoder
    }

    private static let withFractions = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    private static let withoutFractions = Date.ISO8601FormatStyle()
    private static let dateOnly = Date.ISO8601FormatStyle().year().month().day()

    public static func parseDate(_ string: String) -> Date? {
        if let d = try? withFractions.parse(string) { return d }
        if let d = try? withoutFractions.parse(string) { return d }
        if let d = try? dateOnly.parse(string) { return d }
        return nil
    }
}
