import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Fetches quotes from Yahoo Finance's chart endpoint — keyless, works for
/// equities and crypto (e.g. "BTC-USD"). Quotes may be delayed; personal use.
public enum QuoteService {
    struct ChartResponse: Decodable {
        struct Chart: Decodable { let result: [Result]? }
        struct Result: Decodable {
            let meta: Meta
            let timestamp: [Int]?
            let indicators: Indicators?
            let events: Events?
        }
        struct Indicators: Decodable { let quote: [QuoteBlock]? }
        struct QuoteBlock: Decodable { let close: [Double?]? }
        struct Events: Decodable { let dividends: [String: Dividend]? }
        struct Dividend: Decodable { let amount: Double? }
        struct Meta: Decodable {
            let symbol: String
            let currency: String?
            let regularMarketPrice: Double?
            let chartPreviousClose: Double?
            let previousClose: Double?
        }
        let chart: Chart
    }

    private static func chartRequest(symbol: String, range: String,
                                     interval: String = "1d", events: Bool = false) -> URLRequest {
        var comps = URLComponents(string: "https://query1.finance.yahoo.com/v8/finance/chart/\(symbol)")!
        var items = [
            URLQueryItem(name: "interval", value: interval),
            URLQueryItem(name: "range", value: range),
        ]
        if events { items.append(URLQueryItem(name: "events", value: "div")) }
        comps.queryItems = items
        var req = URLRequest(url: comps.url!)
        req.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 15
        return req
    }

    // MARK: - Dividends

    /// Trailing-12-month dividend yield from REAL paid distributions (Yahoo
    /// dividend events over 1y ÷ current price) — works for any listing,
    /// including .TO ETFs. nil when nothing was paid.
    public static func trailingDividendYieldPct(symbol: String) async -> Double? {
        let req = chartRequest(symbol: symbol, range: "1y", interval: "1mo", events: true)
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let parsed = try? JSONDecoder().decode(ChartResponse.self, from: data),
              let result = parsed.chart.result?.first,
              let price = result.meta.regularMarketPrice
        else { return nil }
        let paid = (result.events?.dividends ?? [:]).values.compactMap(\.amount).reduce(0, +)
        return yieldPct(dividendSum: paid, price: price)
    }

    static func yieldPct(dividendSum: Double, price: Double) -> Double? {
        guard price > 0, dividendSum > 0 else { return nil }
        return dividendSum / price * 100
    }

    /// All dividend events (date, amount per share) over `range`, oldest
    /// first — the raw record income analysis is built from.
    public static func dividendEvents(symbol: String, range: String = "2y") async -> [(date: Date, amount: Double)] {
        let req = chartRequest(symbol: symbol, range: range, interval: "1mo", events: true)
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let parsed = try? JSONDecoder().decode(ChartResponse.self, from: data),
              let divs = parsed.chart.result?.first?.events?.dividends
        else { return [] }
        return divs.compactMap { key, div -> (Date, Double)? in
            guard let ts = TimeInterval(key), let amount = div.amount else { return nil }
            return (Date(timeIntervalSince1970: ts), amount)
        }
        .sorted { $0.0 < $1.0 }
    }

    public static func fetch(symbol: String) async -> Quote? {
        // 1mo of daily closes → the row sparkline; meta still carries the
        // live price + previous close.
        let req = chartRequest(symbol: symbol, range: "1mo")
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let parsed = try? JSONDecoder().decode(ChartResponse.self, from: data),
              let result = parsed.chart.result?.first,
              let price = result.meta.regularMarketPrice
        else { return nil }
        let meta = result.meta
        var closes = (result.indicators?.quote?.first?.close ?? []).compactMap { $0 }
        // Is the series' last bar TODAY's (in-progress) bar? With range=1mo
        // Yahoo includes it during the session; yesterday's close is then the
        // second-to-last bar. Compare the last bar's UTC calendar day to now —
        // works for 24/7 crypto bars (00:00 UTC) and exchange bars alike.
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let lastIsToday = (result.timestamp?.last).map {
            cal.isDate(Date(timeIntervalSince1970: TimeInterval($0)), inSameDayAs: Date())
        } ?? false
        let prev: Double
        if lastIsToday, closes.count >= 2 {
            prev = closes[closes.count - 2]
            closes[closes.count - 1] = price // live tail replaces today's partial bar
        } else {
            prev = closes.last ?? meta.chartPreviousClose ?? meta.previousClose ?? price
            closes.append(price)
        }
        return Quote(symbol: symbol, price: price, previousClose: prev, closes: closes,
                     currency: meta.currency ?? "USD")
    }

    // MARK: - FX (display-currency conversion)

    /// Multipliers into `display` currency for every quote currency present
    /// (via Yahoo FX pairs, e.g. "USDCAD=X"). display itself maps to 1.
    public static func fxRates(for currencies: Set<String>, display: String) async -> [String: Double] {
        var out: [String: Double] = [display: 1]
        for cur in currencies where cur != display && !cur.isEmpty {
            if let q = await fetch(symbol: "\(cur)\(display)=X"), q.price > 0 {
                out[cur] = q.price
            }
        }
        return out
    }

    /// Fetch all symbols with bounded concurrency + one retry — a 400-symbol
    /// import must not fire 400 simultaneous requests (Yahoo rate-limits and
    /// the failures silently zero the totals).
    public static func fetchAll(symbols: [String], maxConcurrent: Int = 8) async -> [String: Quote] {
        let unique = Array(Set(symbols))
        guard !unique.isEmpty else { return [:] }
        return await withTaskGroup(of: Quote?.self) { group in
            var it = unique.makeIterator()
            for _ in 0..<min(maxConcurrent, unique.count) {
                if let s = it.next() { group.addTask { await fetchWithRetry(symbol: s) } }
            }
            var out: [String: Quote] = [:]
            for await q in group {
                if let q { out[q.symbol] = q }
                if let s = it.next() { group.addTask { await fetchWithRetry(symbol: s) } }
            }
            return out
        }
    }

    static func fetchWithRetry(symbol: String) async -> Quote? {
        if let q = await fetch(symbol: symbol) { return q }
        try? await Task.sleep(nanoseconds: 400_000_000)
        return await fetch(symbol: symbol)
    }

    // MARK: - History (invested-date detection + since-buy timelines)

    public struct HistoryPoint {
        public let date: Date
        public let close: Double
    }

    /// Daily closes going back `range` (Yahoo ranges: "1mo", "1y", "5y",
    /// "10y", "max"), oldest → newest. Used to detect when a position was
    /// opened and to draw since-invested timelines.
    public static func fetchHistory(symbol: String, range: String = "10y") async -> [HistoryPoint] {
        let req = chartRequest(symbol: symbol, range: range)
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let parsed = try? JSONDecoder().decode(ChartResponse.self, from: data),
              let result = parsed.chart.result?.first,
              let stamps = result.timestamp,
              let closes = result.indicators?.quote?.first?.close
        else { return [] }
        var out: [HistoryPoint] = []
        out.reserveCapacity(stamps.count)
        for (t, c) in zip(stamps, closes) {
            if let c { out.append(HistoryPoint(date: Date(timeIntervalSince1970: TimeInterval(t)), close: c)) }
        }
        return out
    }
}
