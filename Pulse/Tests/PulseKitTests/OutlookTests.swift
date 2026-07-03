import XCTest
@testable import PulseKit

final class OutlookStatsTests: XCTestCase {
    func testMomentumAndRangeFromKnownSeries() {
        let s = OutlookService.stats(closes: [100, 120, 90, 110], price: 110)
        XCTAssertEqual(s.ret1y!, 10, accuracy: 0.001)          // 100 → 110
        XCTAssertEqual(s.high!, 120, accuracy: 0.001)
        XCTAssertEqual(s.low!, 90, accuracy: 0.001)
        XCTAssertEqual(s.fromHigh!, -8.333, accuracy: 0.01)    // 110 vs 120
        XCTAssertEqual(s.drawdown!, -25, accuracy: 0.001)      // 120 → 90
        XCTAssertNil(s.vol) // too few bars to claim a volatility number
    }

    func testVolatilityPositiveForMovingSeries() {
        var closes: [Double] = [100]
        for i in 1..<60 { closes.append(closes[i - 1] * (i.isMultiple(of: 2) ? 1.01 : 0.99)) }
        let s = OutlookService.stats(closes: closes, price: closes.last!)
        XCTAssertNotNil(s.vol)
        XCTAssertGreaterThan(s.vol!, 5) // ~1%/day swings are real volatility
    }

    func testEmptySeriesReturnsNothingRatherThanGuesses() {
        let s = OutlookService.stats(closes: [], price: 100)
        XCTAssertNil(s.ret1y)
        XCTAssertNil(s.high)
        XCTAssertNil(s.vol)
    }

    func testAnalystCountsAggregate() {
        let r = StockOutlook.AnalystRecs(strongBuy: 5, buy: 10, hold: 8, sell: 2,
                                         strongSell: 1, period: "2026-06-01")
        XCTAssertEqual(r.total, 26)
        XCTAssertEqual(r.bullish, 15)
        XCTAssertEqual(r.bearish, 3)
    }
}
