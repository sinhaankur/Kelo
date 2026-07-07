import Foundation

// MARK: - Day State — the unified body + money reading
//
// Kelo's hero. One honest, glanceable answer to "how am I set up today?" that
// fuses the body side ([[Health.swift]]) with the money side (portfolio +
// spending). It is NOT a score out of 100 pretending to be precise, and it is
// NOT advice — it reads the state you're actually in and names it, the way
// the portfolio HealthBanner already does for money alone.
//
// Pure and testable: no SwiftUI, no I/O. The view hands it today's numbers;
// it returns a verdict + the plain-language reasons. Honesty rule: a signal
// that wasn't logged is OMITTED from the reasoning, never guessed — the
// reading degrades to "based on what you gave me" rather than inventing a
// number.

public struct DayState {
    public enum Standing: String { case strong, steady, strained }

    public struct Reason: Identifiable {
        public let id = UUID()
        public let icon: String       // SF Symbol
        public let good: Bool         // true = a tailwind, false = a drag
        public let text: String
        public init(icon: String, good: Bool, text: String) {
            self.icon = icon; self.good = good; self.text = text
        }
    }

    public let standing: Standing
    public let headline: String
    public let reasons: [Reason]
    /// True when we had almost nothing to go on — the view can invite the
    /// user to log a day instead of showing a hollow verdict.
    public let thin: Bool

    // MARK: Inputs
    //
    // Everything optional so the composite works from day one with partial
    // data. Money side is expressed as ratios/flags so this stays
    // currency-agnostic (the view has already converted to display currency).

    public struct Inputs {
        public var today: HealthDay?
        public var restingHRBaseline: Double?
        public var recentLoad: Double            // trailing 7-day training load
        /// Portfolio day change as a fraction of holdings value (e.g. +0.014).
        public var portfolioDayFraction: Double?
        /// Spending so far this month vs. the sum of category budgets, as a
        /// fraction (1.1 = 10% over plan). nil = no budgets set.
        public var spendVsBudget: Double?

        public init(today: HealthDay? = nil, restingHRBaseline: Double? = nil,
                    recentLoad: Double = 0, portfolioDayFraction: Double? = nil,
                    spendVsBudget: Double? = nil) {
            self.today = today
            self.restingHRBaseline = restingHRBaseline
            self.recentLoad = recentLoad
            self.portfolioDayFraction = portfolioDayFraction
            self.spendVsBudget = spendVsBudget
        }
    }

    public init(_ i: Inputs) {
        var reasons: [Reason] = []
        var score = 0            // + tailwinds, − drags; only from KNOWN signals
        var signals = 0          // how many real signals fed the reading

        // ── Body: sleep ────────────────────────────────────────────────
        if let sleep = i.today?.sleepHours {
            signals += 1
            if sleep >= 7 {
                score += 1
                reasons.append(.init(icon: "bed.double.fill", good: true,
                    text: String(format: "%.1fh sleep — well rested", sleep)))
            } else if sleep < 6 {
                score -= 1
                reasons.append(.init(icon: "bed.double", good: false,
                    text: String(format: "%.1fh sleep — short; expect less patience", sleep)))
            } else {
                reasons.append(.init(icon: "bed.double", good: true,
                    text: String(format: "%.1fh sleep — okay", sleep)))
            }
        }

        // ── Body: resting HR vs your own baseline ──────────────────────
        if let hr = i.today?.restingHR, let base = i.restingHRBaseline {
            signals += 1
            let delta = hr - base
            if delta <= -2 {
                score += 1
                reasons.append(.init(icon: "heart.fill", good: true,
                    text: String(format: "resting HR %.0f, %.0f below your baseline — recovered", hr, Double(-delta))))
            } else if delta >= 3 {
                score -= 1
                reasons.append(.init(icon: "heart", good: false,
                    text: String(format: "resting HR %.0f, %.0f above baseline — under-recovered or stressed", hr, delta)))
            }
        }

        // ── Body: readiness self-rating ────────────────────────────────
        if let r = i.today?.readiness {
            signals += 1
            if r >= 7 {
                score += 1
                reasons.append(.init(icon: "bolt.fill", good: true,
                    text: "you rated yourself \(r)/10 — good energy"))
            } else if r <= 4 {
                score -= 1
                reasons.append(.init(icon: "bolt.slash", good: false,
                    text: "you rated yourself \(r)/10 — running low"))
            }
        }

        // ── Body: training load context ────────────────────────────────
        // A rest day after a heavy week is a GOOD sign, not a gap.
        if let today = i.today {
            if today.didTrain {
                signals += 1
                reasons.append(.init(icon: "figure.strengthtraining.traditional", good: true,
                    text: "trained today — \(today.sessions.count) session\(today.sessions.count == 1 ? "" : "s")"))
            } else if i.recentLoad > 1500 {
                reasons.append(.init(icon: "figure.cooldown", good: true,
                    text: "rest day after a heavy week — earned recovery"))
            }
        }

        // ── Money: portfolio day move ──────────────────────────────────
        if let f = i.portfolioDayFraction {
            signals += 1
            let pctStr = String(format: "%+.1f%%", f * 100)
            if f >= 0.005 {
                score += 1
                reasons.append(.init(icon: "chart.line.uptrend.xyaxis", good: true,
                    text: "portfolio \(pctStr) today"))
            } else if f <= -0.015 {
                score -= 1
                reasons.append(.init(icon: "chart.line.downtrend.xyaxis", good: false,
                    text: "portfolio \(pctStr) today — a red day; don't let it drive a decision"))
            }
        }

        // ── Money: spending vs plan ────────────────────────────────────
        if let s = i.spendVsBudget {
            signals += 1
            if s > 1.0 {
                score -= 1
                reasons.append(.init(icon: "creditcard.trianglebadge.exclamationmark", good: false,
                    text: String(format: "%.0f%% over this month's budget", (s - 1) * 100)))
            } else if s < 0.8 {
                score += 1
                reasons.append(.init(icon: "creditcard", good: true,
                    text: "spending under plan this month"))
            }
        }

        // ── Verdict ────────────────────────────────────────────────────
        self.thin = signals < 2
        self.reasons = reasons
        if thin {
            self.standing = .steady
            self.headline = "Log a day to see your state"
        } else if score >= 2 {
            self.standing = .strong
            self.headline = "You're set up well today"
        } else if score <= -2 {
            self.standing = .strained
            self.headline = "A stretched day — go gently"
        } else {
            self.standing = .steady
            self.headline = "A steady day"
        }
    }
}
