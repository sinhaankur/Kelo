import Foundation

/// Paper trades — calls logged from the Trade Draft card and then scored
/// against what the market actually did. This is the learning loop the
/// project is built around: no real orders, just an honest record of whether
/// each call would have been right, measured against the S&P over the same
/// window. Stored locally, gitignored.
public struct PaperTrade: Codable, Identifiable {
    public let id: UUID
    public let date: String      // ISO "YYYY-MM-DD" the call was made
    public let side: String      // "BUY" or "SELL"
    public let symbol: String
    public let shares: Double
    public let entryPrice: Double
    public let amount: Double

    public init(id: UUID = UUID(), date: String, side: String, symbol: String,
                shares: Double, entryPrice: Double, amount: Double) {
        self.id = id
        self.date = date
        self.side = side
        self.symbol = symbol
        self.shares = shares
        self.entryPrice = entryPrice
        self.amount = amount
    }
}

public struct PaperReview {
    public let trade: PaperTrade
    public let currentPrice: Double?
    /// Price move since the call, entry → now.
    public let movePct: Double?
    /// S&P 500 over the same window — the do-nothing alternative.
    public let benchmarkPct: Double?

    /// Direction verdict so far: a BUY call is right when the price rose,
    /// a SELL call is right when it fell. "So far" — not a final grade.
    public var callRightSoFar: Bool? {
        movePct.map { trade.side == "BUY" ? $0 >= 0 : $0 <= 0 }
    }
}

public enum PaperLedger {
    public static var fileURL: URL {
        Portfolio.dirURL.appendingPathComponent("paper-trades.json")
    }

    public static func load(from url: URL = fileURL) -> [PaperTrade] {
        guard let data = try? Data(contentsOf: url),
              let list = try? JSONDecoder().decode([PaperTrade].self, from: data)
        else { return [] }
        return list
    }

    static func save(_ trades: [PaperTrade], to url: URL) {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(trades) {
            try? data.write(to: url, options: .atomic)
        }
    }

    public static func append(_ trade: PaperTrade, to url: URL = fileURL) {
        save(load(from: url) + [trade], to: url)
    }

    public static func remove(id: UUID, from url: URL = fileURL) {
        save(load(from: url).filter { $0.id != id }, to: url)
    }

    /// Score every call against live quotes and the S&P over each call's own
    /// window. Pure — fully testable without the network.
    public static func review(_ trades: [PaperTrade],
                              quotes: [String: Quote],
                              benchmark: [QuoteService.HistoryPoint]) -> [PaperReview] {
        trades.map { t in
            let current = quotes[t.symbol]?.price
            let move = current.flatMap { c -> Double? in
                t.entryPrice > 0 ? (c - t.entryPrice) / t.entryPrice * 100 : nil
            }
            var bench: Double? = nil
            if let start = parseISODate(t.date),
               let b0 = benchmark.first(where: { $0.date >= start })?.close,
               let bN = benchmark.last?.close, b0 > 0 {
                bench = (bN - b0) / b0 * 100
            }
            return PaperReview(trade: t, currentPrice: current,
                               movePct: move, benchmarkPct: bench)
        }
    }
}
