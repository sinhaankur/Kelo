import Foundation

/// Rule-based portfolio review — the honest version of "what should I buy or
/// sell": deterministic structural findings ranked by dollar impact, each
/// with the numbers that justify it and each testable as a paper trade.
/// No market prediction anywhere; these rules only measure what already is.
public struct ReviewItem {
    public enum Kind: String {
        case concentration  // one position dominates
        case laggard        // long-held, far behind the index
        case dust           // positions too small to matter
        case dead           // no live quote — delisted or bad symbol
    }
    public let kind: Kind
    public let symbol: String?
    public let headline: String
    public let detail: String
    /// Ranking key, in the display currency — how many dollars this finding
    /// is about. Bigger = worth attention first.
    public let dollarImpact: Double
}

public enum ReviewService {
    public static func review(holdings: [Holding],
                              quotes: [String: Quote],
                              timelines: [String: PositionTimeline],
                              fxRates: [String: Double]) -> [ReviewItem] {
        func fx(_ currency: String?) -> Double { fxRates[currency ?? "USD"] ?? 1 }
        func value(_ h: Holding) -> Double {
            (quotes[h.symbol].map { $0.price * fx($0.currency) } ?? 0) * h.quantity
        }
        func cost(_ h: Holding) -> Double { h.costBasis * h.quantity * fx(h.currency) }

        let total = holdings.reduce(0.0) { $0 + value($1) }
        guard total > 0 else { return [] }
        var items: [ReviewItem] = []

        // CONCENTRATION — a single position that can sink the whole account.
        for h in holdings {
            let v = value(h)
            let pct = v / total * 100
            if pct > 40 {
                items.append(ReviewItem(
                    kind: .concentration, symbol: h.symbol,
                    headline: "\(h.symbol) is \(Int(pct))% of the portfolio",
                    detail: "\(usd(v)) of \(usd(total)) rides on one position — its bad day is the account's bad day. Consider whether that sizing is a decision or an accident.",
                    dollarImpact: v))
            }
        }

        // LAGGARDS — held ≥1y and ≥10pp/yr behind the S&P over the SAME
        // window. The impact number is the switching math: what the same
        // dollars did in the index instead.
        var laggards: [ReviewItem] = []
        for h in holdings {
            guard let t = timelines[h.symbol], t.holdingDays >= 365,
                  let ann = t.annualizedPct, let bench = t.benchmarkPct else { continue }
            let benchAnn = (pow(1 + bench / 100, 365.25 / Double(t.holdingDays)) - 1) * 100
            guard ann <= benchAnn - 10 else { continue }
            let c = cost(h)
            let foregone = c * (bench - t.totalReturnPct) / 100
            guard foregone > 0 else { continue }
            laggards.append(ReviewItem(
                kind: .laggard, symbol: h.symbol,
                headline: "\(h.symbol) held \(t.heldLabel)\(t.estimated ? " (est.)" : ""): \(String(format: "%+.1f", ann))%/y vs S&P \(String(format: "%+.1f", benchAnn))%/y",
                detail: "the same \(usd(c)) in the index over that window would be \(usd(foregone)) ahead. Not a sell order — a question: what do you know about \(h.symbol) that the market doesn't?",
                dollarImpact: foregone))
        }
        items += laggards.sorted { $0.dollarImpact > $1.dollarImpact }.prefix(5)

        // DUST — positions too small to move the account but plenty big
        // enough to fragment attention. One aggregate finding.
        let dustThreshold = max(25, total * 0.003)
        let dust = holdings.filter { let v = value($0); return v > 0 && v < dustThreshold }
        if dust.count >= 10 {
            let dustValue = dust.reduce(0.0) { $0 + value($1) }
            items.append(ReviewItem(
                kind: .dust, symbol: nil,
                headline: "\(dust.count) positions under \(usd(dustThreshold)) each — \(usd(dustValue)) total (\(Int(dustValue / total * 100))% of the account)",
                detail: "even a double in any of them barely registers, but each one costs attention. Consolidating dust into your few real convictions is the most reliable 'increase value' move available: it changes nothing about the market and everything about whether you can actually manage this portfolio.",
                dollarImpact: dustValue))
        }

        // DEAD — no live quote: delisted, renamed, or a bad symbol. The
        // book value tied up here is unknown until verified in the broker.
        let dead = holdings.filter { quotes[$0.symbol] == nil }
        if !dead.isEmpty {
            let deadCost = dead.reduce(0.0) { $0 + cost($1) }
            let names = dead.prefix(4).map(\.symbol).joined(separator: ", ")
            items.append(ReviewItem(
                kind: .dead, symbol: nil,
                headline: "\(dead.count) position\(dead.count == 1 ? "" : "s") with no live quote (\(names)\(dead.count > 4 ? ", …" : ""))",
                detail: "\(usd(deadCost)) of book value can't be priced — delisted, renamed, or a symbol Pulse can't map. Verify these in the brokerage; they show as $0 here until then.",
                dollarImpact: deadCost))
        }

        return items.sorted { $0.dollarImpact > $1.dollarImpact }
    }
}

// MARK: - Per-position verdicts

/// A committed call per position — direction, not ambiguity. Grounded ONLY
/// in observable decay, never price prediction: a chart 70% off its high and
/// under its 200-day for a position that has lagged the index for years is
/// a condition, and conditions get named plainly.
public struct PositionVerdict {
    public enum Call: String {
        case exit = "EXIT CANDIDATE"
        case review = "REVIEW"
        case hold = "HOLD"
    }
    /// One decay marker: the short line shown, plus the plain-English rule
    /// behind it (the exact threshold and why it matters). The "why" lives
    /// here in the engine so the UI never invents an explanation.
    public struct Marker {
        public let text: String
        public let explanation: String
    }
    public let symbol: String
    public let call: Call
    public let markers: [Marker]
    public let valueAtStake: Double

    /// Back-compat: the plain lines, for callers that only need the text.
    public var reasons: [String] { markers.map(\.text) }

    /// What EXIT / REVIEW / HOLD each mean, in one sentence.
    public var callExplanation: String {
        switch call {
        case .exit:
            return "EXIT CANDIDATE: two or more decay markers fired. The direction is out unless you can write down a specific reason this recovers that the market hasn't already priced. If you can't write that sentence, that's your answer."
        case .review:
            return "REVIEW: one decay marker fired. Not a sell signal — a flag to look closer and decide, before it becomes two."
        case .hold:
            return "HOLD: no decay markers. Nothing structurally wrong. Don't churn it looking for action."
        }
    }

    /// The committed recommendation — direct, no hedging. Every EXIT gets
    /// the same discipline: the loss is already sunk, so the only question
    /// is whether the REMAINING money keeps bleeding here or goes to work.
    public var recommendation: String {
        switch call {
        case .exit:
            return "Sell it. Not at a target price — now, at market. Waiting for it to 'come back to what you paid' is the sunk-cost trap: the market doesn't know your cost, and this needs a huge gain just to break even while it keeps decaying. Ask yourself the only question that matters — if you had this cash today, would you buy this? If no, you're re-buying it every day you hold. Redeploy into the index core."
        case .review:
            return "Decide, don't drift. One marker is a warning, not a verdict — open it, check whether the business is healthy or breaking, and either commit to holding it with a reason or move it to the exit pile before the second marker fires."
        case .hold:
            return "Hold — and be patient. No decay here, so time is on your side. This is where patience compounds; don't sell it because something else is loud. Only revisit if a marker appears."
        }
    }

    /// The one honest test, per call.
    public var buyItTodayVerdict: String {
        switch call {
        case .exit: return "Would you buy it today? Almost certainly no — so holding is choosing to buy it, daily."
        case .review: return "Would you buy it today? If you can't say yes with a reason, it's drifting toward exit."
        case .hold: return "Would you buy it today? If yes, keep holding. Patience is the position."
        }
    }
}

extension ReviewService {
    /// Verdict rules (count the decay markers):
    ///  · ≥70% below the multi-year high AND below the 200-day average
    ///  · held ≥1y and ≥15pp/yr behind the S&P over the same window
    ///  · total return ≤ −60% (the original thesis has failed)
    ///  · penny territory (price < $1 native)
    /// 2+ markers → EXIT CANDIDATE. 1 → REVIEW. 0 → HOLD.
    public static func verdicts(holdings: [Holding],
                                quotes: [String: Quote],
                                timelines: [String: PositionTimeline],
                                fxRates: [String: Double]) -> [PositionVerdict] {
        func fx(_ currency: String?) -> Double { fxRates[currency ?? "USD"] ?? 1 }
        var out: [PositionVerdict] = []
        for h in holdings {
            guard let q = quotes[h.symbol] else { continue } // dead → REVIEW list handles
            let value = q.price * fx(q.currency) * h.quantity
            var markers: [PositionVerdict.Marker] = []

            if let t = timelines[h.symbol] {
                if let fromHigh = t.pctFromAllTimeHigh, let ma = t.vsMa200Pct,
                   fromHigh <= -70, ma < 0 {
                    markers.append(.init(
                        text: "broken chart: \(String(format: "%.0f", fromHigh))% from its high and below the 200-day average",
                        explanation: "Two things are both true: the price is at least 70% below its highest point ever (this one is \(String(format: "%.0f", fromHigh))%), AND it's still trading below its own 200-day average (\(String(format: "%.0f", ma))%), so the long-term trend is down, not recovering. A collapsed price that's climbing back wouldn't trip this — only a collapse with no turn does. For option-income ETFs this is by design: they pay gains out as 'dividends,' so the price grinds permanently lower."))
                }
                if t.holdingDays >= 365, let ann = t.annualizedPct, let bench = t.benchmarkPct {
                    let benchAnn = (pow(1 + bench / 100, 365.25 / Double(t.holdingDays)) - 1) * 100
                    if ann <= benchAnn - 15 {
                        markers.append(.init(
                            text: "dead weight: \(String(format: "%+.1f", ann))%/y over \(t.heldLabel) vs S&P \(String(format: "%+.1f", benchAnn))%/y",
                            explanation: "You've held this at least a year, and over that exact window it returned \(String(format: "%+.1f", ann))% per year while the S&P 500 did \(String(format: "%+.1f", benchAnn))% per year — a gap of \(String(format: "%.0f", benchAnn - ann)) points annually. The same money in a plain index fund would have grown faster with less single-name risk. 'Dead weight' = it's costing you the index's return to hold."))
                    }
                }
                if t.totalReturnPct <= -60 {
                    markers.append(.init(
                        text: "thesis failed: \(String(format: "%.0f", t.totalReturnPct))% since buying",
                        explanation: "Down \(String(format: "%.0f", t.totalReturnPct))% from your cost basis. Whatever reason you bought it for, the market has moved decisively against that idea. A loss this deep needs a +\(String(format: "%.0f", 100 / (1 + t.totalReturnPct / 100) - 100))% gain just to break even — the arithmetic of holding losers is brutal and asymmetric."))
                }
            }
            if q.price < 1 {
                markers.append(.init(
                    text: "penny territory: trading at \(String(format: "%.4f", q.price)) \(q.currency)",
                    explanation: "Trades under $1 (\(String(format: "%.4f", q.price)) \(q.currency)). Sub-$1 names have wide bid-ask spreads (you lose several percent just entering and exiting), thin liquidity, and are prone to promotion-and-dump cycles. 'Trends' here are usually spreads and noise, not signal."))
            }

            let call: PositionVerdict.Call = markers.count >= 2 ? .exit
                : markers.count == 1 ? .review : .hold
            out.append(PositionVerdict(symbol: h.symbol, call: call,
                                       markers: markers, valueAtStake: value))
        }
        return out.sorted {
            if $0.call != $1.call { return rank($0.call) < rank($1.call) }
            return $0.valueAtStake > $1.valueAtStake
        }
    }

    private static func rank(_ c: PositionVerdict.Call) -> Int {
        switch c {
        case .exit: return 0
        case .review: return 1
        case .hold: return 2
        }
    }
}

// MARK: - Trade ideas (paper-first)

/// Candidates generated from observable signals in the user's own book —
/// NOT predictions. A LONG candidate is a position in a working uptrend;
/// a SHORT candidate is a broken chart. Every idea is meant to be logged
/// as a paper trade and scored before any real money moves.
public struct TradeIdea {
    public let direction: String   // "LONG" / "SHORT (paper)"
    public let symbol: String
    public let thesis: String      // the numbers behind it
}

extension ReviewService {
    public static func ideas(holdings: [Holding],
                             quotes: [String: Quote],
                             timelines: [String: PositionTimeline],
                             verdicts: [PositionVerdict],
                             fxRates: [String: Double]) -> (longs: [TradeIdea], shorts: [TradeIdea]) {
        func fx(_ currency: String?) -> Double { fxRates[currency ?? "USD"] ?? 1 }
        let callBySymbol = Dictionary(uniqueKeysWithValues: verdicts.map { ($0.symbol, $0.call) })

        // LONG candidates: HOLD verdict, above the 200-day, near its high,
        // and actually beating the index over the holding period. Trend
        // continuation is the only long signal with any base-rate support —
        // and it still fails often, which is what the paper score is for.
        var longs: [(TradeIdea, Double)] = []
        for h in holdings {
            guard callBySymbol[h.symbol] == .hold,
                  let t = timelines[h.symbol], let q = quotes[h.symbol],
                  let ma = t.vsMa200Pct, ma > 0,
                  let fromHigh = t.pctFromAllTimeHigh, fromHigh > -15,
                  t.holdingDays >= 180,
                  let ann = t.annualizedPct, let bench = t.benchmarkPct else { continue }
            let benchAnn = (pow(1 + bench / 100, 365.25 / Double(t.holdingDays)) - 1) * 100
            guard ann > benchAnn else { continue }
            let value = q.price * fx(q.currency) * h.quantity
            longs.append((TradeIdea(
                direction: "LONG",
                symbol: h.symbol,
                thesis: "uptrend intact: +\(String(format: "%.0f", ma))% above 200-day, \(String(format: "%.0f", fromHigh))% from its high, \(String(format: "%+.1f", ann))%/y vs S&P \(String(format: "%+.1f", benchAnn))%/y over \(t.heldLabel)"),
                value))
        }

        // SHORT candidates (paper only): the biggest broken charts. Real
        // shorting costs borrow fees and can be squeezed — these exist to
        // train the read, not to place.
        let shorts = verdicts.filter { $0.call == .exit }
            .prefix(5)
            .map { v in
                TradeIdea(direction: "SHORT (paper)", symbol: v.symbol,
                          thesis: v.reasons.joined(separator: " · "))
            }

        return (longs.sorted { $0.1 > $1.1 }.prefix(5).map(\.0), Array(shorts))
    }
}
