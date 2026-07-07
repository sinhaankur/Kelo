import XCTest
@testable import KeloKit

final class DNATests: XCTestCase {
    private let sample = """
    # MyHeritage raw data
    # build 37
    rsID\tchromosome\tposition\tallele1\tallele2
    rs762551\t15\t75041917\tA\tA
    rs4988235\t2\t136608646\tG\tG
    rs1815739\t11\t66560624\tC\tT
    rs99999999\t1\t12345\t-\t-
    """

    func testParsesMyHeritageFormatSkippingCommentsAndBadRows() {
        let g = DNAParser.parse(sample)
        // 3 valid rs rows with real calls; the "--" row is tolerated (kept as
        // empty allele set) but the header/comments are skipped.
        XCTAssertEqual(g["rs762551"]?.alleles, "AA")
        XCTAssertEqual(g["rs4988235"]?.alleles, "GG")
        XCTAssertNil(g["rsID"])          // header not parsed as a variant
        XCTAssertEqual(g["rs762551"]?.chromosome, "15")
    }

    func testGenotypeMatchingIsOrderIndependent() {
        XCTAssertEqual(DNAParser.normalizeAlleles("GA"), DNAParser.normalizeAlleles("AG"))
        XCTAssertEqual(DNAParser.normalizeAlleles("TC"), "CT")
    }

    func testInsightsFlagCarriedTraits() {
        let g = DNAParser.parse(sample)
        let insights = DNAParser.insights(genome: g, table: DNATable.associations)
        // rs762551 AA is the fast-caffeine-metabolizer genotype → carried.
        let caffeine = insights.first { $0.association.rsID == "rs762551" }
        XCTAssertNotNil(caffeine)
        XCTAssertTrue(caffeine?.carriesTrait ?? false)
        // rs1815739 is CT here, table flags TT → present but NOT carried.
        let muscle = insights.first { $0.association.rsID == "rs1815739" }
        XCTAssertEqual(muscle?.carriesTrait, false)
    }

    func testEveryTableEntryCitesASource() {
        for a in DNATable.associations {
            XCTAssertFalse(a.source.isEmpty, "\(a.rsID) must name its source")
            XCTAssertTrue(["GWAS Catalog", "ClinVar"].contains(a.source),
                          "\(a.rsID) source must be an open catalog, not SNPedia")
        }
    }
}

final class MovementTests: XCTestCase {
    func testSedentaryFlagNeedsEnoughTrackedTimeAndHighSitting() {
        // 20 active / 10 sitting over only 30 min → not enough tracked time.
        let brief = MovementDay(date: "2026-07-06", activeMinutes: 20, sittingMinutes: 10)
        XCTAssertFalse(brief.tooSedentary)
        // 10 active / 110 sitting over 120 min → 92% sitting → flagged.
        let deskDay = MovementDay(date: "2026-07-06", activeMinutes: 10, sittingMinutes: 110)
        XCTAssertTrue(deskDay.tooSedentary)
        XCTAssertEqual(deskDay.sittingFraction, 110.0/120.0, accuracy: 0.001)
    }
}

final class CrossFitTests: XCTestCase {
    func testForTimePRIsTheLowestTime() {
        let wods = [
            WOD(date: "2026-06-01", name: "Fran", scoring: .forTime, result: "4:10"),
            WOD(date: "2026-06-15", name: "Fran", scoring: .forTime, result: "3:41"),
            WOD(date: "2026-06-20", name: "Fran", scoring: .forTime, result: "3:55"),
        ]
        let prs = CrossFitStore.personalRecords(from: wods)
        XCTAssertEqual(prs.first(where: { $0.name == "Fran" })?.best, "3:41")
    }

    func testLoadPRIsTheHeaviest() {
        let wods = [
            WOD(date: "2026-06-01", name: "Back Squat", scoring: .load, result: "205 lb"),
            WOD(date: "2026-06-10", name: "Back Squat", scoring: .load, result: "225 lb"),
        ]
        let prs = CrossFitStore.personalRecords(from: wods)
        XCTAssertEqual(prs.first(where: { $0.name == "Back Squat" })?.best, "225 lb")
    }

    func testTimeParsingToSeconds() {
        XCTAssertEqual(WOD(date: "d", name: "x", scoring: .forTime, result: "3:41").numericResult, 221)
        XCTAssertEqual(WOD(date: "d", name: "x", scoring: .load, result: "225 lb").numericResult, 225)
    }
}
