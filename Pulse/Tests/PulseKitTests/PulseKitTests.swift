import XCTest
@testable import PulseKit

private func day(_ offset: Int, from base: TimeInterval = 1_600_000_000) -> Date {
    Date(timeIntervalSince1970: base + TimeInterval(offset) * 86_400)
}

private func history(_ closes: [Double]) -> [QuoteService.HistoryPoint] {
    closes.enumerated().map { QuoteService.HistoryPoint(date: day($0.offset), close: $0.element) }
}

final class CsvImporterTests: XCTestCase {
    func testBrokerExportHeaderVariants() {
        let csv = """
        Symbol,Shares,Avg Cost,Purchase Date
        NVDA,4,"1,020.50",03/15/2025
        tsla,2,242.10,2025-08-01
        """
        let result = CsvImporter.parseHoldings(csv)
        XCTAssertEqual(result.imported.count, 2)
        XCTAssertEqual(result.skippedRows, 0)
        XCTAssertEqual(result.imported[0].symbol, "NVDA")
        XCTAssertEqual(result.imported[0].costBasis, 1020.50)
        XCTAssertEqual(result.imported[0].acquired, "2025-03-15")
        XCTAssertEqual(result.imported[1].symbol, "TSLA")
        XCTAssertEqual(result.imported[1].acquired, "2025-08-01")
    }

    func testBadRowsAreSkippedNotFatal() {
        let csv = """
        ticker,qty,cost
        AAPL,10,250
        ,5,100
        MSFT,zero,410
        GOOG,3,180.5
        """
        let result = CsvImporter.parseHoldings(csv)
        XCTAssertEqual(result.imported.map(\.symbol), ["AAPL", "GOOG"])
        XCTAssertEqual(result.skippedRows, 2)
    }

    func testMissingSymbolColumnImportsNothing() {
        let result = CsvImporter.parseHoldings("name,value\nfoo,1\n")
        XCTAssertTrue(result.imported.isEmpty)
    }

    func testQuotedCommasStayInsideCells() {
        XCTAssertEqual(CsvImporter.splitCsvRow(#"A,"1,234.56",c"#), ["A", "1,234.56", "c"])
    }

    func testDollarSignsAndThousandsParse() {
        XCTAssertEqual(CsvImporter.parseNumber("$1,020.50"), 1020.50)
        XCTAssertNil(CsvImporter.parseNumber("n/a"))
    }
}

final class InvestedDateDetectionTests: XCTestCase {
    func testMostRecentCostCrossingWins() {
        // Crosses 100 going up at i=2, back down at i=5, up again at i=8:
        // the most recent crossing (8) is the best keyless buy-date guess.
        let h = history([90, 95, 105, 110, 108, 98, 96, 97, 103, 107])
        XCTAssertEqual(TimelineService.detectAcquisitionIndex(cost: 100, history: h), 8)
    }

    func testNeverCrossedFallsBackToNearestClose() {
        // Price never reached cost 50 — nearest close (index 0) is the guess.
        let h = history([60, 70, 80, 90])
        XCTAssertEqual(TimelineService.detectAcquisitionIndex(cost: 50, history: h), 0)
    }

    func testExplicitAcquiredDateIsNotEstimated() {
        let closes = Array(stride(from: 100.0, through: 199.0, by: 1.0))
        let h = history(closes)
        let acquired = isoDateString(day(40))
        let holding = Holding(symbol: "T", quantity: 1, costBasis: 140, acquired: acquired)
        let t = TimelineService.timeline(for: holding, history: h, price: 199, benchmark: h)
        XCTAssertNotNil(t)
        XCTAssertFalse(t!.estimated)
    }

    func testDetectedDateIsMarkedEstimated() {
        let h = history([90, 95, 105, 110])
        let holding = Holding(symbol: "T", quantity: 1, costBasis: 100)
        let t = TimelineService.timeline(for: holding, history: h, price: 110, benchmark: h)
        XCTAssertEqual(t?.estimated, true)
        XCTAssertTrue(t!.acquiredLabel.hasPrefix("~"))
    }

    func testAnnualizedIsNilUnderThirtyDays() {
        let h = history([100, 101, 102])
        let holding = Holding(symbol: "T", quantity: 1, costBasis: 100,
                              acquired: isoDateString(day(1)))
        let t = TimelineService.timeline(for: holding, history: h, price: 102, benchmark: h)
        // Held only since "yesterday" relative to fixed 2020 base — but the
        // holding days are measured to NOW, so this is actually years. Use a
        // recent acquired date instead.
        _ = t
        let recent = Calendar.current.date(byAdding: .day, value: -5, to: Date())!
        let recentHolding = Holding(symbol: "T", quantity: 1, costBasis: 100,
                                    acquired: isoDateString(recent))
        let closes = history([100, 101, 102])
        let t2 = TimelineService.timeline(for: recentHolding, history: closes,
                                          price: 102, benchmark: closes)
        XCTAssertNil(t2?.annualizedPct)
        XCTAssertEqual(t2!.totalReturnPct, 2.0, accuracy: 0.001)
    }

    func testSinceClosesDownsampledTo120() {
        let closes = Array(repeating: 100.0, count: 500).enumerated().map { Double($0.offset) + $0.element }
        let h = history(closes)
        let holding = Holding(symbol: "T", quantity: 1, costBasis: 100,
                              acquired: isoDateString(day(0)))
        let t = TimelineService.timeline(for: holding, history: h, price: 600, benchmark: h)
        XCTAssertLessThanOrEqual(t!.closesSince.count, 120)
        XCTAssertEqual(t!.closesSince.last!, 600, accuracy: 0.001) // live tail
    }
}

final class PortfolioHistoryTests: XCTestCase {
    func testValuesSumOnlyPositionsAlreadyOpen() {
        let hA = history([10, 11, 12, 13, 14, 15])
        let hB = history([100, 100, 100, 200, 200, 200])
        let a = Holding(symbol: "A", quantity: 2, costBasis: 10, acquired: isoDateString(day(0)))
        let b = Holding(symbol: "B", quantity: 1, costBasis: 100, acquired: isoDateString(day(3)))
        let tA = TimelineService.timeline(for: a, history: hA, price: 15, benchmark: hA)!
        let tB = TimelineService.timeline(for: b, history: hB, price: 200, benchmark: hB)!
        let ph = TimelineService.portfolioHistory(
            holdings: [a, b], timelines: ["A": tA, "B": tB],
            histories: ["A": hA, "B": hB], quotes: [:])
        XCTAssertNotNil(ph)
        // Day 0: only A is open (2 × 10); B joins at day 3 (2×13 + 1×200).
        XCTAssertEqual(ph!.values.first!, 20, accuracy: 0.001)
        XCTAssertEqual(ph!.costs.first!, 20, accuracy: 0.001)
        let day3 = ph!.values[3]
        XCTAssertEqual(day3, 226, accuracy: 0.001)
        XCTAssertEqual(ph!.costs[3], 120, accuracy: 0.001)
    }

    func testMissingHistoryMeansNoPartialChart() {
        let a = Holding(symbol: "A", quantity: 1, costBasis: 10, acquired: isoDateString(day(0)))
        let hA = history([10, 11])
        let tA = TimelineService.timeline(for: a, history: hA, price: 11, benchmark: hA)!
        let b = Holding(symbol: "B", quantity: 1, costBasis: 10)
        // B has no timeline/history — a partial reconstruction would lie.
        let ph = TimelineService.portfolioHistory(
            holdings: [a, b], timelines: ["A": tA], histories: ["A": hA], quotes: [:])
        XCTAssertNil(ph)
    }
}

final class OccSymbolTests: XCTestCase {
    func testFormat() {
        let call = CallPosition(underlying: "MSFT", strike: 500,
                                expiry: "2026-09-18", contracts: 1, premiumPaid: 850)
        XCTAssertEqual(OptionsService.occSymbol(for: call), "MSFT260918C00500000")
    }

    func testFractionalStrike() {
        let call = CallPosition(underlying: "F", strike: 12.5,
                                expiry: "2026-01-16", contracts: 2, premiumPaid: 100)
        XCTAssertEqual(OptionsService.occSymbol(for: call), "F260116C00012500")
    }
}

final class ThemeModeTests: XCTestCase {
    private func at(hour: Int) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: Date())!
    }

    func testAutoFollowsClock() {
        XCTAssertTrue(ThemeMode.auto.isDark(at: at(hour: 3)))
        XCTAssertFalse(ThemeMode.auto.isDark(at: at(hour: 12)))
        XCTAssertTrue(ThemeMode.auto.isDark(at: at(hour: 21)))
        XCTAssertFalse(ThemeMode.auto.isDark(at: at(hour: 7)))   // boundary → light
        XCTAssertTrue(ThemeMode.auto.isDark(at: at(hour: 19)))   // boundary → dark
    }

    func testManualOverrides() {
        XCTAssertFalse(ThemeMode.light.isDark(at: at(hour: 23)))
        XCTAssertTrue(ThemeMode.dark.isDark(at: at(hour: 12)))
    }
}

final class FormatTests: XCTestCase {
    func testHoldingPeriodBands() {
        XCTAssertEqual(holdingPeriodLabel(days: 12), "12d")
        XCTAssertEqual(holdingPeriodLabel(days: 91), "3mo")
        XCTAssertEqual(holdingPeriodLabel(days: 730), "2.0y")
    }

    func testIsoDateRoundTrip() {
        let d = parseISODate("2025-03-15")
        XCTAssertNotNil(d)
        XCTAssertEqual(isoDateString(d!), "2025-03-15")
    }
}

final class SentimentTests: XCTestCase {
    private func sentiment(vix: Double?) -> GlobalSentiment {
        GlobalSentiment(vix: vix, indices: [
            .init(name: "S&P 500", dayPct: 0.5),
            .init(name: "Nikkei 225", dayPct: -0.3),
        ], cryptoFearGreed: 21, cryptoFearGreedLabel: "Extreme Fear",
           headlines: [], fetchedAt: Date())
    }

    func testVixBands() {
        XCTAssertEqual(sentiment(vix: 12).vixBand, "calm")
        XCTAssertEqual(sentiment(vix: 17).vixBand, "normal")
        XCTAssertEqual(sentiment(vix: 25).vixBand, "elevated")
        XCTAssertEqual(sentiment(vix: 35).vixBand, "high fear")
        XCTAssertNil(sentiment(vix: nil).vixBand)
    }

    func testSummaryIsDeterministicAndSourced() {
        let s = sentiment(vix: 16.0)
        XCTAssertEqual(s.upCount, 1)
        XCTAssertEqual(s.summary,
            "VIX 16.0 (normal) · world indices 1/2 up today · crypto fear/greed 21 (extreme fear)")
    }
}
