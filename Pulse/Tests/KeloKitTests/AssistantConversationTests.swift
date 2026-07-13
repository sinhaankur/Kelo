import XCTest
@testable import KeloKit

/// Proves the follow-up conversation + user-notes features actually work:
/// notes reach the grounding brief, prior turns reach the model prompt, the
/// history window is bounded, and the on-device note store round-trips.
final class AssistantConversationTests: XCTestCase {

    // MARK: Notes → grounding

    func testNotesAppearInGroundingBrief() {
        var s = AssistantService.Snapshot(currency: "USD")
        s.dayStanding = "steady"
        s.notes = ["cutting dining out", "bullish on AAPL — new cycle"]
        let ctx = AssistantService.groundingContext(s)
        XCTAssertTrue(ctx.contains("Your notes"))
        XCTAssertTrue(ctx.contains("cutting dining out"))
        XCTAssertTrue(ctx.contains("bullish on AAPL"))
    }

    func testNoNotesLineWhenEmpty() {
        var s = AssistantService.Snapshot()
        s.dayStanding = "strong"
        XCTAssertFalse(AssistantService.groundingContext(s).contains("Your notes"))
    }

    // MARK: Conversation history → model prompt

    func testHistoryIsFoldedIntoThePrompt() async {
        var receivedUser = ""
        let history = [
            AssistantService.Turn(role: .user, text: "How am I doing?"),
            AssistantService.Turn(role: .assistant, text: "You're steady today."),
        ]
        var snap = AssistantService.Snapshot(currency: "USD")
        snap.dayStanding = "steady"

        _ = await AssistantService.answer(
            question: "And my spending?",
            snapshot: snap,
            history: history,
            llm: { _, user in receivedUser = user; return "Spending looks fine." }
        )
        // The prior turns + the new question all reached the model.
        XCTAssertTrue(receivedUser.contains("Our conversation so far"))
        XCTAssertTrue(receivedUser.contains("How am I doing?"))
        XCTAssertTrue(receivedUser.contains("You're steady today."))
        XCTAssertTrue(receivedUser.contains("And my spending?"))
    }

    func testHistoryWindowIsBounded() async {
        var receivedUser = ""
        // More turns than the window — only the last `historyWindow` are carried.
        let many = (1...20).map { AssistantService.Turn(role: .user, text: "turn-\($0)") }
        _ = await AssistantService.answer(
            question: "now",
            snapshot: AssistantService.Snapshot(),
            history: many,
            llm: { _, user in receivedUser = user; return "ok" }
        )
        XCTAssertFalse(receivedUser.contains("turn-1\n"))   // oldest dropped
        XCTAssertTrue(receivedUser.contains("turn-20"))     // newest kept
    }

    func testEmptyHistoryOmitsConversationBlock() async {
        var receivedUser = ""
        _ = await AssistantService.answer(
            question: "hi", snapshot: AssistantService.Snapshot(),
            history: [], llm: { _, user in receivedUser = user; return "ok" })
        XCTAssertFalse(receivedUser.contains("Our conversation so far"))
    }

    // MARK: Note store round-trip (on-device file)

    func testNoteStoreAddRemoveAndContextLines() {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("notes-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: tmp) }

        XCTAssertTrue(NoteStore.load(from: tmp).isEmpty)
        _ = NoteStore.add("cutting dining", to: tmp)
        _ = NoteStore.add("bullish on AAPL", to: tmp)
        let all = NoteStore.load(from: tmp)
        XCTAssertEqual(all.count, 2)
        XCTAssertEqual(all.first?.text, "bullish on AAPL")   // newest first

        // Blank notes are ignored.
        _ = NoteStore.add("   ", to: tmp)
        XCTAssertEqual(NoteStore.load(from: tmp).count, 2)

        // Remove by id.
        let removed = NoteStore.remove(id: all.first!.id, from: tmp)
        XCTAssertEqual(removed.count, 1)
        XCTAssertEqual(removed.first?.text, "cutting dining")
    }

    func testContextLinesRespectLimit() {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("notes-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: tmp) }
        for i in 1...10 { _ = NoteStore.add("note \(i)", to: tmp) }
        XCTAssertEqual(NoteStore.contextLines(from: tmp).count, NoteStore.contextLimit)
    }
}
