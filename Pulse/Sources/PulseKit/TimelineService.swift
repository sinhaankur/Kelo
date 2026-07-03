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

/// The whole portfolio's market value reconstructed day by day from each
/// position's invested date — how the account actually grew, not just where
/// it stands. Options are excluded (no historical marks) and labeled so.
public struct PortfolioHistory {
    public let dates: [Date]
    /// Holdings market value per day (only positions already opened count).
    public let values: [Double]
    /// Cost basis deployed by that day — the flat line the value must beat.
    public let costs: [Double]
    /// Coverage: positions with usable history vs total. Real-world CSV
    /// imports include symbols Yahoo can't chart — the series is built from
    /// what IS known and labeled with this coverage, never silently partial.
    public let covered: Int
    public let total: Int
}

public struct PortfolioAnalysis {
    public let timelines: [String: PositionTimeline]
    public let history: PortfolioHistory?
    /// The fetched S&P 500 daily series — reused by callers for windowed
    /// comparisons (paper-trade reviews) without a second fetch.
    public let benchmark: [QuoteService.HistoryPoint]
}

public enum TimelineService {
    /// Build per-position timelines AND the reconstructed portfolio growth
    /// series in one pass (histories are fetched once). `quotes` supplies
    /// live prices when available; otherwise the last close stands in.
    public static func analyze(holdings: [Holding],
                               quotes: [String: Quote],
                               fxRates: [String: Double] = [:]) async -> PortfolioAnalysis {
        guard !holdings.isEmpty else {
            return PortfolioAnalysis(timelines: [:], history: nil, benchmark: [])
        }
        async let benchTask = QuoteService.fetchHistory(symbol: "^GSPC")
        // Bounded concurrency — hundreds of 10-year history fetches at once
        // would be rate-limited into silent gaps.
        let unique = Array(Set(holdings.map(\.symbol)))
        let histories = await withTaskGroup(of: (String, [QuoteService.HistoryPoint]).self) { group in
            var it = unique.makeIterator()
            for _ in 0..<min(8, unique.count) {
                if let s = it.next() { group.addTask { (s, await QuoteService.fetchHistory(symbol: s)) } }
            }
            var out: [String: [QuoteService.HistoryPoint]] = [:]
            for await (s, h) in group {
                out[s] = h
                if let s = it.next() { group.addTask { (s, await QuoteService.fetchHistory(symbol: s)) } }
            }
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
        let growth = portfolioHistory(holdings: holdings, timelines: result,
                                      histories: histories, quotes: quotes, fxRates: fxRates)
        return PortfolioAnalysis(timelines: result, history: growth, benchmark: bench)
    }

    public static func timelines(for holdings: [Holding],
                                 quotes: [String: Quote]) async -> [String: PositionTimeline] {
        await analyze(holdings: holdings, quotes: quotes).timelines
    }

    /// Day-by-day account value: for every trading day since the earliest
    /// invested date, sum qty × last-known close of each position that was
    /// already open. Days are normalized to UTC so exchange bars and 24/7
    /// crypto bars land on the same axis.
    static func portfolioHistory(holdings: [Holding],
                                 timelines: [String: PositionTimeline],
                                 histories: [String: [QuoteService.HistoryPoint]],
                                 quotes: [String: Quote],
                                 fxRates: [String: Double] = [:]) -> PortfolioHistory? {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!

        struct Series { let start: Date; let days: [Date]; let closes: [Double]; let qty: Double; let cost: Double; let fx: Double }
        var series: [Series] = []
        var daySet = Set<Date>()
        for h in holdings {
            // A live quote is required: a symbol with old history but no
            // current quote is likely delisted — valuing it at a years-old
            // close would inflate the whole curve.
            guard quotes[h.symbol] != nil,
                  let t = timelines[h.symbol], let hist = histories[h.symbol], !hist.isEmpty else { continue }
            let start = cal.startOfDay(for: t.acquired)
            var days: [Date] = []
            var closes: [Double] = []
            for p in hist {
                let d = cal.startOfDay(for: p.date)
                if d < start { continue }
                if days.last == d { closes[closes.count - 1] = p.close } else { days.append(d); closes.append(p.close) }
            }
            guard !days.isEmpty else { continue }
            daySet.formUnion(days)
            // Closes and cost share the listing's currency — one multiplier
            // converts both into the display currency.
            let fx = fxRates[quotes[h.symbol]?.currency ?? "USD"] ?? 1
            series.append(Series(start: start, days: days, closes: closes,
                                 qty: h.quantity, cost: h.costBasis * h.quantity, fx: fx))
        }
        guard !series.isEmpty, !daySet.isEmpty else { return nil }
        let coveredHoldings = holdings.filter {
            quotes[$0.symbol] != nil && timelines[$0.symbol] != nil
                && !(histories[$0.symbol] ?? []).isEmpty
        }

        let grid = daySet.sorted()
        var values = [Double](repeating: 0, count: grid.count)
        var costs = [Double](repeating: 0, count: grid.count)
        for s in series {
            var ptr = 0
            var lastClose: Double? = nil
            for (gi, day) in grid.enumerated() {
                while ptr < s.days.count, s.days[ptr] <= day {
                    lastClose = s.closes[ptr]; ptr += 1
                }
                guard day >= s.start, let c = lastClose else { continue }
                values[gi] += s.qty * c * s.fx
                costs[gi] += s.cost * s.fx
            }
        }
        // Live tail: today's holdings value from real-time quotes when known.
        if let last = values.indices.last {
            let live = zip(series, coveredHoldings).reduce(0.0) { acc, pair in
                acc + pair.0.qty * (quotes[pair.1.symbol]?.price ?? pair.0.closes.last ?? 0) * pair.0.fx
            }
            if live > 0 { values[last] = live }
        }
        var dates = grid
        if values.count > 150 {
            let stride = Double(values.count - 1) / 149.0
            let idx = (0..<150).map { Int((Double($0) * stride).rounded()) }
            dates = idx.map { grid[$0] }
            values = idx.map { values[$0] }
            costs = idx.map { costs[$0] }
        }
        return PortfolioHistory(dates: dates, values: values, costs: costs,
                                covered: series.count, total: holdings.count)
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
