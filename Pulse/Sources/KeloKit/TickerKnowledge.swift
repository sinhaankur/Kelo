import Foundation

/// The agent's per-ticker knowledge base — what each ticker is, and, more
/// importantly, HOW THE AGENT'S OWN CALLS ON IT HAVE ACTUALLY WORKED. This is
/// the learning: the record per symbol is derived from resolved paper calls
/// (never from confidence), and the agent reads it to tilt future picks toward
/// tickers it's been right on and away from ones it keeps getting wrong.
///
/// Honest by construction: every number comes from real reviewed calls. A
/// ticker the agent has never called (or never had a call resolve) has no
/// verdict — we say "no track record yet", never a guess.
public struct TickerKnowledge: Codable, Identifiable, Equatable {
    public var id: String { symbol }
    public let symbol: String
    /// What it is — a plain label ("Apple · Technology"), filled from whatever
    /// metadata is on hand (industry map, asset class). May be just the symbol.
    public var whatItIs: String
    /// How many of the agent's calls on this ticker have resolved (been scored).
    public var scored: Int
    /// How many of those were right so far (BUY & rose, or SELL & fell).
    public var right: Int
    /// Average price move on its calls (entry → now), %.
    public var avgMovePct: Double?
    /// Average S&P over the same windows — the do-nothing alternative, %.
    public var avgBenchPct: Double?

    public init(symbol: String, whatItIs: String, scored: Int, right: Int,
                avgMovePct: Double? = nil, avgBenchPct: Double? = nil) {
        self.symbol = symbol
        self.whatItIs = whatItIs
        self.scored = scored
        self.right = right
        self.avgMovePct = avgMovePct
        self.avgBenchPct = avgBenchPct
    }

    /// Hit rate on this ticker, or nil until at least one call has resolved.
    public var hitRate: Double? { scored > 0 ? Double(right) / Double(scored) : nil }

    /// Did the agent's calls on this ticker beat just holding the index?
    public var beatsHold: Bool? {
        guard let m = avgMovePct, let b = avgBenchPct else { return nil }
        return m > b
    }

    /// The learned stance the agent should take on this ticker next time.
    public enum Stance: String, Codable { case prefer, neutral, avoid, untested }

    /// A stance from the record — deliberately conservative: it takes a few
    /// resolved calls before it trusts a pattern, and "beating hold" matters
    /// more than a raw hit rate (a coin flip that underperforms is still bad).
    public var stance: Stance {
        guard let hr = hitRate, scored >= 3 else { return .untested }
        let beat = beatsHold ?? false
        if hr >= 0.6 && beat { return .prefer }
        if hr <= 0.34 || (avgMovePct ?? 0) < (avgBenchPct ?? 0) - 2 { return .avoid }
        return .neutral
    }

    /// A one-line, honest reading for the UI / the assistant.
    public var summary: String {
        guard let hr = hitRate else { return "\(whatItIs) — no track record yet." }
        let pct = Int((hr * 100).rounded())
        let vs: String
        if let m = avgMovePct, let b = avgBenchPct {
            let edge = m - b
            vs = String(format: " · %@ hold by %+.1f%%", edge >= 0 ? "beating" : "trailing", edge)
        } else { vs = "" }
        return "\(whatItIs) — \(right)/\(scored) right (\(pct)%)\(vs)."
    }
}

public enum TickerKnowledgeBase {

    /// Build the knowledge base from the agent's REVIEWED calls. `whatIs` maps a
    /// symbol to a plain label (name/sector); pass an empty map to fall back to
    /// the bare symbol. Only the agent's own calls count — the record is about
    /// the AGENT's skill, not the user's trades.
    public static func build(reviews: [PaperReview],
                             whatIs: [String: String] = [:]) -> [TickerKnowledge] {
        let agent = reviews.filter { $0.trade.source == "agent" }
        let bySymbol = Dictionary(grouping: agent, by: { $0.trade.symbol })
        return bySymbol.map { symbol, rs in
            let verdicts = rs.compactMap(\.callRightSoFar)
            let moves = rs.compactMap(\.movePct)
            let benches = rs.compactMap(\.benchmarkPct)
            return TickerKnowledge(
                symbol: symbol,
                whatItIs: whatIs[symbol] ?? symbol,
                scored: verdicts.count,
                right: verdicts.filter { $0 }.count,
                avgMovePct: moves.isEmpty ? nil : moves.reduce(0, +) / Double(moves.count),
                avgBenchPct: benches.isEmpty ? nil : benches.reduce(0, +) / Double(benches.count)
            )
        }
        .sorted { ($0.scored, $0.symbol) > ($1.scored, $1.symbol) }
    }

    /// The learned stance for one symbol (untested if it has no resolved calls).
    public static func stance(for symbol: String, in kb: [TickerKnowledge]) -> TickerKnowledge.Stance {
        kb.first { $0.symbol == symbol }?.stance ?? .untested
    }
}
