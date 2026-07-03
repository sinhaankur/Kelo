import Foundation

/// Fetches quotes from Yahoo Finance's chart endpoint — keyless, works for
/// equities and crypto (e.g. "BTC-USD"). Quotes may be delayed; personal use.
enum QuoteService {
    struct ChartResponse: Decodable {
        struct Chart: Decodable { let result: [Result]? }
        struct Result: Decodable { let meta: Meta }
        struct Meta: Decodable {
            let symbol: String
            let regularMarketPrice: Double?
            let chartPreviousClose: Double?
            let previousClose: Double?
        }
        let chart: Chart
    }

    static func fetch(symbol: String) async -> Quote? {
        var comps = URLComponents(string: "https://query1.finance.yahoo.com/v8/finance/chart/\(symbol)")!
        comps.queryItems = [
            URLQueryItem(name: "interval", value: "1d"),
            URLQueryItem(name: "range", value: "1d"),
        ]
        var req = URLRequest(url: comps.url!)
        req.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 10
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let parsed = try? JSONDecoder().decode(ChartResponse.self, from: data),
              let meta = parsed.chart.result?.first?.meta,
              let price = meta.regularMarketPrice
        else { return nil }
        let prev = meta.chartPreviousClose ?? meta.previousClose ?? price
        return Quote(symbol: symbol, price: price, previousClose: prev)
    }

    /// Fetch all symbols concurrently; returns whatever succeeded.
    static func fetchAll(symbols: [String]) async -> [String: Quote] {
        await withTaskGroup(of: Quote?.self) { group in
            for s in Set(symbols) { group.addTask { await fetch(symbol: s) } }
            var out: [String: Quote] = [:]
            for await q in group { if let q { out[q.symbol] = q } }
            return out
        }
    }
}
