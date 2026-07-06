import XCTest
@testable import PulseKit

final class SpendServiceTests: XCTestCase {
    // A fixed "now" so month-window math is deterministic: 2026-07-15 (mid-month,
    // 31-day month → 15/31 elapsed ≈ 0.484).
    private let now = parseISODate("2026-07-15")!
    private let cal = Calendar(identifier: .gregorian)

    private func exp(_ date: String, _ amount: Double, _ cat: String) -> Expense {
        Expense(date: date, amount: amount, category: cat)
    }

    private func sampleData() -> SpendData {
        SpendData(
            expenses: [
                exp("2026-07-02", 100, "Dining"),
                exp("2026-07-10", 180, "Dining"),   // Dining MTD = 280 / 300
                exp("2026-07-05", 60, "Grocery"),
                exp("2026-06-28", 500, "Dining"),   // last month → excluded
                exp("2026-07-08", 40, "Coffee"),    // no budget → Uncategorised-ish
            ],
            budgets: [
                Budget(category: "Dining", limit: 300),
                Budget(category: "Grocery", limit: 400),
            ],
            goal: SavingsGoal(name: "Rebuild fund", target: 5500, saved: 500,
                              monthlyContribution: 420, targetDate: "2026-12-31")
        )
    }

    // MARK: this-month filtering

    func testThisMonthExcludesOtherMonths() {
        let m = SpendService.thisMonthExpenses(sampleData().expenses, now: now, calendar: cal)
        XCTAssertFalse(m.contains { $0.date == "2026-06-28" })
        XCTAssertEqual(m.count, 4)
    }

    // MARK: budgets + "left this month"

    func testBudgetLeftAndOver() {
        let s = SpendService.budgetStatuses(sampleData(), now: now, calendar: cal)
        let dining = s.first { $0.category == "Dining" }!
        XCTAssertEqual(dining.spent, 280, accuracy: 0.001)
        XCTAssertEqual(dining.left, 20, accuracy: 0.001)   // 300 - 280
        XCTAssertFalse(dining.over)
        // a no-budget category still surfaces (limit 0, over by definition of spend)
        XCTAssertTrue(s.contains { $0.category == "Coffee" && $0.limit == 0 })
    }

    func testPaceHotWhenBurningFast() {
        // Dining 280/300 = 93% by the 15th (48% of month) → burning hot.
        let s = SpendService.budgetStatuses(sampleData(), now: now, calendar: cal)
        XCTAssertTrue(s.first { $0.category == "Dining" }!.paceHot)
        // Grocery 60/400 = 15% → not hot.
        XCTAssertFalse(s.first { $0.category == "Grocery" }!.paceHot)
    }

    // MARK: pre-spend "can I afford this?"

    func testAffordFitsWithinBudget() {
        // $10 dining: 20 left → fits, 10 would remain.
        let c = SpendService.canAfford(amount: 10, category: "Dining", data: sampleData(), now: now, calendar: cal)
        XCTAssertFalse(c.breaksBudget)
        XCTAssertEqual(c.categoryLeftBefore!, 20, accuracy: 0.001)
    }

    func testAffordBreaksBudget() {
        // $50 dining: only 20 left → breaks.
        let c = SpendService.canAfford(amount: 50, category: "Dining", data: sampleData(), now: now, calendar: cal)
        XCTAssertTrue(c.breaksBudget)
        XCTAssertTrue(c.verdict.lowercased().contains("over budget"))
    }

    func testAffordGoalDelay() {
        // $420 spend = exactly one month of contribution → ~30 days later.
        let c = SpendService.canAfford(amount: 420, category: nil, data: sampleData(), now: now, calendar: cal)
        XCTAssertEqual(c.goalDelayDays!, 30)                     // 1.0 * 30.44 rounded
        XCTAssertEqual(c.goalFraction!, 420.0 / 5500.0, accuracy: 1e-6)
    }

    // MARK: scorecard verdict

    func testScorecardNamesTheLeak() {
        var d = sampleData()
        d.expenses.append(exp("2026-07-12", 120, "Dining")) // Dining now 400/300 → 100 over
        let sc = SpendService.scorecard(d, now: now, calendar: cal)
        XCTAssertEqual(sc.biggestLeakCategory, "Dining")
        XCTAssertEqual(sc.biggestLeakOver, 100, accuracy: 0.001)
        XCTAssertTrue(sc.verdict.contains("Dining"))
    }

    func testScorecardUnderBudgetIsCalm() {
        let sc = SpendService.scorecard(sampleData(), now: now, calendar: cal)
        // total spent 380 (280+60+40) < budgeted 700 → under
        XCTAssertNil(sc.biggestLeakCategory)
        XCTAssertTrue(sc.verdict.lowercased().contains("under budget"))
    }

    // MARK: streak

    func testUnderBudgetStreakCountsCalmDays() {
        // daily budget = 700/31 ≈ 22.6. With no spend on recent days, the streak
        // counts consecutive days ending "now" that are under that.
        let d = SpendData(expenses: [], budgets: sampleData().budgets, goal: nil)
        let streak = SpendService.underBudgetStreak(d, now: now, calendar: cal)
        XCTAssertGreaterThanOrEqual(streak, 1)
    }
}
