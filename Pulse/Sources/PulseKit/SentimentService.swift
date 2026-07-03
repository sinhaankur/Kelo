import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Global sentiment from REAL, sourced numbers — no invented scores:
///  · VIX (CBOE volatility index via Yahoo) with its standard reading bands
///  · world index breadth (how many major markets are up today)
///  · crypto Fear & Greed (alternative.me, keyless)
///  · market headlines (Finnhub, only when the user has put a key in
///    config.json) — interpretation of headlines is left to the LOCAL model.
public struct GlobalSentiment {
    public struct IndexMove {
        public let name: String
        public let dayPct: Double
    }
    public struct Headline {
        public let title: String
        public let source: String
        public let date: Date
    }
    /// World-dynamics gauge — a real level + day move (gold, oil, dollar,
    /// yields): the numbers geopolitics actually shows up in.
    public struct MacroGauge {
        public let name: String
        public let level: Double
        public let dayPct: Double
        public let unit: String

        public var levelLabel: String {
            switch unit {
            case "$": return usd(level)
            case "%": return String(format: "%.2f%%", level)
            default: return String(format: "%.1f", level)
            }
        }
    }

    public let vix: Double?
    public let indices: [IndexMove]
    public let macro: [MacroGauge]
    public let cryptoFearGreed: Int?
    public let cryptoFearGreedLabel: String?
    public let headlines: [Headline]
    public let fetchedAt: Date

    public var upCount: Int { indices.filter { $0.dayPct >= 0 }.count }

    /// Standard VIX reading bands (CBOE's own framing of the index).
    public var vixBand: String? {
        guard let v = vix else { return nil }
        switch v {
        case ..<15: return "calm"
        case ..<20: return "normal"
        case ..<30: return "elevated"
        default: return "high fear"
        }
    }

    /// One deterministic line, every number sourced.
    public var summary: String {
        var parts: [String] = []
        if let v = vix, let band = vixBand {
            parts.append("VIX \(String(format: "%.1f", v)) (\(band))")
        }
        if !indices.isEmpty {
            parts.append("world indices \(upCount)/\(indices.count) up today")
        }
        if let fg = cryptoFearGreed, let label = cryptoFearGreedLabel {
            parts.append("crypto fear/greed \(fg) (\(label.lowercased()))")
        }
        return parts.isEmpty ? "no sentiment data reachable" : parts.joined(separator: " · ")
    }
}

public enum SentimentService {
    static let indexSymbols: [(symbol: String, name: String)] = [
        ("^GSPC", "S&P 500"), ("^IXIC", "Nasdaq"), ("^DJI", "Dow"),
        ("^FTSE", "FTSE 100"), ("^GDAXI", "DAX"), ("^N225", "Nikkei 225"),
        ("^HSI", "Hang Seng"),
    ]

    // World-dynamics gauges: gold + oil (geopolitical stress), the dollar
    // index (global money flow), the US 10-year yield (rates). Yahoo quotes
    // ^TNX directly in percent (verified live: ~4.5, not 45).
    static let macroSymbols: [(symbol: String, name: String, unit: String, divisor: Double)] = [
        ("GC=F", "Gold", "$", 1),
        ("CL=F", "Oil WTI", "$", 1),
        ("DX-Y.NYB", "Dollar DXY", "", 1),
        ("^TNX", "US 10Y", "%", 1),
    ]

    public static func fetch(finnhubKey: String?) async -> GlobalSentiment {
        async let vixQuote = QuoteService.fetch(symbol: "^VIX")
        async let indexQuotes = QuoteService.fetchAll(symbols: indexSymbols.map(\.symbol))
        async let macroQuotes = QuoteService.fetchAll(symbols: macroSymbols.map(\.symbol))
        async let fearGreed = fetchCryptoFearGreed()
        async let news = fetchHeadlines(key: finnhubKey)

        let iq = await indexQuotes
        let indices = indexSymbols.compactMap { entry in
            iq[entry.symbol].map { GlobalSentiment.IndexMove(name: entry.name, dayPct: $0.dayChangePct) }
        }
        let mq = await macroQuotes
        let macro = macroSymbols.compactMap { entry in
            mq[entry.symbol].map {
                GlobalSentiment.MacroGauge(name: entry.name, level: $0.price / entry.divisor,
                                           dayPct: $0.dayChangePct, unit: entry.unit)
            }
        }
        let fg = await fearGreed
        return GlobalSentiment(vix: await vixQuote?.price,
                               indices: indices,
                               macro: macro,
                               cryptoFearGreed: fg?.value,
                               cryptoFearGreedLabel: fg?.label,
                               headlines: await news,
                               fetchedAt: Date())
    }

    // alternative.me Crypto Fear & Greed — keyless public API.
    private static func fetchCryptoFearGreed() async -> (value: Int, label: String)? {
        struct FngResponse: Decodable {
            struct Entry: Decodable {
                let value: String
                let value_classification: String
            }
            let data: [Entry]
        }
        guard let url = URL(string: "https://api.alternative.me/fng/?limit=1") else { return nil }
        var req = URLRequest(url: url)
        req.timeoutInterval = 10
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let parsed = try? JSONDecoder().decode(FngResponse.self, from: data),
              let entry = parsed.data.first,
              let v = Int(entry.value)
        else { return nil }
        return (v, entry.value_classification)
    }

    private struct NewsItem: Decodable {
        let headline: String
        let source: String
        let datetime: Int
    }

    private static func fetchNews(url: URL?, limit: Int) async -> [GlobalSentiment.Headline] {
        guard let url else { return [] }
        var req = URLRequest(url: url)
        req.timeoutInterval = 10
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let items = try? JSONDecoder().decode([NewsItem].self, from: data)
        else { return [] }
        return items.prefix(limit).map {
            GlobalSentiment.Headline(title: $0.headline, source: $0.source,
                                     date: Date(timeIntervalSince1970: TimeInterval($0.datetime)))
        }
    }

    // Finnhub general market news — requires the user's own key (config.json).
    private static func fetchHeadlines(key: String?) async -> [GlobalSentiment.Headline] {
        guard let key, !key.isEmpty else { return [] }
        var comps = URLComponents(string: "https://finnhub.io/api/v1/news")!
        comps.queryItems = [
            URLQueryItem(name: "category", value: "general"),
            URLQueryItem(name: "token", value: key),
        ]
        return await fetchNews(url: comps.url, limit: 6)
    }

    /// True for symbols Finnhub's company-news endpoint can answer for —
    /// plain equities, not crypto pairs ("BTC-USD") or indices ("^GSPC").
    public static func isEquitySymbol(_ symbol: String) -> Bool {
        !symbol.contains("-") && !symbol.hasPrefix("^") && !symbol.isEmpty
    }

    /// Last 7 days of company news for one holding (Finnhub, user's key).
    public static func companyNews(symbol: String, key: String?,
                                   limit: Int = 2) async -> [GlobalSentiment.Headline] {
        guard let key, !key.isEmpty, isEquitySymbol(symbol) else { return [] }
        let now = Date()
        var comps = URLComponents(string: "https://finnhub.io/api/v1/company-news")!
        comps.queryItems = [
            URLQueryItem(name: "symbol", value: symbol),
            URLQueryItem(name: "from", value: isoDateString(now.addingTimeInterval(-7 * 86_400))),
            URLQueryItem(name: "to", value: isoDateString(now)),
            URLQueryItem(name: "token", value: key),
        ]
        return await fetchNews(url: comps.url, limit: limit)
    }

    /// News for every equity holding, fetched concurrently.
    public static func holdingsNews(symbols: [String], key: String?)
        async -> [String: [GlobalSentiment.Headline]] {
        guard let key, !key.isEmpty else { return [:] }
        return await withTaskGroup(of: (String, [GlobalSentiment.Headline]).self) { group in
            for s in Set(symbols.filter(isEquitySymbol)) {
                group.addTask { (s, await companyNews(symbol: s, key: key)) }
            }
            var out: [String: [GlobalSentiment.Headline]] = [:]
            for await (s, n) in group where !n.isEmpty { out[s] = n }
            return out
        }
    }
}
