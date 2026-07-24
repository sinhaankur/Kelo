import Foundation

// MARK: - Obsidian vault link (Kelo's "memory and brain")
//
// Kelo connects to an Obsidian vault two ways, with a hard boundary between them:
//
//   READ  — the user's own per-ticker notes (filename = ticker, `NVDA.md`).
//           Strictly read-only: Kelo shows your note on that ticker, never edits it.
//   WRITE — Kelo's own feeds (Congress moves + news) go ONLY into a dedicated
//           `Kelo Feeds/` subfolder, one note per ticker. Kelo never writes
//           anywhere else in the vault, so your authored notes are never touched.
//
// This is the accumulating knowledge layer — the "shows its knowledge" half of
// the vault-graph idea. It's opt-in: nothing happens unless `obsidianVaultPath`
// is set in config.json. Every note Kelo writes says, in its own text, that Kelo
// generated it and that the disclosures are backward-looking, not a signal.

public enum VaultService {
    /// The folder Kelo owns for its generated notes. Nothing outside this is
    /// ever written.
    public static let feedFolderName = "Kelo Feeds"

    // MARK: resolve the vault (opt-in)

    /// The configured vault root, `~`-expanded, or nil when the integration is
    /// off (no path set) or the path doesn't exist.
    public static func vaultRoot(config: AppConfig) -> URL? {
        guard let raw = config.obsidianVaultPath?.trimmingCharacters(in: .whitespaces),
              !raw.isEmpty else { return nil }
        let expanded = (raw as NSString).expandingTildeInPath
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: expanded, isDirectory: &isDir),
              isDir.boolValue else { return nil }
        return URL(fileURLWithPath: expanded, isDirectory: true)
    }

    public static var isEnabled: Bool { vaultRoot(config: AppConfig.load()) != nil }

    // MARK: READ — the user's own notes (read-only)

    /// The user's own note for a ticker, if one exists (`<TICKER>.md`, matched
    /// case-insensitively, searched recursively so it can live in any folder).
    /// Kelo only ever reads this — it is never modified. nil = no note / no vault.
    public static func userNote(ticker: String, config: AppConfig = .load()) -> String? {
        guard let root = vaultRoot(config: config) else { return nil }
        let target = ticker.trimmingCharacters(in: .whitespaces).uppercased()
        guard !target.isEmpty else { return nil }
        // Skip our own feed folder so a feed note never masquerades as the
        // user's authored note.
        let feedDir = root.appendingPathComponent(feedFolderName).standardizedFileURL.path
        let fm = FileManager.default
        guard let en = fm.enumerator(at: root, includingPropertiesForKeys: nil) else { return nil }
        for case let url as URL in en {
            guard url.pathExtension.lowercased() == "md" else { continue }
            if url.standardizedFileURL.path.hasPrefix(feedDir) { continue }
            let base = url.deletingPathExtension().lastPathComponent.uppercased()
            if base == target {
                return try? String(contentsOf: url, encoding: .utf8)
            }
        }
        return nil
    }

    // MARK: WRITE — Kelo's own feed notes (only into Kelo Feeds/)

    /// Write (overwrite) the Kelo feed note for a ticker into `Kelo Feeds/`.
    /// Returns the file URL on success. No-op returning nil when the vault is
    /// off. NEVER writes outside the feed folder.
    @discardableResult
    public static func writeFeedNote(ticker: String, markdown: String,
                                     config: AppConfig = .load()) -> URL? {
        guard let root = vaultRoot(config: config) else { return nil }
        let safeTicker = sanitizeTicker(ticker)
        guard !safeTicker.isEmpty else { return nil }
        let dir = root.appendingPathComponent(feedFolderName, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("\(safeTicker).md")
        // Final guard: the resolved path must stay inside the feed folder.
        guard file.standardizedFileURL.path.hasPrefix(dir.standardizedFileURL.path) else { return nil }
        do {
            try markdown.write(to: file, atomically: true, encoding: .utf8)
            return file
        } catch { return nil }
    }

    /// A ticker reduced to a safe filename stem — no path separators can escape
    /// the feed folder.
    public static func sanitizeTicker(_ ticker: String) -> String {
        ticker.uppercased().unicodeScalars.filter {
            CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-").contains($0)
        }.map(String.init).joined()
    }

    // MARK: note content (PURE — unit-tested, no filesystem)

    /// Render the markdown for a ticker's Kelo feed note from its Congress moves
    /// and news headlines. Honest by construction: it states it's Kelo-generated,
    /// that disclosures lag and are ranges, and links every filing. Deterministic
    /// for a given input so re-runs don't churn the vault needlessly.
    public static func feedNoteMarkdown(ticker: String,
                                        trades: [CongressTrade],
                                        headlines: [GlobalSentiment.Headline],
                                        generatedAt: Date = Date()) -> String {
        var s = "---\nkelo_generated: true\nticker: \(ticker.uppercased())\n---\n\n"
        s += "# \(ticker.uppercased()) — Kelo feed\n\n"
        s += "> Auto-generated by Kelo. This is a research/transparency record, "
        s += "not financial advice. Congress disclosures are filed 30–45+ days "
        s += "after the trade and amounts are ranges — backward-looking, not a signal.\n\n"

        let mine = trades.filter { $0.ticker.uppercased() == ticker.uppercased() && $0.isEquity }
        s += "## Congress disclosures\n\n"
        if mine.isEmpty {
            s += "_No disclosed Congressional trades for this ticker in the recent feed._\n\n"
        } else {
            s += "| Member | Action | Amount | Filed (lag) | Since |\n"
            s += "|---|---|---|---|---|\n"
            for t in mine.prefix(20) {
                let action = t.kind.rawValue.uppercased()
                let amount = t.amountLabel ?? "—"
                let lag = t.disclosureLagDays.map { "\($0)d" } ?? "—"
                let since = t.returnSince.map { String(format: "%+.0f%%", $0 * 100) } ?? "—"
                let member = t.docURL.map { "[\(t.filerName)](\($0))" } ?? t.filerName
                s += "| \(member) | \(action) | \(amount) | \(t.filingDate ?? "—") (\(lag)) | \(since) |\n"
            }
            s += "\n"
        }

        s += "## Recent news\n\n"
        if headlines.isEmpty {
            s += "_No recent headlines captured._\n\n"
        } else {
            for h in headlines.prefix(15) {
                s += "- \(h.title) — _\(h.source)_\n"
            }
            s += "\n"
        }

        s += "---\n_Updated \(isoDateString(generatedAt)) by Kelo._\n"
        return s
    }
}
