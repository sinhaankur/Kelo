import XCTest
@testable import KeloKit

final class DisciplineTests: XCTestCase {
    private let cal = Calendar.current
    private func day(_ offset: Int) -> String {
        isoDateString(cal.date(byAdding: .day, value: offset, to: Date())!)
    }

    func testStreakCountsConsecutiveDaysEndingToday() {
        let met = [day(0): true, day(-1): true, day(-2): true, day(-4): true]
        let r = Discipline.streak(metByDay: met)
        XCTAssertEqual(r.current, 3)     // today, -1, -2 (gap at -3 stops it)
        XCTAssertTrue(r.metToday)
    }

    // An unfinished today must NOT zero a real streak — it counts from yesterday.
    func testUnfinishedTodayKeepsStreakAlive() {
        let met = [day(-1): true, day(-2): true, day(-3): true]  // today absent
        let r = Discipline.streak(metByDay: met)
        XCTAssertEqual(r.current, 3)
        XCTAssertFalse(r.metToday)
    }

    func testBrokenStreakIsZero() {
        let met = [day(-2): true, day(-3): true]  // neither today nor yesterday
        let r = Discipline.streak(metByDay: met)
        XCTAssertEqual(r.current, 0)
    }

    func testStreaksDerivedFromHealthAndMood() {
        let days = [
            HealthDay(date: day(-1), sleepHours: 8, sessions: [
                TrainingSession(kind: "Run", minutes: 30, rpe: 6)]),
            HealthDay(date: day(0), sleepHours: 7.5, sessions: [
                TrainingSession(kind: "Lift", minutes: 45, rpe: 7)]),
        ]
        let mood = [MoodEntry(date: day(0), mood: 4)]
        let streaks = Discipline.streaks(health: HealthData(days: days), mood: mood)
        XCTAssertEqual(streaks.first { $0.id == "trained" }?.current, 2)
        XCTAssertEqual(streaks.first { $0.id == "slept" }?.current, 2)
        XCTAssertEqual(streaks.first { $0.id == "logged" }?.current, 1)
    }

    // Mood clamps to 1...5 and labels/emoji stay in range.
    func testMoodClamped() {
        XCTAssertEqual(MoodEntry(date: "d", mood: 9).mood, 5)
        XCTAssertEqual(MoodEntry(date: "d", mood: 0).mood, 1)
        XCTAssertEqual(MoodEntry(date: "d", mood: 3).label, "Okay")
    }

    // Mood feeds the composite: a low mood is a drag reason.
    func testLowMoodIsADragInDayState() {
        let s = DayState(.init(today: HealthDay(date: "d", sleepHours: 7.5), mood: 1))
        XCTAssertTrue(s.reasons.contains { !$0.good && $0.text.lowercased().contains("mood") })
    }
}
