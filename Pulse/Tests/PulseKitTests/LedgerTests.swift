import XCTest
@testable import PulseKit

final class SnapshotStoreTests: XCTestCase {
    func testUpsertReplacesSameDayAndSorts() {
        let old = [
            DailySnapshot(date: "2026-07-01", holdings: 100, options: 0, cost: 90),
            DailySnapshot(date: "2026-07-03", holdings: 110, options: 5, cost: 90),
        ]
        let updated = SnapshotStore.upsert(
            DailySnapshot(date: "2026-07-02", holdings: 105, options: 2, cost: 90), into: old)
        XCTAssertEqual(updated.map(\.date), ["2026-07-01", "2026-07-02", "2026-07-03"])

        let replaced = SnapshotStore.upsert(
            DailySnapshot(date: "2026-07-03", holdings: 120, options: 6, cost: 90), into: updated)
        XCTAssertEqual(replaced.count, 3)
        XCTAssertEqual(replaced.last?.holdings, 120)
        XCTAssertEqual(replaced.last?.total, 126)
    }

    func testRecordRoundTripsThroughDisk() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("pulse-test-snapshots-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }

        SnapshotStore.record(holdings: 100, options: 10, cost: 95, to: url)
        let twice = SnapshotStore.record(holdings: 101, options: 11, cost: 95, to: url)
        // Same day → one entry, last write wins.
        XCTAssertEqual(twice.count, 1)
        XCTAssertEqual(twice[0].total, 112)
        XCTAssertEqual(SnapshotStore.load(from: url), twice)
    }
}

final class PaperLedgerTests: XCTestCase {
    private func trade(_ side: String, _ symbol: String, entry: Double,
                       date: String = "2026-06-01") -> PaperTrade {
        PaperTrade(date: date, side: side, symbol: symbol,
                   shares: 1, entryPrice: entry, amount: entry)
    }

    private let quotes: [String: Quote] = [
        "UP": Quote(symbol: "UP", price: 110, previousClose: 109, closes: []),
        "DOWN": Quote(symbol: "DOWN", price: 90, previousClose: 91, closes: []),
    ]

    func testBuyCallScoredByDirection() {
        let reviews = PaperLedger.review(
            [trade("BUY", "UP", entry: 100), trade("BUY", "DOWN", entry: 100)],
            quotes: quotes, benchmark: [])
        XCTAssertEqual(reviews[0].movePct!, 10, accuracy: 0.001)
        XCTAssertEqual(reviews[0].callRightSoFar, true)
        XCTAssertEqual(reviews[1].callRightSoFar, false)
    }

    func testSellCallIsRightWhenPriceFalls() {
        let reviews = PaperLedger.review(
            [trade("SELL", "DOWN", entry: 100), trade("SELL", "UP", entry: 100)],
            quotes: quotes, benchmark: [])
        XCTAssertEqual(reviews[0].callRightSoFar, true)   // fell after sell → good exit
        XCTAssertEqual(reviews[1].callRightSoFar, false)  // rose after sell → left gains
    }

    func testBenchmarkUsesTheCallsOwnWindow() {
        let base = parseISODate("2026-05-30")!
        let bench = (0..<10).map {
            QuoteService.HistoryPoint(date: base.addingTimeInterval(Double($0) * 86_400),
                                      close: 100 + Double($0)) // 100 → 109
        }
        // Call made 2026-06-01 → first bench bar at/after is close 102.
        let r = PaperLedger.review([trade("BUY", "UP", entry: 100)],
                                   quotes: quotes, benchmark: bench)[0]
        XCTAssertEqual(r.benchmarkPct!, (109.0 - 102.0) / 102.0 * 100, accuracy: 0.001)
    }

    func testUnknownSymbolHasNoVerdict() {
        let r = PaperLedger.review([trade("BUY", "MISSING", entry: 100)],
                                   quotes: quotes, benchmark: [])[0]
        XCTAssertNil(r.movePct)
        XCTAssertNil(r.callRightSoFar)
    }

    func testAppendRemoveRoundTrip() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("pulse-test-paper-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }

        let t = trade("BUY", "UP", entry: 100)
        PaperLedger.append(t, to: url)
        PaperLedger.append(trade("SELL", "DOWN", entry: 50), to: url)
        XCTAssertEqual(PaperLedger.load(from: url).count, 2)
        PaperLedger.remove(id: t.id, from: url)
        let left = PaperLedger.load(from: url)
        XCTAssertEqual(left.count, 1)
        XCTAssertEqual(left[0].symbol, "DOWN")
    }
}

final class WatchlistTests: XCTestCase {
    func testAddRemoveRoundTrip() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("pulse-test-watch-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertEqual(Watchlist.add(" nvda ", to: url), ["NVDA"])
        XCTAssertEqual(Watchlist.add("NVDA", to: url), ["NVDA"]) // no dupes
        XCTAssertEqual(Watchlist.add("SHOP.TO", to: url), ["NVDA", "SHOP.TO"])
        XCTAssertEqual(Watchlist.remove("NVDA", from: url), ["SHOP.TO"])
        XCTAssertEqual(Watchlist.load(from: url), ["SHOP.TO"])
    }
}

final class DividendYieldTests: XCTestCase {
    func testYieldMath() {
        XCTAssertEqual(QuoteService.yieldPct(dividendSum: 1.05, price: 32.39)!, 3.242, accuracy: 0.01)
        XCTAssertNil(QuoteService.yieldPct(dividendSum: 0, price: 100))  // none paid ≠ 0% claim
        XCTAssertNil(QuoteService.yieldPct(dividendSum: 1, price: 0))
    }

    func testPayoutStatsTtmAndDecayTrend()  {
        let now = Date()
        func d(_ monthsAgo: Int) -> Date { now.addingTimeInterval(-Double(monthsAgo) * 30 * 86_400) }
        // Payout shrinking each month: 1.0, 0.9 … — a decaying annuity.
        let events = (0..<8).reversed().map { i in
            (date: d(i), amount: 1.0 - Double(7 - i) * 0.1)
        }
        let s = IncomeService.payoutStats(events: events, now: now)
        XCTAssertEqual(s.ttmPerShare, events.map(\.amount).reduce(0, +), accuracy: 0.001)
        XCTAssertNotNil(s.trendPct)
        XCTAssertLessThan(s.trendPct!, -10) // clearly decaying
    }

    func testStablePayoutIsNotFlaggedDecaying() {
        let now = Date()
        let events = (0..<8).map { i in
            (date: now.addingTimeInterval(-Double(i) * 30 * 86_400), amount: 0.5)
        }
        let s = IncomeService.payoutStats(events: events.reversed(), now: now)
        XCTAssertEqual(s.trendPct ?? 0, 0, accuracy: 0.001)
    }
}

final class EquitySymbolTests: XCTestCase {
    func testCompanyNewsOnlyForPlainEquities() {
        XCTAssertTrue(SentimentService.isEquitySymbol("AAPL"))
        XCTAssertFalse(SentimentService.isEquitySymbol("BTC-USD"))
        XCTAssertFalse(SentimentService.isEquitySymbol("^GSPC"))
        XCTAssertFalse(SentimentService.isEquitySymbol(""))
    }
}
