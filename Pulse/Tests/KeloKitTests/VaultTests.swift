import XCTest
@testable import KeloKit

final class VaultNoteFormatTests: XCTestCase {
    private func trade(_ ticker: String, _ kind: CongressTrade.Kind, ret: Double?) -> CongressTrade {
        CongressTrade(id: "\(ticker)-\(kind)", filerName: "Jane Doe", chamber: .senate,
                      party: "R", state: "TX", office: nil, ticker: ticker, assetName: nil,
                      kind: kind, amountLow: 1001, amountHigh: 15000,
                      amountLabel: "$1,001 - $15,000", transactionDate: "2026-05-01",
                      filingDate: "2026-06-10", disclosureLagDays: 40,
                      docURL: "https://example.gov/f.pdf", returnSince: ret, excessSince: nil)
    }

    func testNoteIsHonestAndSelfLabelled() {
        let md = VaultService.feedNoteMarkdown(
            ticker: "nvda",
            trades: [trade("NVDA", .buy, ret: 0.25)],
            headlines: [.init(title: "Chip demand strong", source: "Reuters", date: Date())])
        XCTAssertTrue(md.contains("kelo_generated: true"))     // machine-detectable it's ours
        XCTAssertTrue(md.contains("ticker: NVDA"))             // uppercased
        XCTAssertTrue(md.contains("not financial advice"))
        XCTAssertTrue(md.contains("backward-looking, not a signal"))
        XCTAssertTrue(md.contains("Jane Doe"))
        XCTAssertTrue(md.contains("+25%"))                     // the return renders
        XCTAssertTrue(md.contains("Chip demand strong"))
    }

    func testNoteFiltersToTheTickerAndHandlesEmpty() {
        let md = VaultService.feedNoteMarkdown(
            ticker: "AAPL",
            trades: [trade("NVDA", .buy, ret: 0.1)],   // different ticker
            headlines: [])
        XCTAssertFalse(md.contains("Jane Doe"))               // NVDA row excluded
        XCTAssertTrue(md.contains("No disclosed Congressional trades"))
        XCTAssertTrue(md.contains("No recent headlines"))
    }

    func testSanitizeTickerBlocksPathEscape() {
        XCTAssertEqual(VaultService.sanitizeTicker("NVDA"), "NVDA")
        XCTAssertEqual(VaultService.sanitizeTicker("brk.b"), "BRK.B") // dots kept (BRK.B is real)
        // The security property: no path separators ever survive, so the stem
        // cannot escape the feed folder — regardless of the dots.
        for evil in ["../../etc/passwd", "a/b", "..\\..\\win", "foo/../bar"] {
            let out = VaultService.sanitizeTicker(evil)
            XCTAssertFalse(out.contains("/"), "slash survived in \(out)")
            XCTAssertFalse(out.contains("\\"), "backslash survived in \(out)")
        }
    }
}

final class VaultFilesystemTests: XCTestCase {
    private var vault: URL!

    override func setUpWithError() throws {
        vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("kelo-vault-test-\(UUID())")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: vault)
    }

    private func config() -> AppConfig {
        AppConfig(obsidianVaultPath: vault.path)
    }

    func testDisabledWhenNoPath() {
        XCTAssertNil(VaultService.vaultRoot(config: AppConfig()))
        XCTAssertNil(VaultService.userNote(ticker: "NVDA", config: AppConfig()))
        XCTAssertNil(VaultService.writeFeedNote(ticker: "NVDA", markdown: "x", config: AppConfig()))
    }

    func testReadsUserNoteButNeverModifiesIt() throws {
        let note = vault.appendingPathComponent("NVDA.md")
        let original = "# My NVDA thesis\nStrong moat."
        try original.write(to: note, atomically: true, encoding: .utf8)

        let read = VaultService.userNote(ticker: "nvda", config: config()) // case-insensitive
        XCTAssertEqual(read, original)
        // The file on disk is byte-for-byte unchanged after a read.
        XCTAssertEqual(try String(contentsOf: note, encoding: .utf8), original)
    }

    func testWritesOnlyIntoKeloFeedsFolder() throws {
        let url = VaultService.writeFeedNote(ticker: "NVDA", markdown: "# feed", config: config())
        let unwrapped = try XCTUnwrap(url)
        // Landed inside Kelo Feeds/, nowhere else.
        XCTAssertEqual(unwrapped.deletingLastPathComponent().lastPathComponent, VaultService.feedFolderName)
        XCTAssertEqual(unwrapped.lastPathComponent, "NVDA.md")
        XCTAssertEqual(try String(contentsOf: unwrapped, encoding: .utf8), "# feed")
    }

    func testUserNoteIgnoresKeloFeedsFolder() throws {
        // A feed note Kelo wrote must NOT be returned as the user's authored note.
        VaultService.writeFeedNote(ticker: "TSLA", markdown: "# kelo feed", config: config())
        XCTAssertNil(VaultService.userNote(ticker: "TSLA", config: config()))
        // But a real user note with the same name IS found.
        let real = vault.appendingPathComponent("TSLA.md")
        try "my tsla note".write(to: real, atomically: true, encoding: .utf8)
        XCTAssertEqual(VaultService.userNote(ticker: "TSLA", config: config()), "my tsla note")
    }
}
