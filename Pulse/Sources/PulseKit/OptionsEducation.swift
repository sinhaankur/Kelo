import Foundation

/// Options, taught from zero — plain language plus an honest calculator.
/// Nothing here recommends buying options; it explains what they are and
/// shows exactly what a trade would cost, break even at, and lose. For a
/// first-timer the goal is understanding and a risk-free test run, not a bet.
public enum OptionsEducation {
    /// The lessons, in the order a total beginner should read them.
    public static let lessons: [(title: String, body: String)] = [
        ("What an option is",
         "An option is a contract that gives you the RIGHT — not the obligation — to buy or sell 100 shares of a stock at a fixed price (the 'strike') before a deadline (the 'expiry'). You pay a fee up front for that right, called the 'premium'. One contract = 100 shares, so a $2.00 premium costs $200."),

        ("Calls vs Puts",
         "A CALL is a bet UP: the right to BUY at the strike. You want one when you think the stock will rise above the strike. A PUT is a bet DOWN: the right to SELL at the strike. You want one when you think the stock will fall below it. Buying either one, the most you can lose is the premium you paid — but you lose ALL of it if you're wrong."),

        ("The premium and breakeven",
         "You don't profit the moment the stock moves your way — you first have to earn back the premium. If you pay $2.00 for a $100 call, the stock must climb past $102 (strike + premium) just for you to break even. Everything below that is still a loss. This is why options need a BIG, FAST move to pay off, not just any move."),

        ("Theta — why time is your enemy",
         "An option is a melting ice cube. Every day that passes, it loses a little value even if the stock doesn't move — that's 'theta,' or time decay. The closer to expiry, the faster it melts. A stock you can hold forever; an option is fighting a clock. Most options that are bought expire worthless."),

        ("The covered call — the ONE safe strategy",
         "If you own 100+ shares of a stock, you can SELL a call against them and collect the premium as income. If the stock stays flat or rises modestly, you keep the premium free. The trade-off: if it rockets up, you have to sell your shares at the strike and miss the extra upside. It's the only options strategy that lowers your risk instead of raising it — but it needs 100 shares of ONE stock, which a scattered portfolio doesn't have yet."),

        ("Why options are dangerous for small accounts",
         "Buying calls and puts is the fastest-losing game in the market for beginners: you need a large move in a specific direction within a specific time, while theta bleeds you daily, and you can lose 100% of what you put in. There's no 'hold and wait for recovery' — expiry is final. Learn on paper first. Real options only make sense once you have a positive paper record AND enough shares for covered calls."),
    ]
}

/// The honest math of a single bought option — every number that decides
/// whether it wins or loses, computed, not guessed.
public struct OptionScenario {
    public enum Kind: String { case call = "CALL", put = "PUT" }
    public let kind: Kind
    public let spot: Double         // current stock price
    public let strike: Double
    public let premium: Double      // per share
    public let daysToExpiry: Int
    public let contracts: Int

    public init(kind: Kind, spot: Double, strike: Double, premium: Double,
                daysToExpiry: Int, contracts: Int) {
        self.kind = kind
        self.spot = spot
        self.strike = strike
        self.premium = premium
        self.daysToExpiry = daysToExpiry
        self.contracts = contracts
    }

    public var costTotal: Double { premium * 100 * Double(contracts) }
    /// The price the stock must reach for you to break even at expiry.
    public var breakeven: Double {
        kind == .call ? strike + premium : strike - premium
    }
    /// How far the stock must move from here, in %, just to break even.
    public var moveToBreakevenPct: Double {
        spot > 0 ? (breakeven - spot) / spot * 100 : 0
    }
    /// Max loss = the whole premium (a bought option can't lose more).
    public var maxLoss: Double { costTotal }
    /// Intrinsic value right now — what it'd be worth if it expired today.
    public var intrinsicNow: Double {
        let per = kind == .call ? max(0, spot - strike) : max(0, strike - spot)
        return per * 100 * Double(contracts)
    }
    /// True when there's no intrinsic value yet — you're paying purely for
    /// hope and time. Most beginner losses live here.
    public var isAllTimeValue: Bool { intrinsicNow == 0 }

    /// One plain-language honesty line.
    public var honestRead: String {
        var s = "You'd pay \(usd(costTotal)). "
        s += "The stock is at \(usd(spot)); it must reach \(usd(breakeven)) "
        s += "(\(String(format: "%+.1f", moveToBreakevenPct))%) by expiry in \(daysToExpiry) days just to break even. "
        if isAllTimeValue {
            s += "This option has NO intrinsic value yet — you're paying entirely for time and hope, and it melts daily. "
        }
        s += "Max loss: \(usd(maxLoss)) (100% of what you put in)."
        return s
    }
}
