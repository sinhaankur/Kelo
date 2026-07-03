import Foundation

/// The Pulse Agent — works every refresh, calls at most once per day, and
/// keeps score in the open. It scans the book with the same signal engines
/// the user sees (working uptrends → BUY calls, broken charts → SHORT
/// calls), logs each call to the paper ledger under source "agent", and its
/// running hit rate IS the answer to "does it make money": the record
/// decides, never the confidence. It cannot predict prices and never
/// touches real money.
public struct AgentState: Codable {
    public var lastActionDate: String?
    /// Reasoning per call, keyed by the paper trade's id.
    public var reasonings: [String: String] = [:]

    public init(lastActionDate: String? = nil, reasonings: [String: String] = [:]) {
        self.lastActionDate = lastActionDate
        self.reasonings = reasonings
    }
}

public enum AgentService {
    public static var stateURL: URL {
        Portfolio.dirURL.appendingPathComponent("agent-state.json")
    }

    public struct Action {
        public let trade: PaperTrade
        public let reasoning: String
    }

    public static func loadState(from url: URL = stateURL) -> AgentState {
        guard let data = try? Data(contentsOf: url),
              let s = try? JSONDecoder().decode(AgentState.self, from: data)
        else { return AgentState() }
        return s
    }

    static func saveState(_ s: AgentState, to url: URL) {
        if let data = try? JSONEncoder().encode(s) {
            try? data.write(to: url, options: .atomic)
        }
    }

    /// One agent cycle. Discipline is the strategy: at most one call per
    /// day, at most `maxOpen` open calls, never the same symbol twice,
    /// longs preferred over shorts, fixed small notional.
    public static func runCycle(ideas: (longs: [TradeIdea], shorts: [TradeIdea]),
                                quotes: [String: Quote],
                                fxRates: [String: Double],
                                openCalls: [PaperTrade],
                                today: String = isoDateString(Date()),
                                maxOpen: Int = 6,
                                notional: Double = 250,
                                stateURL: URL = stateURL) -> Action? {
        var state = loadState(from: stateURL)
        guard state.lastActionDate != today else { return nil }
        let agentCalls = openCalls.filter { $0.source == "agent" }
        guard agentCalls.count < maxOpen else { return nil }
        let already = Set(openCalls.map(\.symbol))

        let pick = ideas.longs.first { !already.contains($0.symbol) }
            ?? ideas.shorts.first { !already.contains($0.symbol) }
        guard let pick, let q = quotes[pick.symbol], q.price > 0 else { return nil }

        let fx = fxRates[q.currency] ?? 1
        let displayPrice = q.price * fx
        let side = pick.direction.hasPrefix("LONG") ? "BUY" : "SELL"
        let trade = PaperTrade(date: today, side: side, symbol: pick.symbol,
                               shares: notional / displayPrice,
                               entryPrice: q.price, amount: notional,
                               source: "agent")
        state.lastActionDate = today
        state.reasonings[trade.id.uuidString] = pick.thesis
        saveState(state, to: stateURL)
        return Action(trade: trade, reasoning: pick.thesis)
    }

    /// The agent's open scorecard from its reviewed calls.
    public static func scorecard(reviews: [PaperReview]) -> (right: Int, scored: Int, avgMove: Double?, avgBench: Double?) {
        let agent = reviews.filter { $0.trade.source == "agent" }
        let verdicts = agent.compactMap(\.callRightSoFar)
        let moves = agent.compactMap(\.movePct)
        let benches = agent.compactMap(\.benchmarkPct)
        return (verdicts.filter { $0 }.count,
                verdicts.count,
                moves.isEmpty ? nil : moves.reduce(0, +) / Double(moves.count),
                benches.isEmpty ? nil : benches.reduce(0, +) / Double(benches.count))
    }
}
