import Foundation

/// When a position was opened, and how it has behaved since. The date comes
/// from portfolio.json's `acquired` when present; otherwise it is DETECTED
/// from up to 10y of daily closes — the most recent day the price crossed the
/// position's cost basis — and always labeled as an estimate, never fact.
public struct PositionTimeline {
    public let symbol: String
    public let acquired: Date
    /// true when the date was inferred from price history, not user-provided.
    public let estimated: Bool
    public let holdingDays: Int
    public let totalReturnPct: Double
    /// CAGR — only computed once the position is ≥30 days old (annualizing a
    /// week is noise, not analysis).
    public let annualizedPct: Double?
    /// Daily closes since acquisition, downsampled to ≤120 points for drawing.
    public let closesSince: [Double]
    /// S&P 500 total return over the same window, for an honest benchmark.
    public let benchmarkPct: Double?

    public var acquiredLabel: String {
        (estimated ? "~" : "") + isoDateString(acquired)
    }
    public var heldLabel: String { holdingPeriodLabel(days: holdingDays) }
}

public enum TimelineService {
    /// Build timelines for all holdings concurrently. `quotes` supplies live
    /// prices when available; otherwise the last close stands in.
    public static func timelines(for holdings: [Holding],
                                 quotes: [String: Quote]) async -> [String: PositionTimeline] {
        guard !holdings.isEmpty else { return [:] }
        async let benchTask = QuoteService.fetchHistory(symbol: "^GSPC")
        let histories = await withTaskGroup(of: (String, [QuoteService.HistoryPoint]).self) { group in
            for s in Set(holdings.map(\.symbol)) {
                group.addTask { (s, await QuoteService.fetchHistory(symbol: s)) }
            }
            var out: [String: [QuoteService.HistoryPoint]] = [:]
            for await (s, h) in group { out[s] = h }
            return out
        }
        let bench = await benchTask

        var result: [String: PositionTimeline] = [:]
        for h in holdings {
            guard let history = histories[h.symbol], history.count >= 2 else { continue }
            let price = quotes[h.symbol]?.price ?? history.last!.close
            if let t = timeline(for: h, history: history, price: price, benchmark: bench) {
                result[h.symbol] = t
            }
        }
        return result
    }

    static func timeline(for holding: Holding,
                         history: [QuoteService.HistoryPoint],
                         price: Double,
                         benchmark: [QuoteService.HistoryPoint]) -> PositionTimeline? {
        guard holding.costBasis > 0 else { return nil }
        let startIdx: Int
        let estimated: Bool
        if let d = holding.acquiredDate {
            startIdx = history.firstIndex { $0.date >= d } ?? history.count - 1
            estimated = false
        } else {
            startIdx = detectAcquisitionIndex(cost: holding.costBasis, history: history)
            estimated = true
        }
        let acquired = holding.acquiredDate ?? history[startIdx].date
        let days = max(0, Calendar.current.dateComponents([.day], from: acquired, to: Date()).day ?? 0)
        let totalPct = (price - holding.costBasis) / holding.costBasis * 100
        var annualized: Double? = nil
        if days >= 30, price > 0 {
            annualized = (pow(price / holding.costBasis, 365.25 / Double(days)) - 1) * 100
        }
        var since = history[startIdx...].map(\.close)
        if let last = since.indices.last { since[last] = price }
        if since.count > 120 {
            let stride = Double(since.count - 1) / 119.0
            since = (0..<120).map { since[Int((Double($0) * stride).rounded())] }
        }
        var benchPct: Double? = nil
        if let b0 = benchmark.first(where: { $0.date >= acquired })?.close,
           let bN = benchmark.last?.close, b0 > 0 {
            benchPct = (bN - b0) / b0 * 100
        }
        return PositionTimeline(symbol: holding.symbol, acquired: acquired,
                                estimated: estimated, holdingDays: days,
                                totalReturnPct: totalPct, annualizedPct: annualized,
                                closesSince: since, benchmarkPct: benchPct)
    }

    /// Most recent day the close crossed the cost basis — the best keyless
    /// guess at "when was this bought". Falls back to the close nearest the
    /// cost when the price never crossed it inside the fetched window.
    static func detectAcquisitionIndex(cost: Double, history: [QuoteService.HistoryPoint]) -> Int {
        var i = history.count - 1
        while i >= 1 {
            let a = history[i - 1].close - cost
            let b = history[i].close - cost
            if a == 0 { return i - 1 }
            if a * b <= 0 { return i }
            i -= 1
        }
        var best = 0
        var bestDist = Double.greatestFiniteMagnitude
        for (idx, p) in history.enumerated() {
            let d = abs(p.close - cost)
            if d < bestDist { bestDist = d; best = idx }
        }
        return best
    }
}
