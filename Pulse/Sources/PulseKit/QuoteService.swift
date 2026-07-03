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
        }
        struct Indicators: Decodable { let quote: [QuoteBlock]? }
        struct QuoteBlock: Decodable { let close: [Double?]? }
        struct Meta: Decodable {
            let symbol: String
            let regularMarketPrice: Double?
            let chartPreviousClose: Double?
            let previousClose: Double?
        }
        let chart: Chart
    }

    private static func chartRequest(symbol: String, range: String) -> URLRequest {
        var comps = URLComponents(string: "https://query1.finance.yahoo.com/v8/finance/chart/\(symbol)")!
        comps.queryItems = [
            URLQueryItem(name: "interval", value: "1d"),
            URLQueryItem(name: "range", value: range),
        ]
        var req = URLRequest(url: comps.url!)
        req.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 15
        return req
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
        return Quote(symbol: symbol, price: price, previousClose: prev, closes: closes)
    }

    /// Fetch all symbols concurrently; returns whatever succeeded.
    public static func fetchAll(symbols: [String]) async -> [String: Quote] {
        await withTaskGroup(of: Quote?.self) { group in
            for s in Set(symbols) { group.addTask { await fetch(symbol: s) } }
            var out: [String: Quote] = [:]
            for await q in group { if let q { out[q.symbol] = q } }
            return out
        }
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
