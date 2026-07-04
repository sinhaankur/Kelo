import Foundation

/// Our own global-markets board — stock-focused, not general geopolitics.
/// Live indices by region, plus the commodities and rates that move stocks,
/// so you can see the whole world's session and how it connects to what you
/// own. Same idea as a world-monitor dashboard, built in and money-first.
public struct WorldMarkets {
    public struct Ticker {
        public let symbol: String
        public let name: String
        public let region: String
        public let price: Double
        public let dayPct: Double
        public let kind: Kind
        public enum Kind: String { case index, commodity, crypto, rate }
    }
    public let tickers: [Ticker]
    public let fetchedAt: Date

    public func byRegion() -> [(region: String, items: [Ticker])] {
        let order = ["North America", "Europe", "Asia-Pacific", "Commodities", "Crypto"]
        var groups: [String: [Ticker]] = [:]
        for t in tickers { groups[t.region, default: []].append(t) }
        return order.compactMap { r in groups[r].map { (r, $0) } }
    }

    /// A one-line read of the global session: how broad the move is.
    public var breadthSummary: String {
        let idx = tickers.filter { $0.kind == .index }
        guard !idx.isEmpty else { return "" }
        let up = idx.filter { $0.dayPct >= 0 }.count
        let mood = up == idx.count ? "green across the board"
                 : up == 0 ? "red across the board"
                 : "mixed"
        return "World equities \(up)/\(idx.count) up — \(mood)."
    }
}

public enum WorldMarketsService {
    static let board: [(symbol: String, name: String, region: String, kind: WorldMarkets.Ticker.Kind)] = [
        ("^GSPC", "S&P 500", "North America", .index),
        ("^IXIC", "Nasdaq", "North America", .index),
        ("^DJI", "Dow Jones", "North America", .index),
        ("^GSPTSE", "TSX (Canada)", "North America", .index),
        ("^FTSE", "FTSE 100 (UK)", "Europe", .index),
        ("^GDAXI", "DAX (Germany)", "Europe", .index),
        ("^FCHI", "CAC 40 (France)", "Europe", .index),
        ("^N225", "Nikkei (Japan)", "Asia-Pacific", .index),
        ("^HSI", "Hang Seng (HK)", "Asia-Pacific", .index),
        ("^BSESN", "Sensex (India)", "Asia-Pacific", .index),
        ("^AXJO", "ASX 200 (Australia)", "Asia-Pacific", .index),
        ("GC=F", "Gold", "Commodities", .commodity),
        ("CL=F", "Oil (WTI)", "Commodities", .commodity),
        ("SI=F", "Silver", "Commodities", .commodity),
        ("BTC-USD", "Bitcoin", "Crypto", .crypto),
        ("ETH-USD", "Ethereum", "Crypto", .crypto),
    ]

    public static func fetch() async -> WorldMarkets {
        let quotes = await QuoteService.fetchAll(symbols: board.map(\.symbol))
        let tickers = board.compactMap { entry -> WorldMarkets.Ticker? in
            guard let q = quotes[entry.symbol] else { return nil }
            return WorldMarkets.Ticker(symbol: entry.symbol, name: entry.name,
                                       region: entry.region, price: q.price,
                                       dayPct: q.dayChangePct, kind: entry.kind)
        }
        return WorldMarkets(tickers: tickers, fetchedAt: Date())
    }
}
