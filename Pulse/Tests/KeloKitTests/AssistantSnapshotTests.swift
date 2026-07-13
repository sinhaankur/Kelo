import XCTest
@testable import KeloKit

/// Proves the assistant is wired to REAL app data — the snapshot builder reads
/// the actual stores/domain services, not hand-fed values, so the assistant
/// grounds in what Kelo genuinely knows.
final class AssistantSnapshotTests: XCTestCase {

    private func today() -> String { isoDateString(Date()) }

    func testSnapshotFromStoresGroundsInRealSpend() {
        let spend = SpendData(
            expenses: [
                Expense(date: today(), amount: 1300, category: "Dining"),
            ],
            budgets: [Budget(category: "Dining", limit: 1000)]
        )
        let health = HealthData(days: [
            HealthDay(date: today(), sleepHours: 5.5, restingHR: nil, readiness: nil),
        ])
        let profile = Profile(age: 30, gender: .male, annualSalary: 80_000, country: .canada)

        let snap = AssistantService.Snapshot.fromStores(
            health: health,
            movement: MovementDay(date: today(), steps: 8000, activeMinutes: 60),
            spend: spend,
            moodEntry: MoodEntry(date: today(), mood: 4),
            profile: profile,
            currency: "CAD",
            currentSaved: 20_000
        )

        // Real spend flowed through
        XCTAssertEqual(snap.spentThisMonth, 1300)
        XCTAssertEqual(snap.budgetedThisMonth, 1000)
        // Mood 4/5 → valence +1
        XCTAssertEqual(snap.moodValence, 1)
        // Savings benchmark computed against a real profile+target
        XCTAssertNotNil(snap.savingsFractionOfTarget)
        // Day-state produced a standing from real signals
        XCTAssertNotNil(snap.dayStanding)

        // And the grounding brief reflects those real numbers.
        let ctx = AssistantService.groundingContext(snap)
        XCTAssertTrue(ctx.contains("$1,300"))
        XCTAssertTrue(ctx.contains("OVER by $300"))
    }

    func testSnapshotOmitsPortfolioWhenNoQuotes() {
        // Without live quotes the assistant must NOT mention a portfolio.
        let snap = AssistantService.Snapshot.fromStores(
            health: HealthData(days: []),
            movement: nil,
            spend: SpendData(),
            moodEntry: nil,
            profile: Profile()
        )
        XCTAssertNil(snap.portfolioValue)
        XCTAssertTrue(snap.topHoldings.isEmpty)
        let ctx = AssistantService.groundingContext(snap)
        XCTAssertFalse(ctx.contains("Portfolio"))
    }

    func testSnapshotIncludesPortfolioWhenProvided() {
        let snap = AssistantService.Snapshot.fromStores(
            spend: SpendData(),
            profile: Profile(),
            currency: "USD",
            portfolioValue: 52_000,
            portfolioDayChangePct: -0.8,
            topHoldings: ["AAPL +2.1%"]
        )
        XCTAssertEqual(snap.portfolioValue, 52_000)
        let ctx = AssistantService.groundingContext(snap)
        XCTAssertTrue(ctx.contains("$52,000"))
        XCTAssertTrue(ctx.contains("AAPL +2.1%"))
    }
}
