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

final class VerdictTests: XCTestCase {
    private func timeline(symbol: String, days: Int, totalPct: Double, annPct: Double?,
                          benchPct: Double?, fromHigh: Double?, vsMa200: Double?) -> PositionTimeline {
        PositionTimeline(symbol: symbol, acquired: Date(timeIntervalSinceNow: -Double(days) * 86_400),
                         estimated: false, holdingDays: days, totalReturnPct: totalPct,
                         annualizedPct: annPct, closesSince: [], benchmarkPct: benchPct,
                         pctFromAllTimeHigh: fromHigh, vsMa200Pct: vsMa200)
    }

    func testTwoMarkersMakeAnExitCandidate() {
        // 80% off its high + below 200dma + thesis failed (−70%) = plain call.
        let h = Holding(symbol: "DYING", quantity: 100, costBasis: 10)
        let q = Quote(symbol: "DYING", price: 3, previousClose: 3, closes: [])
        let t = timeline(symbol: "DYING", days: 800, totalPct: -70, annPct: -40,
                         benchPct: 25, fromHigh: -80, vsMa200: -20)
        let v = ReviewService.verdicts(holdings: [h], quotes: ["DYING": q],
                                       timelines: ["DYING": t], fxRates: [:])
        XCTAssertEqual(v[0].call, .exit)
        XCTAssertGreaterThanOrEqual(v[0].reasons.count, 2)
    }

    func testHealthyPositionHolds() {
        let h = Holding(symbol: "FINE", quantity: 10, costBasis: 100)
        let q = Quote(symbol: "FINE", price: 130, previousClose: 129, closes: [])
        let t = timeline(symbol: "FINE", days: 500, totalPct: 30, annPct: 21,
                         benchPct: 20, fromHigh: -4, vsMa200: 6)
        let v = ReviewService.verdicts(holdings: [h], quotes: ["FINE": q],
                                       timelines: ["FINE": t], fxRates: [:])
        XCTAssertEqual(v[0].call, .hold)
        XCTAssertTrue(v[0].reasons.isEmpty)
    }

    func testOneMarkerMeansReview() {
        let h = Holding(symbol: "MEH", quantity: 10, costBasis: 100)
        let q = Quote(symbol: "MEH", price: 90, previousClose: 90, closes: [])
        // Only the laggard marker fires (held 2y, way behind the index).
        let t = timeline(symbol: "MEH", days: 730, totalPct: -10, annPct: -5,
                         benchPct: 40, fromHigh: -30, vsMa200: 2)
        let v = ReviewService.verdicts(holdings: [h], quotes: ["MEH": q],
                                       timelines: ["MEH": t], fxRates: [:])
        XCTAssertEqual(v[0].call, .review)
        XCTAssertEqual(v[0].reasons.count, 1)
    }

    func testDustAggregationAndLaggardImpactMath() {
        var holdings: [Holding] = []
        var quotes: [String: Quote] = [:]
        for i in 0..<12 {
            let s = "D\(i)"
            holdings.append(Holding(symbol: s, quantity: 1, costBasis: 10))
            quotes[s] = Quote(symbol: s, price: 10, previousClose: 10, closes: [])
        }
        holdings.append(Holding(symbol: "BIG", quantity: 100, costBasis: 90))
        quotes["BIG"] = Quote(symbol: "BIG", price: 100, previousClose: 100, closes: [])
        let items = ReviewService.review(holdings: holdings, quotes: quotes,
                                         timelines: [:], fxRates: [:])
        XCTAssertTrue(items.contains { $0.kind == .dust })
    }
}

final class WorldMarketsTests: XCTestCase {
    func testRegionGroupingAndBreadth() {
        let t = [
            WorldMarkets.Ticker(symbol: "^GSPC", name: "S&P 500", region: "North America",
                                price: 100, dayPct: 1.0, kind: .index),
            WorldMarkets.Ticker(symbol: "^N225", name: "Nikkei", region: "Asia-Pacific",
                                price: 100, dayPct: -0.5, kind: .index),
            WorldMarkets.Ticker(symbol: "GC=F", name: "Gold", region: "Commodities",
                                price: 100, dayPct: 2.0, kind: .commodity),
        ]
        let w = WorldMarkets(tickers: t, fetchedAt: Date())
        let regions = w.byRegion().map(\.region)
        XCTAssertEqual(regions, ["North America", "Asia-Pacific", "Commodities"]) // ordered
        // Breadth counts only indices: 1 of 2 up.
        XCTAssertTrue(w.breadthSummary.contains("1/2"))
    }
}

final class MacroDataTests: XCTestCase {
    func testFredCsvParse() {
        let csv = """
        observation_date,CPIAUCSL
        2025-05-01,320.0
        2025-06-01,.
        2026-05-01,333.979
        """
        let rows = MacroDataService.parseCsv(csv)
        XCTAssertEqual(rows.count, 2) // the "." missing value is skipped
        XCTAssertEqual(rows.first?.value ?? 0, 320.0, accuracy: 0.001)
        XCTAssertEqual(rows.last?.value ?? 0, 333.979, accuracy: 0.001)
    }
}

final class TacticalDataTests: XCTestCase {
    func testCountryCentersCoverConflictZones() {
        XCTAssertNotNil(CountryGeo.center("Ukraine"))
        XCTAssertNotNil(CountryGeo.center("Israel"))
        XCTAssertNotNil(CountryGeo.center("Sudan"))
        XCTAssertNil(CountryGeo.center("Atlantis"))
    }
    func testChokepointsPresent() {
        XCTAssertTrue(Chokepoints.all.contains { $0.name.contains("Hormuz") })
        XCTAssertTrue(Chokepoints.all.contains { $0.name.contains("Suez") })
        XCTAssertTrue(Chokepoints.all.allSatisfy { abs($0.lat) <= 90 && abs($0.lon) <= 180 })
    }
}

final class GeoDependencyTests: XCTestCase {
    func testSemiconductorChain() {
        let d = GeoDependencyLens.forIndustry("Semiconductors")
        XCTAssertTrue(d.producers.contains { $0.contains("Taiwan") })
        XCTAssertTrue(d.chokepoints.contains { $0.contains("Taiwan") })
        XCTAssertFalse(d.isEmpty)
    }
    func testOilChainHasHormuz() {
        let d = GeoDependencyLens.forIndustry("Oil & Gas")
        XCTAssertTrue(d.chokepoints.contains { $0.contains("Hormuz") })
    }
    func testUnknownIndustryIsEmpty() {
        XCTAssertTrue(GeoDependencyLens.forIndustry("Something Obscure").isEmpty)
    }
}

final class MacroLensTests: XCTestCase {
    func testEnergyStockGetsWarAndDollarChannels() {
        let e = MacroLens.exposures(industry: "Oil & Gas", country: "US")
        XCTAssertTrue(e.contains { $0.force.contains("War") })
        XCTAssertTrue(e.contains { $0.force.contains("petrodollar") || $0.channel.contains("dollar") })
    }
    func testForeignStockAddsCurrencyExposure() {
        let e = MacroLens.exposures(industry: "Banking", country: "IN")
        XCTAssertTrue(e.contains { $0.force.contains("Currency") })
    }
    func testUnknownIndustryStillGetsUniversalChannel() {
        let e = MacroLens.exposures(industry: nil, country: "US")
        XCTAssertFalse(e.isEmpty)
    }
}

final class SectorTests: XCTestCase {
    func testSectorGroupingAndConcentration() {
        let holds = [
            Holding(symbol: "AAPL", quantity: 1, costBasis: 100, currency: "USD", assetClass: "Stock"),
            Holding(symbol: "MSFT", quantity: 1, costBasis: 100, currency: "USD", assetClass: "Stock"),
            Holding(symbol: "BTC-USD", quantity: 1, costBasis: 100, currency: "USD", assetClass: "Crypto"),
        ]
        let quotes = [
            "AAPL": Quote(symbol: "AAPL", price: 100, previousClose: 100, closes: []),
            "MSFT": Quote(symbol: "MSFT", price: 100, previousClose: 100, closes: []),
            "BTC-USD": Quote(symbol: "BTC-USD", price: 100, previousClose: 100, closes: []),
        ]
        let slices = ClusterService.sectors(holdings: holds, quotes: quotes, fxRates: [:],
                                            industryBySymbol: ["AAPL": "Technology", "MSFT": "Technology"])
        XCTAssertTrue(slices.contains { $0.name == "Technology" && $0.count == 2 })
        XCTAssertTrue(slices.contains { $0.name == "Crypto" })
    }
}

final class AgentTests: XCTestCase {
    private func tmpState() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("pulse-test-agent-\(UUID()).json")
    }

    private let ideas: (longs: [TradeIdea], shorts: [TradeIdea]) = (
        longs: [TradeIdea(direction: "LONG", symbol: "UP", thesis: "uptrend")],
        shorts: [TradeIdea(direction: "SHORT (paper)", symbol: "DOWN", thesis: "broken")]
    )
    private let quotes = [
        "UP": Quote(symbol: "UP", price: 100, previousClose: 99, closes: []),
        "DOWN": Quote(symbol: "DOWN", price: 50, previousClose: 51, closes: []),
    ]

    func testAgentCallsTheTopLongOnceAndOnlyOncePerDay() {
        let url = tmpState(); defer { try? FileManager.default.removeItem(at: url) }
        let first = AgentService.runCycle(ideas: ideas, quotes: quotes, fxRates: [:],
                                          openCalls: [], today: "2026-07-03", stateURL: url)
        XCTAssertEqual(first?.trade.symbol, "UP")
        XCTAssertEqual(first?.trade.side, "BUY")
        XCTAssertEqual(first?.trade.source, "agent")
        XCTAssertEqual(first!.trade.shares, 2.5, accuracy: 0.001) // 250 / 100
        // Same day → discipline: no second call.
        let second = AgentService.runCycle(ideas: ideas, quotes: quotes, fxRates: [:],
                                           openCalls: [first!.trade], today: "2026-07-03", stateURL: url)
        XCTAssertNil(second)
        // Next day, UP already called → falls through to the short.
        let third = AgentService.runCycle(ideas: ideas, quotes: quotes, fxRates: [:],
                                          openCalls: [first!.trade], today: "2026-07-04", stateURL: url)
        XCTAssertEqual(third?.trade.symbol, "DOWN")
        XCTAssertEqual(third?.trade.side, "SELL")
    }

    func testAgentRespectsMaxOpenCalls() {
        let url = tmpState(); defer { try? FileManager.default.removeItem(at: url) }
        let open = (0..<6).map { i in
            PaperTrade(date: "2026-07-01", side: "BUY", symbol: "S\(i)",
                       shares: 1, entryPrice: 10, amount: 10, source: "agent")
        }
        let action = AgentService.runCycle(ideas: ideas, quotes: quotes, fxRates: [:],
                                           openCalls: open, today: "2026-07-03", stateURL: url)
        XCTAssertNil(action)
    }

    func testWealthsimpleSymbolReverseMapping() {
        XCTAssertEqual(AgentService.wealthsimpleSymbol("SHOP.TO"), "SHOP")
        XCTAssertEqual(AgentService.wealthsimpleSymbol("TECK-B.TO"), "TECK.B")
        XCTAssertEqual(AgentService.wealthsimpleSymbol("ABC.V"), "ABC")
        XCTAssertEqual(AgentService.wealthsimpleSymbol("XYZ.CN"), "XYZ")
        XCTAssertEqual(AgentService.wealthsimpleSymbol("BTC-CAD"), "BTC")
        XCTAssertEqual(AgentService.wealthsimpleSymbol("ADA-USD"), "ADA")
        XCTAssertEqual(AgentService.wealthsimpleSymbol("NVDA"), "NVDA")
        XCTAssertEqual(AgentService.wealthsimpleSymbol("BRK-B"), "BRK-B") // US class shares stay dashed
    }

    func testAgentStoresItsReasoning() {
        let url = tmpState(); defer { try? FileManager.default.removeItem(at: url) }
        let action = AgentService.runCycle(ideas: ideas, quotes: quotes, fxRates: [:],
                                           openCalls: [], today: "2026-07-03", stateURL: url)!
        let state = AgentService.loadState(from: url)
        XCTAssertEqual(state.reasonings[action.trade.id.uuidString], "uptrend")
        XCTAssertEqual(state.lastActionDate, "2026-07-03")
    }
}

final class IBKRGuardTests: XCTestCase {
    func testLiveAccountsAreRefusedInCode() {
        // The paper lock is structural: a U-prefixed (live) account throws.
        XCTAssertThrowsError(try IBKRService.validatePaperOrder(
            accountId: "U1234567", quantity: 1, notional: 100))
        XCTAssertNoThrow(try IBKRService.validatePaperOrder(
            accountId: "DU1234567", quantity: 1, notional: 100))
    }

    func testCeilingAndShareGuards() {
        XCTAssertThrowsError(try IBKRService.validatePaperOrder(
            accountId: "DU1234567", quantity: 0, notional: 100))
        XCTAssertThrowsError(try IBKRService.validatePaperOrder(
            accountId: "DU1234567", quantity: 5, notional: 1_500))
        XCTAssertNoThrow(try IBKRService.validatePaperOrder(
            accountId: "DU1234567", quantity: 5, notional: 999))
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
