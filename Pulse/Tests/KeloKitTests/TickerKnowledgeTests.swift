import XCTest
@testable import KeloKit

/// Proves the agent's learning loop: the per-ticker knowledge base is built
/// from REAL resolved calls, the stance reflects the record (not confidence),
/// and runCycle actually steers by it — avoiding proven losers, preferring
/// proven winners.
final class TickerKnowledgeTests: XCTestCase {

    private func trade(_ sym: String, side: String) -> PaperTrade {
        PaperTrade(date: "2026-01-01", side: side, symbol: sym, shares: 1,
                   entryPrice: 100, amount: 100, source: "agent")
    }
    /// A resolved agent review: a BUY that moved `move`%, benchmark `bench`%.
    private func review(_ sym: String, side: String, move: Double, bench: Double) -> PaperReview {
        PaperReview(trade: trade(sym, side: side), currentPrice: 100 * (1 + move / 100),
                    movePct: move, benchmarkPct: bench)
    }
    private func idea(_ dir: String, _ sym: String) -> TradeIdea {
        TradeIdea(direction: dir, symbol: sym, thesis: "test")
    }
    private func quotesFor(_ syms: [String]) -> [String: Quote] {
        Dictionary(uniqueKeysWithValues: syms.map {
            ($0, Quote(symbol: $0, price: 100, previousClose: 100, closes: [100], currency: "USD"))
        })
    }

    // MARK: Knowledge base is built from real resolved calls

    func testBuildAggregatesPerTicker() {
        let reviews = [
            review("AAPL", side: "BUY", move: 5, bench: 1),   // right, beats hold
            review("AAPL", side: "BUY", move: 3, bench: 1),   // right, beats hold
            review("TSLA", side: "BUY", move: -4, bench: 2),  // wrong, trails hold
        ]
        let kb = TickerKnowledgeBase.build(reviews: reviews, whatIs: ["AAPL": "Apple · Technology"])
        let aapl = kb.first { $0.symbol == "AAPL" }!
        XCTAssertEqual(aapl.scored, 2)
        XCTAssertEqual(aapl.right, 2)
        XCTAssertEqual(aapl.hitRate, 1.0)
        XCTAssertEqual(aapl.beatsHold, true)
        XCTAssertEqual(aapl.whatItIs, "Apple · Technology")

        let tsla = kb.first { $0.symbol == "TSLA" }!
        XCTAssertEqual(tsla.right, 0)
        XCTAssertEqual(tsla.beatsHold, false)
    }

    func testUntestedWhenNoResolvedCalls() {
        let k = TickerKnowledge(symbol: "NVDA", whatItIs: "Nvidia", scored: 0, right: 0)
        XCTAssertNil(k.hitRate)
        XCTAssertEqual(k.stance, .untested)
        XCTAssertTrue(k.summary.contains("no track record"))
    }

    func testOnlyAgentCallsCount() {
        // A user's winning trade must NOT flatter the agent's record.
        let userTrade = PaperTrade(date: "2026-01-01", side: "BUY", symbol: "AAPL",
                                   shares: 1, entryPrice: 100, amount: 100, source: nil)
        let r = PaperReview(trade: userTrade, currentPrice: 200, movePct: 100, benchmarkPct: 1)
        let kb = TickerKnowledgeBase.build(reviews: [r])
        XCTAssertTrue(kb.isEmpty)   // no agent calls → nothing learned
    }

    // MARK: Stance reflects the record (conservative)

    func testStanceNeedsEnoughResolvedCalls() {
        // 2/2 right but only 2 scored → still untested (won't trust 2 samples).
        let two = TickerKnowledge(symbol: "X", whatItIs: "X", scored: 2, right: 2,
                                  avgMovePct: 5, avgBenchPct: 1)
        XCTAssertEqual(two.stance, .untested)
    }

    func testStancePreferWhenRightAndBeatingHold() {
        let k = TickerKnowledge(symbol: "AAPL", whatItIs: "Apple", scored: 5, right: 4,
                                avgMovePct: 4, avgBenchPct: 1)
        XCTAssertEqual(k.stance, .prefer)
    }

    func testStanceAvoidWhenLosing() {
        let k = TickerKnowledge(symbol: "TSLA", whatItIs: "Tesla", scored: 5, right: 1,
                                avgMovePct: -3, avgBenchPct: 2)
        XCTAssertEqual(k.stance, .avoid)
    }

    // MARK: runCycle STEERS by the knowledge (the loop is closed)

    func testRunCycleAvoidsProvenLosers() {
        // The agent's top idea is TSLA, but its record says avoid → it skips to AAPL.
        let kb = [TickerKnowledge(symbol: "TSLA", whatItIs: "Tesla", scored: 5, right: 1,
                                  avgMovePct: -3, avgBenchPct: 2)]
        let action = AgentService.runCycle(
            ideas: (longs: [idea("LONG", "TSLA"), idea("LONG", "AAPL")], shorts: []),
            quotes: quotesFor(["TSLA", "AAPL"]), fxRates: [:], openCalls: [],
            today: "2026-02-02", knowledge: kb,
            stateURL: FileManager.default.temporaryDirectory.appendingPathComponent("agent-\(UUID()).json"))
        XCTAssertEqual(action?.trade.symbol, "AAPL")   // avoided TSLA
    }

    func testRunCyclePrefersProvenWinners() {
        // AAPL is second in the list but a proven winner → it's picked first.
        let kb = [TickerKnowledge(symbol: "AAPL", whatItIs: "Apple", scored: 5, right: 4,
                                  avgMovePct: 4, avgBenchPct: 1)]
        let action = AgentService.runCycle(
            ideas: (longs: [idea("LONG", "MSFT"), idea("LONG", "AAPL")], shorts: []),
            quotes: quotesFor(["MSFT", "AAPL"]), fxRates: [:], openCalls: [],
            today: "2026-02-03", knowledge: kb,
            stateURL: FileManager.default.temporaryDirectory.appendingPathComponent("agent-\(UUID()).json"))
        XCTAssertEqual(action?.trade.symbol, "AAPL")   // preferred over MSFT
    }

    func testRunCycleUnchangedWithoutKnowledge() {
        // With no knowledge, behaviour is the old one: first eligible long.
        let action = AgentService.runCycle(
            ideas: (longs: [idea("LONG", "MSFT"), idea("LONG", "AAPL")], shorts: []),
            quotes: quotesFor(["MSFT", "AAPL"]), fxRates: [:], openCalls: [],
            today: "2026-02-04",
            stateURL: FileManager.default.temporaryDirectory.appendingPathComponent("agent-\(UUID()).json"))
        XCTAssertEqual(action?.trade.symbol, "MSFT")
    }
}
