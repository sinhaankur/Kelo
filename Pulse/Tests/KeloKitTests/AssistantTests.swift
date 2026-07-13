import XCTest
@testable import KeloKit

/// These tests prove the assistant actually DOES what it intends — it grounds
/// in the user's real numbers, answers honestly with zero AI, and never passes
/// off a fake or empty model reply as a real one.
final class AssistantTests: XCTestCase {

    private func fullSnapshot() -> AssistantService.Snapshot {
        var s = AssistantService.Snapshot(currency: "CAD")
        s.dayStanding = "steady"
        s.dayHeadline = "solid but short on sleep"
        s.dayReasons = ["5.5h sleep — short; expect less patience", "trained today"]
        s.bodyRingLabel = "trained · 8,000 steps"; s.bodyRingFraction = 1.0
        s.moneyRingLabel = "over"; s.moneyRingFraction = 0.4
        s.disciplineRingLabel = "2 of 3 habits"; s.disciplineRingFraction = 0.66
        s.moodValence = 1
        s.spentThisMonth = 1300; s.budgetedThisMonth = 1000
        s.savingsFractionOfTarget = 0.42; s.savingsOnTrack = false
        s.portfolioValue = 52_000; s.portfolioDayChangePct = -0.8
        s.topHoldings = ["AAPL +2.1%", "MSFT -0.4%"]
        return s
    }

    // MARK: Grounding context contains ONLY real facts from the snapshot

    func testGroundingContextReflectsRealNumbers() {
        let ctx = AssistantService.groundingContext(fullSnapshot())
        XCTAssertTrue(ctx.contains("steady"))
        XCTAssertTrue(ctx.contains("5.5h sleep"))              // the real reason line
        XCTAssertTrue(ctx.contains("$1,300"))                 // real spend, CAD symbol
        XCTAssertTrue(ctx.contains("OVER by $300"))           // computed from real data
        XCTAssertTrue(ctx.contains("42% there"))              // savings fraction
        XCTAssertTrue(ctx.contains("$52,000"))                // portfolio value
        XCTAssertTrue(ctx.contains("AAPL +2.1%"))             // real holdings
    }

    func testGroundingOnlyStatesKnownFields() {
        var s = AssistantService.Snapshot()
        s.dayStanding = "strong"
        let ctx = AssistantService.groundingContext(s)
        XCTAssertTrue(ctx.contains("strong"))
        XCTAssertFalse(ctx.contains("Portfolio"))   // no portfolio → never mentioned
        XCTAssertFalse(ctx.contains("Spending"))    // no budget → never mentioned
    }

    func testEmptySnapshotSaysNothingRecorded() {
        let ctx = AssistantService.groundingContext(AssistantService.Snapshot())
        XCTAssertEqual(ctx, "No data has been recorded yet.")
    }

    // MARK: Deterministic local summary is a REAL answer, not a canned string

    func testLocalSummaryUsesRealSignals() {
        let text = AssistantService.localSummary(fullSnapshot())
        XCTAssertTrue(text.contains("steady"))
        XCTAssertTrue(text.contains("$300"))              // the real over-budget amount
        XCTAssertTrue(text.contains("42%"))               // the real savings fraction
        XCTAssertFalse(text.isEmpty)
    }

    func testLocalSummaryHonestWhenEmpty() {
        let text = AssistantService.localSummary(AssistantService.Snapshot())
        XCTAssertTrue(text.lowercased().contains("isn't enough logged")
            || text.lowercased().contains("log a mood"))
    }

    func testLocalSummaryDistinguishesOverVsUnderBudget() {
        var under = AssistantService.Snapshot(currency: "USD")
        under.spentThisMonth = 600; under.budgetedThisMonth = 1000
        XCTAssertTrue(AssistantService.localSummary(under).contains("under control"))

        var over = AssistantService.Snapshot(currency: "USD")
        over.spentThisMonth = 1200; over.budgetedThisMonth = 1000
        XCTAssertTrue(AssistantService.localSummary(over).lowercased().contains("over budget"))
    }

    // MARK: The full answer path — model vs honest fallback

    func testAnswerFallsBackToLocalWhenNoModel() async {
        let a = await AssistantService.answer(question: "How am I doing?",
                                              snapshot: fullSnapshot(), llm: nil)
        XCTAssertEqual(a.source, .localData)
        XCTAssertFalse(a.usedCloud)
        XCTAssertTrue(a.text.contains("steady"))
    }

    func testAnswerUsesModelReplyWhenAvailable() async {
        // A stub standing in for the on-device LLM — it must receive the REAL
        // brief (grounding) and its reply is surfaced as source .model.
        var receivedUser = ""
        let a = await AssistantService.answer(
            question: "Am I over budget?",
            snapshot: fullSnapshot(),
            llm: { _, user in
                receivedUser = user
                return "You're over your budget this month by $300."
            })
        XCTAssertEqual(a.source, .model)
        XCTAssertTrue(a.text.contains("$300"))
        // Proof it was actually grounded: the brief and question reached the model.
        XCTAssertTrue(receivedUser.contains("OVER by $300"))
        XCTAssertTrue(receivedUser.contains("Am I over budget?"))
    }

    func testEmptyModelReplyFallsBackNotFaked() async {
        // A model that returns whitespace must NOT be surfaced as a real answer.
        let a = await AssistantService.answer(question: "x",
                                              snapshot: fullSnapshot(),
                                              llm: { _, _ in "   \n  " })
        XCTAssertEqual(a.source, .localData)
        XCTAssertFalse(a.text.isEmpty)
    }

    func testModelErrorFallsBackGracefully() async {
        struct Boom: Error {}
        let a = await AssistantService.answer(question: "x",
                                              snapshot: fullSnapshot(),
                                              llm: { _, _ in throw Boom() })
        XCTAssertEqual(a.source, .localData)   // never breaks the feature
        XCTAssertFalse(a.text.isEmpty)
    }

    func testCloudFlagIsHonestlyPropagated() async {
        let a = await AssistantService.answer(question: "x",
                                              snapshot: fullSnapshot(),
                                              llm: { _, _ in "ok" },
                                              usedCloud: true)
        XCTAssertTrue(a.usedCloud)   // the UI can warn that data left the device
    }
}
