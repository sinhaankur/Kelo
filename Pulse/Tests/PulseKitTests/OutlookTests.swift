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

    func testRsiExtremesAndInsufficientData() {
        let up = (0..<40).map { 100.0 + Double($0) }         // straight up
        XCTAssertEqual(OutlookService.rsi(closes: up, price: up.last!)!, 100, accuracy: 0.5)
        XCTAssertNil(OutlookService.rsi(closes: [1, 2, 3], price: 3)) // too short
    }

    func testMovingAverageGapNeedsFullWindow() {
        let flat = Array(repeating: 100.0, count: 60)
        XCTAssertEqual(OutlookService.movingAverageGap(closes: flat, price: 100, window: 50)!, 0, accuracy: 0.001)
        XCTAssertNil(OutlookService.movingAverageGap(closes: flat, price: 100, window: 200))
    }
}

final class BrokerageImportTests: XCTestCase {
    func testYahooSymbolMapping() {
        XCTAssertEqual(CsvImporter.yahooSymbol(raw: "SHOP", exchange: "TSX", securityType: "EQUITY", bookCurrency: "CAD"), "SHOP.TO")
        XCTAssertEqual(CsvImporter.yahooSymbol(raw: "TECK.B", exchange: "TSX", securityType: "EQUITY", bookCurrency: "CAD"), "TECK-B.TO")
        XCTAssertEqual(CsvImporter.yahooSymbol(raw: "ABC", exchange: "TSX-V", securityType: "EQUITY", bookCurrency: "CAD"), "ABC.V")
        XCTAssertEqual(CsvImporter.yahooSymbol(raw: "XYZ", exchange: "CSE", securityType: "EQUITY", bookCurrency: "CAD"), "XYZ.CN")
        XCTAssertEqual(CsvImporter.yahooSymbol(raw: "DEF", exchange: "CBOE CANADA", securityType: "EXCHANGE_TRADED_FUND", bookCurrency: "CAD"), "DEF.NE")
        XCTAssertEqual(CsvImporter.yahooSymbol(raw: "NVDA", exchange: "NASDAQ", securityType: "EQUITY", bookCurrency: "USD"), "NVDA")
        XCTAssertEqual(CsvImporter.yahooSymbol(raw: "BTC", exchange: "", securityType: "CRYPTOCURRENCY", bookCurrency: "CAD"), "BTC-CAD")
    }

    func testBrokerageReportParsing() {
        let csv = """
        Account Name,Symbol,Exchange,Security Type,Quantity,Market Price,Book Value (Market),Book Value Currency (Market)
        "Crypto","ADA","","CRYPTOCURRENCY","100","0.24","118.40","CAD"
        "TFSA","SHOP","TSX","EQUITY","2","95.00","150.00","CAD"
        "RRSP","NVDA","NASDAQ","EQUITY","1","190.00","120.00","USD"
        """
        let result = CsvImporter.parseHoldings(csv)
        XCTAssertTrue(result.isFullAccountReport)
        XCTAssertEqual(result.imported.count, 3)
        let ada = result.imported[0]
        XCTAssertEqual(ada.symbol, "ADA-CAD")
        XCTAssertEqual(ada.costBasis, 1.184, accuracy: 0.0001) // book ÷ qty, NOT market price
        XCTAssertEqual(ada.currency, "CAD")
        XCTAssertEqual(result.imported[1].symbol, "SHOP.TO")
        XCTAssertEqual(result.imported[1].costBasis, 75.0, accuracy: 0.001)
        XCTAssertEqual(result.imported[2].symbol, "NVDA")
        XCTAssertEqual(result.imported[2].currency, "USD")
    }

    func testSameAssetAcrossAccountsAggregates() {
        // SHOP in both TFSA and RRSP: total 3 shares, book 150+90=240 → avg 80.
        let csv = """
        Account Name,Symbol,Exchange,Security Type,Quantity,Market Price,Book Value (Market),Book Value Currency (Market)
        "TFSA","SHOP","TSX","EQUITY","2","95.00","150.00","CAD"
        "RRSP","SHOP","TSX","EQUITY","1","95.00","90.00","CAD"
        """
        let result = CsvImporter.parseHoldings(csv)
        XCTAssertEqual(result.imported.count, 1)
        XCTAssertEqual(result.imported[0].quantity, 3, accuracy: 0.0001)
        XCTAssertEqual(result.imported[0].costBasis, 80, accuracy: 0.0001)
    }

    func testGenericParserNeverGrabsMarketPriceAsCost() {
        // Header has "Market Price" but no cost column: import must fail the
        // rows rather than silently use the current price as the cost basis.
        let csv = "Symbol,Quantity,Market Price\nAAPL,10,200\n"
        let result = CsvImporter.parseHoldings(csv)
        XCTAssertTrue(result.imported.isEmpty)
    }
}
