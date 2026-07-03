import Foundation

/// The income truth table — what each payer actually sent (TTM), whether the
/// payout itself is growing or decaying, and the price damage next to it.
/// This is where "the dividend covers the losses" gets tested with numbers:
/// a stable payout on a stable price is income; a collapsing payout on a
/// collapsing price is your own capital coming back on a schedule.
public struct IncomePosition {
    public let symbol: String
    /// TTM distributions on the CURRENT share count, display currency.
    public let ttmIncome: Double
    public var monthlyEstimate: Double { ttmIncome / 12 }
    public let valueNow: Double
    /// Price-only P/L since buying, display currency.
    public let pricePL: Double
    /// Per-share payout: average of the last 3 payments vs the 3 before —
    /// the direction the income itself is heading.
    public let payoutTrendPct: Double?

    /// Falling more than 10% per period = a decaying annuity, not income.
    public var decaying: Bool { (payoutTrendPct ?? 0) <= -10 }
}

public struct IncomeReport {
    public let positions: [IncomePosition]
    public var totalMonthly: Double { positions.reduce(0) { $0 + $1.monthlyEstimate } }
    public var decayingMonthly: Double {
        positions.filter(\.decaying).reduce(0) { $0 + $1.monthlyEstimate }
    }
}

public enum IncomeService {
    /// Pure payout math from raw dividend events — fully testable.
    static func payoutStats(events: [(date: Date, amount: Double)],
                            now: Date = Date()) -> (ttmPerShare: Double, trendPct: Double?) {
        let ttm = events.filter { $0.date >= now.addingTimeInterval(-365 * 86_400) }
            .reduce(0.0) { $0 + $1.amount }
        var trend: Double? = nil
        let amounts = events.map(\.amount)
        if amounts.count >= 6 {
            let recent = amounts.suffix(3).reduce(0, +) / 3
            let prior = amounts.dropLast(3).suffix(3).reduce(0, +) / 3
            if prior > 0 { trend = (recent / prior - 1) * 100 }
        }
        return (ttm, trend)
    }

    /// Income report for the biggest positions (income concentrates there;
    /// checking all 400+ would hammer the endpoint for nothing).
    public static func report(holdings: [Holding],
                              quotes: [String: Quote],
                              fxRates: [String: Double],
                              topN: Int = 30) async -> IncomeReport {
        func fx(_ currency: String?) -> Double { fxRates[currency ?? "USD"] ?? 1 }
        func displayValue(_ h: Holding) -> Double {
            guard let q = quotes[h.symbol] else { return 0 }
            return q.price * h.quantity * fx(q.currency)
        }
        let top = holdings.sorted { displayValue($0) > displayValue($1) }.prefix(topN)

        let events = await withTaskGroup(of: (String, [(date: Date, amount: Double)]).self) { group in
            var it = top.makeIterator()
            for _ in 0..<min(6, top.count) {
                if let h = it.next() {
                    group.addTask { (h.symbol, await QuoteService.dividendEvents(symbol: h.symbol)) }
                }
            }
            var out: [String: [(date: Date, amount: Double)]] = [:]
            for await (s, e) in group {
                out[s] = e
                if let h = it.next() {
                    group.addTask { (h.symbol, await QuoteService.dividendEvents(symbol: h.symbol)) }
                }
            }
            return out
        }

        var positions: [IncomePosition] = []
        for h in top {
            guard let q = quotes[h.symbol], let e = events[h.symbol], !e.isEmpty else { continue }
            let stats = payoutStats(events: e)
            guard stats.ttmPerShare > 0 else { continue }
            let m = fx(q.currency)
            positions.append(IncomePosition(
                symbol: h.symbol,
                ttmIncome: stats.ttmPerShare * h.quantity * m,
                valueNow: q.price * h.quantity * m,
                pricePL: (q.price * m - h.costBasis * fx(h.currency)) * h.quantity,
                payoutTrendPct: stats.trendPct))
        }
        positions.sort { $0.ttmIncome > $1.ttmIncome }
        return IncomeReport(positions: positions)
    }
}
