import Foundation

/// Pure portfolio valuation — market value + day change from holdings, quotes,
/// and FX rates. Shared by every surface (Mac reimplemented this inline; now
/// both the Mac and the phone value the book the same way, and it's testable).
///
/// All prices are converted to the DISPLAY currency via `fxRates` (keyed by the
/// quote's native currency → multiplier into display). Holdings without a quote
/// contribute nothing to market value (honest — we don't guess a price).
public enum PortfolioValuation {

    /// FX multiplier from a currency into the display currency (1 if unknown).
    public static func fx(_ currency: String?, rates: [String: Double]) -> Double {
        rates[currency ?? "USD"] ?? 1
    }

    /// A holding's market value in the display currency (0 without a quote).
    public static func holdingValue(_ h: Holding, quotes: [String: Quote], fxRates: [String: Double]) -> Double {
        guard let q = quotes[h.symbol] else { return 0 }
        return q.price * fx(q.currency, rates: fxRates) * h.quantity
    }

    /// Total market value of all quoted holdings, in the display currency.
    public static func totalValue(_ p: Portfolio, quotes: [String: Quote], fxRates: [String: Double]) -> Double {
        p.holdings.reduce(0) { $0 + holdingValue($1, quotes: quotes, fxRates: fxRates) }
    }

    /// Value-weighted portfolio day change (%), across holdings we have quotes
    /// for. nil when nothing is quoted (so the assistant simply omits it).
    public static func dayChangePct(_ p: Portfolio, quotes: [String: Quote], fxRates: [String: Double]) -> Double? {
        var weighted = 0.0, base = 0.0
        for h in p.holdings {
            guard let q = quotes[h.symbol] else { continue }
            let val = q.price * fx(q.currency, rates: fxRates) * h.quantity
            weighted += val * q.dayChangePct
            base += val
        }
        return base > 0 ? weighted / base : nil
    }

    /// The top-N holdings by value, labelled with today's move — the same
    /// "AAPL +2.1%" lines the assistant grounds in. Symbols without a quote fall
    /// back to just the symbol (no invented number).
    public static func topHoldings(_ p: Portfolio, quotes: [String: Quote], fxRates: [String: Double], limit: Int = 4) -> [String] {
        p.holdings
            .sorted { holdingValue($0, quotes: quotes, fxRates: fxRates) > holdingValue($1, quotes: quotes, fxRates: fxRates) }
            .prefix(limit)
            .map { h in
                if let pct = quotes[h.symbol]?.dayChangePct {
                    return "\(h.symbol) \(String(format: "%+.1f%%", pct))"
                }
                return h.symbol
            }
    }
}
