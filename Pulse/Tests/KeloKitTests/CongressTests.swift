import XCTest
@testable import KeloKit

final class CongressDecodeTests: XCTestCase {
    // A fixture mirroring the real kadoa-org feed shape (verified 2026-07-22),
    // including the messy rows the decoder must survive: a blank ticker, a
    // Senate row, and a row with no computed return.
    private let fixture = """
    [
      {"id":"house_1_t1","filer_name":"James A. Himes","chamber":"house","party":"D",
       "state":"CT","office":"U.S. Representative · CT-04","ticker":"HD",
       "asset_name":"Home Depot, Inc.","transaction_type":"Sale (Full)",
       "amount_range_low":15001,"amount_range_high":50000,
       "amount_range_label":"$15,001 - $50,000","transaction_date":"2026-06-01",
       "filing_date":"2026-07-20","days_to_file":49,
       "doc_url":"https://example.gov/a.pdf","ret_since":-0.10,"excess_since":-0.20},
      {"id":"sen_1_t1","filer_name":"Jane Doe","chamber":"senate","party":"R",
       "state":"TX","office":"U.S. Senator","ticker":"NVDA","asset_name":"NVIDIA",
       "transaction_type":"Purchase","amount_range_low":1001,"amount_range_high":15000,
       "amount_range_label":"$1,001 - $15,000","transaction_date":"2026-05-01",
       "filing_date":"2026-06-10","days_to_file":40,
       "doc_url":"https://example.gov/b.pdf","ret_since":0.25,"excess_since":0.15},
      {"id":"sen_1_t2","filer_name":"Jane Doe","chamber":"senate","party":"R",
       "state":"TX","ticker":"AAPL","transaction_type":"Purchase",
       "amount_range_low":1001,"amount_range_high":15000,
       "transaction_date":"2026-05-15","filing_date":"2026-06-20","days_to_file":36,
       "ret_since":null,"excess_since":null},
      {"id":"blank","filer_name":"No Ticker","chamber":"house","ticker":"",
       "transaction_type":"Sale (Partial)","filing_date":"2026-07-01"}
    ]
    """.data(using: .utf8)!

    func testDecodesAndSkipsBlankTickerRows() {
        let trades = CongressService.decode(fixture)!
        // The empty-ticker row is dropped; the three real rows remain.
        XCTAssertEqual(trades.count, 3)
        XCTAssertFalse(trades.contains { $0.ticker.isEmpty })
    }

    func testFieldMappingAndComputedValues() {
        let trades = CongressService.decode(fixture)!
        let hd = trades.first { $0.ticker == "HD" }!
        XCTAssertEqual(hd.filerName, "James A. Himes")
        XCTAssertEqual(hd.chamber, .house)
        XCTAssertEqual(hd.state, "CT")
        XCTAssertEqual(hd.kind, .sell)                 // "Sale (Full)" → sell
        XCTAssertEqual(hd.amountLow, 15001)
        XCTAssertEqual(hd.disclosureLagDays, 49)       // filed 49d late by law's clock
        XCTAssertEqual(hd.returnSince!, -0.10, accuracy: 0.0001)
        XCTAssertNotNil(hd.transactionDateValue)
    }

    func testKindNormalization() {
        XCTAssertEqual(CongressService.parseKind("Purchase"), .buy)
        XCTAssertEqual(CongressService.parseKind("Sale (Full)"), .sell)
        XCTAssertEqual(CongressService.parseKind("Sale (Partial)"), .sell)
        XCTAssertEqual(CongressService.parseKind("Exchange"), .exchange)
        XCTAssertEqual(CongressService.parseKind("something odd"), .unknown)
        XCTAssertEqual(CongressService.parseKind(nil), .unknown)
    }

    func testGarbageJsonReturnsNilNotCrash() {
        XCTAssertNil(CongressService.decode("not json".data(using: .utf8)!))
    }
}

final class CongressScoringTests: XCTestCase {
    func testMoveWorkedDirection() {
        // A buy that rose worked; a buy that fell didn't.
        XCTAssertEqual(CongressService.moveWorked(kind: .buy, returnSince: 0.1), true)
        XCTAssertEqual(CongressService.moveWorked(kind: .buy, returnSince: -0.1), false)
        // A sell that fell worked (loss avoided); a sell that rose didn't.
        XCTAssertEqual(CongressService.moveWorked(kind: .sell, returnSince: -0.1), true)
        XCTAssertEqual(CongressService.moveWorked(kind: .sell, returnSince: 0.1), false)
        // No return, or a non-directional move → no judgement (never guessed).
        XCTAssertNil(CongressService.moveWorked(kind: .buy, returnSince: nil))
        XCTAssertNil(CongressService.moveWorked(kind: .exchange, returnSince: 0.1))
    }

    private func trade(_ name: String, _ kind: CongressTrade.Kind, ret: Double?,
                       ticker: String = "AAA") -> CongressTrade {
        CongressTrade(id: "\(name)-\(ticker)-\(ret ?? 0)", filerName: name, chamber: .senate,
                      party: "R", state: "TX", office: nil, ticker: ticker, assetName: nil,
                      kind: kind, amountLow: 1001, amountHigh: 15000, amountLabel: nil,
                      transactionDate: "2026-05-01", filingDate: "2026-06-01",
                      disclosureLagDays: 31, docURL: nil, returnSince: ret, excessSince: nil)
    }

    func testMemberScorecardHitRateAndAverage() {
        let trades = [
            trade("Winner", .buy, ret: 0.20, ticker: "AAA"),   // worked
            trade("Winner", .buy, ret: 0.10, ticker: "BBB"),   // worked
            trade("Winner", .sell, ret: 0.05, ticker: "CCC"),  // sell rose → didn't work
            trade("Winner", .exchange, ret: 0.99, ticker: "DDD"), // not directional
            trade("Quiet", .buy, ret: nil, ticker: "EEE"),     // unscored
        ]
        let cards = CongressService.memberScorecards(trades)
        let winner = cards.first { $0.filerName == "Winner" }!
        XCTAssertEqual(winner.tradeCount, 4)                    // exchange counts as a move
        XCTAssertEqual(winner.scoredCount, 4)                  // 4 have a return
        // Directional hits: 2 of 3 (the exchange isn't directional).
        XCTAssertEqual(winner.hitRate!, 2.0 / 3.0, accuracy: 0.0001)
        // Avg return across the 4 scored rows: (0.20+0.10+0.05+0.99)/4.
        XCTAssertEqual(winner.avgReturnSince!, 0.335, accuracy: 0.0001)

        let quiet = cards.first { $0.filerName == "Quiet" }!
        XCTAssertEqual(quiet.scoredCount, 0)
        XCTAssertNil(quiet.hitRate)                             // nothing scored → no claim
        XCTAssertNil(quiet.avgReturnSince)
    }

    func testScorecardsSortByActivity() {
        let trades = [
            trade("A", .buy, ret: 0.1), trade("A", .buy, ret: 0.1), trade("A", .buy, ret: 0.1),
            trade("B", .buy, ret: 0.1),
        ]
        let cards = CongressService.memberScorecards(trades)
        XCTAssertEqual(cards.first?.filerName, "A")             // most active on top
    }
}

final class CongressGeoTests: XCTestCase {
    func testKnownStatesResolveAndCoordinatesAreValid() {
        XCTAssertNotNil(CongressGeo.center("CT"))
        XCTAssertNotNil(CongressGeo.center("tx"))              // case-insensitive
        XCTAssertNotNil(CongressGeo.center("DC"))
        XCTAssertNil(CongressGeo.center("ZZ"))
        XCTAssertNil(CongressGeo.center(nil))
        // Every centre is a plausible coordinate.
        XCTAssertTrue(CongressGeo.centers.values.allSatisfy {
            abs($0.lat) <= 90 && abs($0.lon) <= 180
        })
    }

    func testAllFiftyStatesCovered() {
        let fifty = ["AL","AK","AZ","AR","CA","CO","CT","DE","FL","GA","HI","ID","IL",
                     "IN","IA","KS","KY","LA","ME","MD","MA","MI","MN","MS","MO","MT",
                     "NE","NV","NH","NJ","NM","NY","NC","ND","OH","OK","OR","PA","RI",
                     "SC","SD","TN","TX","UT","VT","VA","WA","WV","WI","WY"]
        for s in fifty { XCTAssertNotNil(CongressGeo.center(s), "missing \(s)") }
    }
}
