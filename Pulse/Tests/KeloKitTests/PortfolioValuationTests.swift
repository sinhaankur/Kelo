import XCTest
@testable import KeloKit

/// Proves the shared valuation is correct + honest: no quote → no value (never
/// a guessed price), FX is applied, day change is value-weighted.
final class PortfolioValuationTests: XCTestCase {

    private func holding(_ sym: String, qty: Double, cost: Double = 0, ccy: String = "USD") -> Holding {
        Holding(symbol: sym, quantity: qty, costBasis: cost, acquired: nil, currency: ccy, assetClass: nil)
    }
    private func quote(_ sym: String, price: Double, prev: Double, ccy: String = "USD") -> Quote {
        Quote(symbol: sym, price: price, previousClose: prev, closes: [prev, price], currency: ccy)
    }

    func testHoldingValueNeedsAQuote() {
        let h = holding("AAPL", qty: 10)
        // No quote → 0, never an invented price.
        XCTAssertEqual(PortfolioValuation.holdingValue(h, quotes: [:], fxRates: [:]), 0)
        // With a quote → price × qty.
        let q = ["AAPL": quote("AAPL", price: 200, prev: 190)]
        XCTAssertEqual(PortfolioValuation.holdingValue(h, quotes: q, fxRates: [:]), 2000)
    }

    func testFxIsApplied() {
        let h = holding("SHOP", qty: 5, ccy: "CAD")
        let q = ["SHOP": quote("SHOP", price: 100, prev: 100, ccy: "CAD")]
        // 0.73 CAD→USD → 5 × 100 × 0.73 = 365.
        let v = PortfolioValuation.holdingValue(h, quotes: q, fxRates: ["CAD": 0.73])
        XCTAssertEqual(v, 365, accuracy: 0.001)
    }

    func testTotalValueSumsQuotedHoldingsOnly() {
        let p = Portfolio(holdings: [holding("AAPL", qty: 10), holding("NOQUOTE", qty: 5)], calls: [])
        let q = ["AAPL": quote("AAPL", price: 200, prev: 190)]
        XCTAssertEqual(PortfolioValuation.totalValue(p, quotes: q, fxRates: [:]), 2000)
    }

    func testDayChangeIsValueWeighted() {
        // AAPL: value 2000, +5.26% (200 vs 190); MSFT: value 1000, -2% (98 vs 100).
        let p = Portfolio(holdings: [holding("AAPL", qty: 10), holding("MSFT", qty: 10)], calls: [])
        let q = [
            "AAPL": quote("AAPL", price: 200, prev: 190),
            "MSFT": quote("MSFT", price: 98, prev: 100),
        ]
        let pct = PortfolioValuation.dayChangePct(p, quotes: q, fxRates: [:])!
        // weighted: (2000×5.263 + 980×(−2.0)) / (2000+980) ≈ 2.87%
        XCTAssertEqual(pct, 2.87, accuracy: 0.1)
    }

    func testDayChangeNilWithoutQuotes() {
        let p = Portfolio(holdings: [holding("AAPL", qty: 10)], calls: [])
        XCTAssertNil(PortfolioValuation.dayChangePct(p, quotes: [:], fxRates: [:]))
    }

    func testTopHoldingsSortedWithMovesAndFallback() {
        let p = Portfolio(holdings: [holding("SMALL", qty: 1), holding("BIG", qty: 100), holding("DARK", qty: 3)], calls: [])
        let q = [
            "SMALL": quote("SMALL", price: 10, prev: 10),
            "BIG": quote("BIG", price: 50, prev: 45),
            // DARK has no quote → falls back to bare symbol.
        ]
        let top = PortfolioValuation.topHoldings(p, quotes: q, fxRates: [:], limit: 3)
        XCTAssertEqual(top.first, "BIG +11.1%")   // biggest value, with its move
        XCTAssertTrue(top.contains("DARK"))         // no quote → bare symbol, no fake %
    }
}
