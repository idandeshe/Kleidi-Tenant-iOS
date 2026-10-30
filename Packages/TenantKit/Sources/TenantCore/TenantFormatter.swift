// Display formatting shared by every screen: the web client's fixed `DD/MM/YYYY`, money as
// in the approved mock-up (`€ 800`), month names in the chosen language.

import Foundation

public enum TenantFormatter {
    // MARK: Dates

    /// `DD/MM/YYYY` in the viewer's time zone, whatever the device locale.
    public static func date(_ value: Date?, timeZone: TimeZone = .current) -> String {
        guard let value else { return "" }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let c = calendar.dateComponents([.year, .month, .day], from: value)
        return "\(pad(c.day))/\(pad(c.month))/\(c.year ?? 0)"
    }

    /// "October 2026" / "Οκτωβρίου 2026" (genitive, as in "Ενοίκιο Οκτωβρίου 2026").
    public static func monthYear(_ value: Date, language: AppLanguage, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = language.locale
        formatter.timeZone = timeZone
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: value)
    }

    /// A rent month `YYYY-MM` as a standalone label: "October 2026" / "Οκτώβριος 2026"
    /// (nominative, the web `formatPeriod`). Anything that is not `YYYY-MM` is shown as is.
    public static func period(_ period: String, language: AppLanguage) -> String {
        guard let date = periodDate(period) else { return period }
        let formatter = DateFormatter()
        formatter.locale = language.locale
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "LLLL yyyy"
        return formatter.string(from: date)
    }

    /// `2026-10` → the first of that month, UTC midnight; nil when malformed.
    public static func periodDate(_ period: String) -> Date? {
        let parts = period.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 2, parts[0].count == 4, parts[1].count == 2,
              let year = Int(parts[0]), let month = Int(parts[1]), (1...12).contains(month) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.date(from: DateComponents(year: year, month: month, day: 1))
    }

    /// `YYYY-MM-DD` of the calendar day in the viewer's time zone — what the server expects
    /// for a transfer date (the web `todayInputValue()`).
    public static func isoDate(_ value: Date, timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let c = calendar.dateComponents([.year, .month, .day], from: value)
        return "\(c.year ?? 0)-\(pad(c.month))-\(pad(c.day))"
    }

    /// "812 KB" / "1.4 MB" for a picked proof file.
    public static func fileSize(_ bytes: Int, language: AppLanguage) -> String {
        if bytes >= 1_000_000 {
            let mb = (Double(bytes) / 1_000_000).formatted(.number.precision(.fractionLength(1)).locale(language.locale))
            return "\(mb) MB"
        }
        return "\(max(1, bytes / 1_000)) KB"
    }

    // MARK: Money

    /// `800` + `EUR` → "€ 800"; `812.5` → "€ 812,50" in Greek, "€ 812.50" in English.
    /// Without a currency the bare number is shown.
    public static func money(_ amount: Double?, currencyCode: String?, language: AppLanguage) -> String {
        guard let amount else { return "" }
        let fractions: ClosedRange<Int> = amount.rounded() == amount ? 0...0 : 2...2
        let number = amount.formatted(.number.precision(.fractionLength(fractions)).locale(language.locale))
        guard let currencyCode, !currencyCode.isEmpty else { return number }
        return "\(symbol(for: currencyCode)) \(number)"
    }

    static func symbol(for currencyCode: String) -> String {
        switch currencyCode.uppercased() {
        case "EUR": return "€"
        case "GBP": return "£"
        case "USD": return "$"
        default: return currencyCode.uppercased()
        }
    }

    // MARK: Numbers

    /// English ordinal ("5th"); Greek shows the plain number ("5", read "τις 5").
    public static func ordinal(_ n: Int, language: AppLanguage) -> String {
        switch language {
        case .el:
            return "\(n)"
        case .en:
            let tens = n % 100
            if (11...13).contains(tens) { return "\(n)th" }
            switch n % 10 {
            case 1: return "\(n)st"
            case 2: return "\(n)nd"
            case 3: return "\(n)rd"
            default: return "\(n)th"
            }
        }
    }

    private static func pad(_ n: Int?) -> String {
        let n = n ?? 0
        return n < 10 ? "0\(n)" : "\(n)"
    }
}
