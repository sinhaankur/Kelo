import Foundation

/// The Kelo Assistant — an opt-in "how am I doing?" answer grounded in the
/// user's OWN real data (day-state, rings, savings benchmark, holdings).
///
/// Design (honest by construction — it must actually do what it says):
///  1. `groundingContext` assembles a FACTUAL brief from Kelo's real computed
///     numbers. No invention: every line is a value Kelo already derived.
///  2. `localSummary` answers the question deterministically from that brief.
///     This is the zero-AI path — the feature fully works with no model
///     running, so the assistant is never a hollow shell returning canned text.
///  3. `answer` is the full path: build the brief, then either ask the on-device
///     LLM (real call via `LlmService`, with a system prompt that FORBIDS
///     inventing numbers) or fall back to `localSummary`. The result says which
///     path produced it, so the UI can be honest about whether a model spoke.
///
/// OpenAlice's good idea borrowed here: everything is grounded in tracked, real
/// state and the model only ever INTERPRETS it — the numbers come from Kelo,
/// not the model. (No autonomous action; this only reads + explains.)
public enum AssistantService {

    /// A snapshot of the user's life, in real numbers, that the assistant reads.
    /// Every field is optional so the brief only ever states what's KNOWN.
    public struct Snapshot {
        public var dayStanding: String?          // "strong" | "steady" | "strained"
        public var dayHeadline: String?
        public var dayReasons: [String] = []     // the real DayState reason lines
        public var bodyRingLabel: String?        // e.g. "trained · 8,000 steps"
        public var bodyRingFraction: Double?
        public var moneyRingLabel: String?
        public var moneyRingFraction: Double?
        public var disciplineRingLabel: String?
        public var disciplineRingFraction: Double?
        public var moodValence: Int?             // -2…+2, if logged
        public var spentThisMonth: Double?
        public var budgetedThisMonth: Double?
        public var savingsFractionOfTarget: Double?  // Benchmark.fractionOfTarget
        public var savingsOnTrack: Bool?
        public var portfolioValue: Double?
        public var portfolioDayChangePct: Double?
        public var topHoldings: [String] = []    // e.g. ["AAPL +2.1%", "MSFT −0.4%"]
        /// User-authored notes / theses (the OpenAlice "tracked entities" idea) —
        /// short lines the person wrote themselves ("cutting dining", "bullish on
        /// AAPL"). The assistant reads them as context, never as fact it invented.
        public var notes: [String] = []
        public var currency: String

        public init(currency: String = "USD") { self.currency = currency }
    }

    public enum Source: String { case model, localData }

    /// One prior exchange, for follow-up questions ("and my spending?"). Kept
    /// small — only the last few turns are carried so context stays cheap.
    public struct Turn {
        public enum Role: String { case user, assistant }
        public let role: Role
        public let text: String
        public init(role: Role, text: String) { self.role = role; self.text = text }
    }

    public struct Answer {
        public let text: String
        public let source: Source
        /// True when the answer left the device (cloud model). The UI must say so.
        public let usedCloud: Bool
        public init(text: String, source: Source, usedCloud: Bool) {
            self.text = text; self.source = source; self.usedCloud = usedCloud
        }
    }

    // MARK: - Grounding

    /// Build the factual brief the model reads (or the local summary formats).
    /// Deterministic + pure → fully testable. One fact per line, plain numbers.
    public static func groundingContext(_ s: Snapshot) -> String {
        var lines: [String] = []
        let cur = s.currency

        if let st = s.dayStanding {
            lines.append("Day standing: \(st)\(s.dayHeadline.map { " — \($0)" } ?? "").")
        }
        for r in s.dayReasons { lines.append("• \(r)") }

        func ring(_ name: String, _ label: String?, _ frac: Double?) {
            guard let label else { return }
            let pctStr = frac.map { " (\(Int(($0 * 100).rounded()))% closed)" } ?? ""
            lines.append("\(name) ring: \(label)\(pctStr).")
        }
        ring("Body", s.bodyRingLabel, s.bodyRingFraction)
        ring("Money", s.moneyRingLabel, s.moneyRingFraction)
        ring("Discipline", s.disciplineRingLabel, s.disciplineRingFraction)

        if let mood = s.moodValence {
            let word = ["low", "down", "neutral", "good", "great"][max(0, min(4, mood + 2))]
            lines.append("Mood logged: \(word).")
        }

        if let spent = s.spentThisMonth, let bud = s.budgetedThisMonth, bud > 0 {
            let over = spent > bud
            lines.append("Spending this month: \(money(spent, cur)) of \(money(bud, cur)) budget — \(over ? "OVER by \(money(spent - bud, cur))" : "\(money(bud - spent, cur)) left").")
        }

        if let frac = s.savingsFractionOfTarget {
            let onTrack = s.savingsOnTrack ?? (frac >= 0.9)
            lines.append("Savings vs your nest-egg target: \(Int((frac * 100).rounded()))% there — \(onTrack ? "on track" : "behind").")
        }

        if let val = s.portfolioValue {
            let day = s.portfolioDayChangePct.map { " (today \(signedPct($0)))" } ?? ""
            lines.append("Portfolio value: \(money(val, cur))\(day).")
        }
        if !s.topHoldings.isEmpty {
            lines.append("Holdings: \(s.topHoldings.joined(separator: ", ")).")
        }

        // User-authored notes — clearly framed as THEIR words, not facts.
        if !s.notes.isEmpty {
            lines.append("Your notes (things you told me):")
            for n in s.notes { lines.append("  – \(n)") }
        }

        return lines.isEmpty
            ? "No data has been recorded yet."
            : lines.joined(separator: "\n")
    }

    // MARK: - Deterministic answer (zero-AI path)

    /// Per-domain sentences from the snapshot — the building blocks the
    /// deterministic answers are assembled from. Each returns [] when unknown.
    private static func standingPart(_ s: Snapshot) -> [String] {
        switch s.dayStanding {
        case "strong": return ["You're having a strong day."]
        case "strained": return ["Today's a strained one — go easier on yourself."]
        case "steady": return ["You're steady today."]
        default: return []
        }
    }
    private static func bodyPart(_ s: Snapshot) -> [String] {
        guard let bf = s.bodyRingFraction else { return [] }
        if bf >= 1 { return ["Your body ring is closed — movement's handled."] }
        if bf >= 0.5 { return ["You're partway on movement; a walk would close the body ring."] }
        if bf > 0 { return ["Movement is light so far today."] }
        return []
    }
    private static func budgetPart(_ s: Snapshot) -> [String] {
        guard let spent = s.spentThisMonth, let bud = s.budgetedThisMonth, bud > 0 else { return [] }
        return spent > bud
            ? ["You're over budget this month by \(money(spent - bud, s.currency))."]
            : ["Spending's under control — \(money(bud - spent, s.currency)) left in the budget."]
    }
    private static func savingsPart(_ s: Snapshot) -> [String] {
        guard let frac = s.savingsFractionOfTarget else { return [] }
        let p = Int((frac * 100).rounded())
        if frac >= 0.9 { return ["Your savings are on track — about \(p)% of your target."] }
        if frac >= 0.5 { return ["You're about \(p)% of the way to your nest-egg target — keep adding."] }
        return ["Savings are early — \(p)% of your target; the gap is the thing to chip at."]
    }
    private static func portfolioPart(_ s: Snapshot) -> [String] {
        guard let val = s.portfolioValue else { return [] }
        let day = s.portfolioDayChangePct.map { " (\(signedPct($0)) today)" } ?? ""
        var out = ["Your portfolio is worth \(money(val, s.currency))\(day)."]
        if !s.topHoldings.isEmpty { out.append("Biggest positions: \(s.topHoldings.joined(separator: ", ")).") }
        return out
    }
    private static func disciplinePart(_ s: Snapshot) -> [String] {
        guard let df = s.disciplineRingFraction else { return [] }
        if df >= 1 { return ["Every habit's met today — discipline ring closed."] }
        if df > 0 { return ["Some habits done, some open — the discipline ring isn't closed yet."] }
        return []
    }

    /// A real, plain-language WHOLE-DAY answer built ONLY from the snapshot — no
    /// model. This is the honest baseline: with nothing running, it still tells
    /// you where you stand, using your actual numbers.
    public static func localSummary(_ s: Snapshot) -> String {
        let parts = standingPart(s) + bodyPart(s) + budgetPart(s) + savingsPart(s) + disciplinePart(s)
        if parts.isEmpty {
            return "There isn't enough logged yet to read your day. Log a mood, connect Health, or add a budget and I'll have something real to tell you."
        }
        return parts.joined(separator: " ")
    }

    /// A deterministic answer that actually ADDRESSES the question when the model
    /// isn't available — so "am I over budget?" gets the budget line, not the
    /// whole-day wall. Falls back to the full summary for open-ended asks.
    public static func localAnswer(question: String, snapshot s: Snapshot) -> String {
        let q = question.lowercased()
        func has(_ words: [String]) -> Bool { words.contains { q.contains($0) } }

        var picked: [String] = []
        if has(["budget", "spend", "spent", "overspend"]) { picked += budgetPart(s) }
        if has(["save", "saving", "savings", "nest", "retire", "target"]) { picked += savingsPart(s) }
        if has(["portfolio", "stock", "holding", "invest", "market", "position"]) { picked += portfolioPart(s) }
        if has(["move", "movement", "walk", "step", "exercise", "train", "workout", "body", "fitness"]) { picked += bodyPart(s) }
        if has(["habit", "streak", "discipline", "consistent"]) { picked += disciplinePart(s) }

        if !picked.isEmpty { return picked.joined(separator: " ") }
        // No clear intent → the whole-day read.
        return localSummary(s)
    }

    // MARK: - Full answer (model when available, honest fallback otherwise)

    /// The system prompt that keeps the model HONEST: interpret the brief, never
    /// invent numbers, no financial advice, plain and kind.
    public static let systemPrompt = """
    You are Kelo, a private assistant that helps one person understand their own \
    health and money. You are given a factual brief of THIS person's real, current \
    data. Answer their question using ONLY the facts in the brief. Never invent \
    numbers, prices, or trends that aren't stated. If the brief lacks something, \
    say it isn't recorded rather than guessing. Be concise, concrete, and kind. \
    Do not give financial or medical advice or predictions; describe what the \
    numbers show and what would move them. Refer to the person as "you".
    """

    /// The number of prior turns carried into a follow-up (keeps context cheap).
    public static let historyWindow = 6

    /// Answer a question. If `llm` is provided it's called for real; otherwise
    /// (or on any error) the deterministic local summary is returned. The
    /// caller decides whether a model is configured — Kelo works with none.
    ///
    /// `history` carries prior turns so follow-ups ("and my spending?") have
    /// context. Only the last `historyWindow` turns are used.
    public static func answer(
        question: String,
        snapshot: Snapshot,
        history: [Turn] = [],
        llm: ((_ system: String, _ user: String) async throws -> String)? = nil,
        usedCloud: Bool = false
    ) async -> Answer {
        let brief = groundingContext(snapshot)
        guard let llm else {
            // No model → a deterministic answer that ADDRESSES the question.
            return Answer(text: localAnswer(question: question, snapshot: snapshot), source: .localData, usedCloud: false)
        }
        // Fold the recent conversation into the prompt so the model can resolve
        // "and that?" against what was just discussed. The data brief is always
        // re-stated so answers stay grounded in the CURRENT numbers.
        var convo = ""
        let recent = history.suffix(historyWindow)
        if !recent.isEmpty {
            convo = "Our conversation so far:\n"
                + recent.map { "\($0.role == .user ? "You" : "Me"): \($0.text)" }.joined(separator: "\n")
                + "\n\n"
        }
        let user = """
        Here is my current data:

        \(brief)

        \(convo)My question: \(question.isEmpty ? "How am I doing?" : question)
        """
        do {
            let reply = try await llm(systemPrompt, user)
            let trimmed = reply.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                return Answer(text: localAnswer(question: question, snapshot: snapshot), source: .localData, usedCloud: false)
            }
            return Answer(text: trimmed, source: .model, usedCloud: usedCloud)
        } catch {
            // A model that isn't running must NEVER break the feature.
            return Answer(text: localAnswer(question: question, snapshot: snapshot), source: .localData, usedCloud: false)
        }
    }

    // MARK: - Small local formatters (kept here so the core has no UI deps)

    private static func money(_ v: Double, _ currency: String) -> String {
        let sym = currencySymbol(currency)
        return "\(sym)\(Int(v.rounded()).formatted(.number.grouping(.automatic)))"
    }
    private static func signedPct(_ v: Double) -> String { String(format: "%+.1f%%", v) }
    private static func currencySymbol(_ code: String) -> String {
        switch code.uppercased() {
        case "USD", "CAD", "AUD": return "$"
        case "GBP": return "£"
        case "EUR": return "€"
        case "JPY": return "¥"
        case "INR": return "₹"
        default: return "\(code) "
        }
    }
}
