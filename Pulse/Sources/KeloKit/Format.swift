import Foundation

/// Display currency — set once at startup from config.json
/// (`displayCurrency`). All money the UI shows is converted into this.
public enum Money {
    public static var displayCode = "USD"
}

public func usd(_ v: Double) -> String {
    let f = NumberFormatter()
    f.numberStyle = .currency; f.currencyCode = Money.displayCode
    f.maximumFractionDigits = abs(v) >= 1000 ? 0 : 2
    return f.string(from: v as NSNumber) ?? "$\(v)"
}

public func num(_ v: Double) -> String {
    v == v.rounded() ? String(Int(v)) : String(format: "%.4g", v)
}

public func pct(_ v: Double) -> String { String(format: "%+.2f%%", v) }

/// Parse "YYYY-MM-DD" in US market time — same convention everywhere.
public func parseISODate(_ s: String) -> Date? {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd"
    f.timeZone = TimeZone(identifier: "America/New_York")
    return f.date(from: s)
}

public func isoDateString(_ d: Date) -> String {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd"
    f.timeZone = TimeZone(identifier: "America/New_York")
    return f.string(from: d)
}

/// "3d" / "5mo" / "2.4y" — compact holding-period label.
public func holdingPeriodLabel(days: Int) -> String {
    if days < 60 { return "\(days)d" }
    if days < 365 { return "\(Int((Double(days) / 30.44).rounded()))mo" }
    return String(format: "%.1fy", Double(days) / 365.25)
}
