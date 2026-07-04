import Foundation

/// The "why and how" layer: how big-picture forces — war, inflation, money
/// printing, rates, the dollar, oil — transmit to a specific stock, based on
/// its sector and country. These are the well-documented CHANNELS through
/// which macro moves markets; they are explanatory, not predictive. Pulse
/// never claims to know what happens next, only how the plumbing works.
public struct MacroExposure {
    public let force: String       // e.g. "War / conflict"
    public let channel: String     // plain-language transmission
    public let direction: String   // typical (not guaranteed) direction
}

public enum MacroLens {
    /// Map an industry keyword to the forces that historically move it.
    public static func exposures(industry: String?, country: String?) -> [MacroExposure] {
        let ind = (industry ?? "").lowercased()
        var out: [MacroExposure] = []

        func add(_ f: String, _ c: String, _ d: String) {
            out.append(MacroExposure(force: f, channel: c, direction: d))
        }

        // Energy / oil.
        if ind.contains("oil") || ind.contains("energy") || ind.contains("gas") {
            add("War / conflict", "Conflict in oil regions disrupts supply; scarce oil prices rise, lifting producers' revenue.", "usually up for producers")
            add("The petrodollar / USD", "Oil is priced in US dollars worldwide. A weaker dollar tends to push nominal oil prices up; a stronger dollar weighs on them.", "inverse to the dollar")
            add("Inflation", "Energy is an input to almost everything, so producers often hold value when inflation runs hot.", "usually a hedge")
        }
        // Banks / financials.
        if ind.contains("bank") || ind.contains("financ") || ind.contains("insurance") {
            add("Interest rates / money printing", "Banks earn on the spread between lending and deposit rates. Rising rates usually widen that spread; money printing and rate cuts compress it.", "up with rates, to a point")
            add("Inflation", "High inflation erodes the real value of fixed loans banks already made, and raises default risk in a downturn.", "mixed to negative")
        }
        // Tech / growth.
        if ind.contains("tech") || ind.contains("software") || ind.contains("semiconduct") || ind.contains("internet") {
            add("Interest rates", "Growth stocks are valued on FUTURE profits. Higher rates discount those future dollars harder, so tech usually falls when rates rise.", "inverse to rates")
            add("Currency printing", "Cheap money and low rates inflate valuations of long-duration growth assets — great on the way up, brutal when it reverses.", "up with easy money")
            add("Global supply chains", "Chips and hardware depend on Taiwan, Korea, China. A shock or conflict there hits supply and cost regardless of where the stock is listed.", "risk from Asia tension")
        }
        // Consumer staples / defensives.
        if ind.contains("consumer") || ind.contains("food") || ind.contains("utilit") || ind.contains("retail") {
            add("Inflation", "Staples can often pass rising costs to customers, so they tend to hold up better than most when prices rise.", "relatively defensive")
            add("Interest rates", "Utilities carry heavy debt and pay dividends, so they trade a bit like bonds — higher rates hurt them.", "inverse to rates for utilities")
        }
        // Materials / mining / gold.
        if ind.contains("mining") || ind.contains("metal") || ind.contains("material") || ind.contains("gold") {
            add("Inflation / money printing", "Hard assets like metals are a classic inflation hedge — when currency loses value, real things hold it.", "usually up with inflation")
            add("The dollar", "Commodities are dollar-priced; a weaker dollar lifts their nominal price.", "inverse to the dollar")
            add("War / conflict", "Gold especially is a fear asset — capital flees to it during conflict and uncertainty.", "up in fear")
        }
        // Defense.
        if ind.contains("aerospace") || ind.contains("defense") || ind.contains("defence") {
            add("War / conflict", "Defense contractors' order books grow when governments arm up. Conflict is, bluntly, their demand.", "up in conflict")
        }
        // Airlines / travel / shipping — oil as a cost.
        if ind.contains("airline") || ind.contains("travel") || ind.contains("ship") || ind.contains("transport") {
            add("Oil prices / war", "Fuel is a huge cost. Rising oil (often from conflict) squeezes margins directly.", "inverse to oil")
        }

        // Every foreign-listed holding carries currency risk back to you.
        if let country, !country.isEmpty, country.uppercased() != "US" {
            add("Currency / FX", "This is a \(country) company. Its home currency moving against yours changes your return even if the stock itself doesn't move — a country printing money devalues what your shares are worth in your currency.", "FX adds a second bet")
        }

        // The universal one.
        if out.isEmpty {
            add("Interest rates & inflation", "Nearly every stock is affected by the cost of money and the pace of price rises — they set the discount rate the whole market is valued on.", "market-wide")
        }
        return out
    }
}
