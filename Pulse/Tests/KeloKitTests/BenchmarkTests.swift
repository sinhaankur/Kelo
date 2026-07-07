import XCTest
@testable import KeloKit

final class BenchmarkTests: XCTestCase {

    // The correctness point: a few years on a work permit earns ~no state
    // pension. Canada OAS needs 10 residency years to pay ANYTHING.
    func testShortStayCanadaEarnsNoOAS() {
        let p = Profile(age: 35, country: .canada,
                        pensionContributionYears: 5, residencyYears: 5)
        let benefit = Benchmark.annualStateBenefit(p)
        // 5 contribution years earns a little CPP, but OAS must be exactly 0.
        // Full = 12000 * 5/39 ≈ 1538; no OAS.
        XCTAssertLessThan(benefit, 2_000)
        XCTAssertGreaterThan(benefit, 0)
    }

    // US Social Security pays NOTHING below ~10 years / 40 credits.
    func testShortStayUSEarnsNothing() {
        let p = Profile(country: .unitedStates, pensionContributionYears: 6)
        XCTAssertEqual(Benchmark.annualStateBenefit(p), 0)
    }

    // Right at the OAS residency threshold, some OAS starts.
    func testCanadaOASStartsAtTenResidencyYears() {
        let below = Profile(country: .canada, pensionContributionYears: 9, residencyYears: 9)
        let at = Profile(country: .canada, pensionContributionYears: 10, residencyYears: 10)
        XCTAssertGreaterThan(Benchmark.annualStateBenefit(at),
                             Benchmark.annualStateBenefit(below))
    }

    // A long career gets the full-ish benefit (both components maxed).
    func testFullCareerCanadaGetsFullBenefit() {
        let p = Profile(country: .canada, pensionContributionYears: 40, residencyYears: 40)
        // ~12000 CPP + ~8500 OAS.
        XCTAssertEqual(Benchmark.annualStateBenefit(p), 20_500, accuracy: 500)
    }

    // With no state benefit, the target is simply expenses × 25 (4% rule).
    func testExpenseTargetIsExpensesTimes25WhenNoBenefit() {
        let p = Profile(age: 34, gender: .male, annualSalary: 90_000,
                        country: .other, pensionContributionYears: 0)
        let r = Benchmark.compute(profile: p, annualExpenses: 40_000, currentSaved: 0)
        XCTAssertEqual(r.expenseBasedTarget, 40_000 * 25, accuracy: 1)   // 1,000,000
        XCTAssertEqual(r.emergencyFundTarget, 40_000 / 12 * 6, accuracy: 1)
    }

    // The state benefit REDUCES how much you must self-fund.
    func testStateBenefitLowersTheTarget() {
        let permit = Profile(country: .canada, pensionContributionYears: 5, residencyYears: 5)
        let lifer = Profile(country: .canada, pensionContributionYears: 40, residencyYears: 40)
        let onPermit = Benchmark.compute(profile: permit, annualExpenses: 50_000, currentSaved: 0)
        let settled = Benchmark.compute(profile: lifer, annualExpenses: 50_000, currentSaved: 0)
        // The settled resident self-funds LESS → lower target.
        XCTAssertLessThan(settled.expenseBasedTarget, onPermit.expenseBasedTarget)
        // And the short-stay result must carry the honest $0/low-benefit note.
        XCTAssertTrue(onPermit.notes.contains { $0.lowercased().contains("work permit")
                                             || $0.lowercased().contains("reduced")
                                             || $0.lowercased().contains("self-fund") })
    }

    // Fidelity salary-multiple: interpolates between published anchors.
    func testSalaryMultipleInterpolates() {
        XCTAssertEqual(Benchmark.salaryMultipleTarget(age: 40), 3, accuracy: 0.01)
        XCTAssertEqual(Benchmark.salaryMultipleTarget(age: 45), 4, accuracy: 0.01)
        // Halfway 40→45 → 3.5×.
        XCTAssertEqual(Benchmark.salaryMultipleTarget(age: 42), 3.4, accuracy: 0.1)
        XCTAssertEqual(Benchmark.salaryMultipleTarget(age: 80), 10, accuracy: 0.01)
    }

    // Women fund a longer retirement → a modestly higher target, and it's
    // surfaced as an explicit note, not hidden.
    func testLongevityFactorRaisesTargetAndIsLabelled() {
        let f = Profile(gender: .female, country: .other)
        let m = Profile(gender: .male, country: .other)
        let rf = Benchmark.compute(profile: f, annualExpenses: 40_000, currentSaved: 0)
        let rm = Benchmark.compute(profile: m, annualExpenses: 40_000, currentSaved: 0)
        XCTAssertGreaterThan(rf.expenseBasedTarget, rm.expenseBasedTarget)
        XCTAssertTrue(rf.notes.contains { $0.lowercased().contains("life expectancy") })
    }
}
