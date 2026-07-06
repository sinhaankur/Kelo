import XCTest
@testable import PulseKit

final class DayStateTests: XCTestCase {

    // A day with fewer than two real signals must not pretend to have a
    // verdict — it invites the user to log instead.
    func testThinDataAsksToLog() {
        let s = DayState(.init())
        XCTAssertTrue(s.thin)
        XCTAssertEqual(s.standing, .steady)
        XCTAssertTrue(s.reasons.isEmpty)
    }

    // Good sleep + a green portfolio day + under-budget spending → strong.
    func testConvergingTailwindsReadStrong() {
        let today = HealthDay(date: "2026-07-06", sleepHours: 8.0, readiness: 8)
        let s = DayState(.init(today: today,
                               portfolioDayFraction: 0.012,
                               spendVsBudget: 0.7))
        XCTAssertEqual(s.standing, .strong)
        XCTAssertFalse(s.thin)
        XCTAssertTrue(s.reasons.contains { $0.good })
    }

    // Short sleep + low energy + a sharp red day + over budget → strained.
    func testConvergingDragsReadStrained() {
        let today = HealthDay(date: "2026-07-06", sleepHours: 5.0, readiness: 3)
        let s = DayState(.init(today: today,
                               portfolioDayFraction: -0.02,
                               spendVsBudget: 1.2))
        XCTAssertEqual(s.standing, .strained)
        XCTAssertTrue(s.reasons.contains { !$0.good })
    }

    // Resting HR is only judged AGAINST a baseline — with no baseline it must
    // be omitted from the reasoning entirely, never guessed.
    func testRestingHRIgnoredWithoutBaseline() {
        let today = HealthDay(date: "2026-07-06", sleepHours: 7.5, restingHR: 70)
        let s = DayState(.init(today: today, restingHRBaseline: nil,
                               portfolioDayFraction: 0.0))
        XCTAssertFalse(s.reasons.contains { $0.text.lowercased().contains("resting hr") })
    }

    // A resting HR below the user's own baseline is a recovery tailwind.
    func testRestingHRBelowBaselineIsGood() {
        let today = HealthDay(date: "2026-07-06", restingHR: 50, readiness: 7)
        let s = DayState(.init(today: today, restingHRBaseline: 55))
        XCTAssertTrue(s.reasons.contains { $0.good && $0.text.lowercased().contains("recovered") })
    }

    // A rest day after a heavy training week reads as earned recovery, not a
    // gap in the data.
    func testRestDayAfterHeavyWeekIsEarnedRecovery() {
        let today = HealthDay(date: "2026-07-06", sleepHours: 8, sessions: [])
        let s = DayState(.init(today: today, recentLoad: 2000, portfolioDayFraction: 0.0))
        XCTAssertTrue(s.reasons.contains { $0.text.lowercased().contains("recovery") })
    }

    // Training load math: minutes × RPE, summed across sessions.
    func testTrainingLoadIsMinutesTimesRPE() {
        let day = HealthDay(date: "2026-07-06", sessions: [
            TrainingSession(kind: "CrossFit", minutes: 60, rpe: 8),   // 480
            TrainingSession(kind: "Row", minutes: 20, rpe: 3),         // 60
        ])
        XCTAssertEqual(day.trainingLoad, 540)
        XCTAssertTrue(day.didTrain)
    }

    // RPE is clamped to 1...10 so a fat-fingered entry can't skew load.
    func testRPEClamped() {
        XCTAssertEqual(TrainingSession(kind: "Lift", minutes: 30, rpe: 99).rpe, 10)
        XCTAssertEqual(TrainingSession(kind: "Lift", minutes: 30, rpe: -4).rpe, 1)
    }

    // Baseline needs at least three logged resting-HR values to be honest.
    func testBaselineNeedsEnoughHistory() throws {
        let two = HealthData(days: [
            HealthDay(date: "2026-07-01", restingHR: 54),
            HealthDay(date: "2026-07-02", restingHR: 56),
        ])
        XCTAssertNil(two.restingHRBaseline())

        let three = HealthData(days: two.days + [HealthDay(date: "2026-07-03", restingHR: 55)])
        let baseline = try XCTUnwrap(three.restingHRBaseline())
        XCTAssertEqual(baseline, 55, accuracy: 0.01)
    }
}
