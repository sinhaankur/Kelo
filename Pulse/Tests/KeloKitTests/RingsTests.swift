import XCTest
@testable import KeloKit

final class RingsTests: XCTestCase {

    func testBodyRingEmptyWithoutData() {
        let r = Rings.body(movement: nil, trainedToday: false)
        XCTAssertEqual(r.fraction, 0)
        XCTAssertFalse(r.hasData)
    }

    func testBodyRingClosesWithStepsAndTraining() {
        let m = MovementDay(date: "d", steps: 8000, activeMinutes: 60)
        let noTrain = Rings.body(movement: m, trainedToday: false)
        let trained = Rings.body(movement: m, trainedToday: true)
        XCTAssertGreaterThan(trained.fraction, noTrain.fraction)   // training helps close it
        XCTAssertTrue(trained.label.contains("trained"))
    }

    func testMoneyRingFullOnPlanDrainsWhenOver() {
        let onPlan = Rings.money(spentThisMonth: 800, budgeted: 1000)
        let over = Rings.money(spentThisMonth: 1300, budgeted: 1000)
        XCTAssertGreaterThan(onPlan.fraction, over.fraction)
        XCTAssertEqual(onPlan.label, "on plan")
        XCTAssertTrue(over.label.contains("over"))
    }

    func testMoneyRingNeedsABudget() {
        XCTAssertFalse(Rings.money(spentThisMonth: 500, budgeted: 0).hasData)
    }

    func testDisciplineRingIsShareOfHabitsMetToday() {
        let streaks = [
            Streak(id: "a", title: "A", icon: "", current: 3, metToday: true),
            Streak(id: "b", title: "B", icon: "", current: 0, metToday: false),
            Streak(id: "c", title: "C", icon: "", current: 5, metToday: true),
        ]
        let r = Rings.discipline(streaks: streaks)
        XCTAssertEqual(r.fraction, 2.0/3.0, accuracy: 0.001)
        XCTAssertTrue(r.label.contains("2/3"))
        XCTAssertTrue(r.label.contains("5-day streak"))
    }

    func testAllThreeRingsBuild() {
        let rings = Rings.all(movement: MovementDay(date: "d", steps: 5000),
                              trainedToday: true, spentThisMonth: 500, budgeted: 1000,
                              streaks: [Streak(id: "a", title: "A", icon: "", current: 1, metToday: true)])
        XCTAssertEqual(rings.count, 3)
        XCTAssertEqual(rings.map(\.kind), [.body, .money, .discipline])
    }
}
