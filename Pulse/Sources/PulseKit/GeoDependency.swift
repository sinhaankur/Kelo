import Foundation

/// The geo-dependency lens — a stock listed in one country usually DEPENDS on
/// several others for its inputs, energy, and shipping. This maps an
/// industry to its critical minerals, producer countries, energy inputs, and
/// the maritime chokepoints its supply chain flows through — so "a shock in
/// country B or C can move a stock listed in country A" becomes concrete.
/// Explanatory reference, inspired by StockMonitor's Geo-Dependency Engine,
/// built natively from the concept (no external code). Not predictive.
public struct GeoDependency {
    public let inputs: [String]        // critical materials / components
    public let producers: [String]     // countries those come from
    public let chokepoints: [String]   // shipping routes it depends on
    public let note: String

    public var isEmpty: Bool { inputs.isEmpty && producers.isEmpty && chokepoints.isEmpty }
}

public enum GeoDependencyLens {
    public static func forIndustry(_ industry: String?) -> GeoDependency {
        let ind = (industry ?? "").lowercased()

        if ind.contains("semiconduct") || ind.contains("chip") {
            return GeoDependency(
                inputs: ["advanced chips", "silicon wafers", "rare-earth elements", "neon gas"],
                producers: ["Taiwan (TSMC)", "South Korea", "Netherlands (ASML)", "China (rare earths)"],
                chokepoints: ["Taiwan Strait", "South China Sea"],
                note: "Even a US-listed chip company usually depends on Taiwanese fabrication and Dutch lithography equipment. A Taiwan Strait crisis is a supply shock for the whole sector, wherever the stock trades.")
        }
        if ind.contains("auto") || ind.contains("electric vehicle") || ind.contains("ev") {
            return GeoDependency(
                inputs: ["lithium", "cobalt", "nickel", "chips", "rare-earth magnets"],
                producers: ["Chile & Australia (lithium)", "DR Congo (cobalt)", "Indonesia (nickel)", "China (magnets & processing)"],
                chokepoints: ["Strait of Malacca", "Panama Canal"],
                note: "Carmakers depend on battery minerals dug and refined far from where they sell cars. China controls much of the refining — a policy shift there ripples to every automaker.")
        }
        if ind.contains("oil") || ind.contains("gas") || ind.contains("energy") {
            return GeoDependency(
                inputs: ["crude oil", "natural gas", "refining capacity"],
                producers: ["Saudi Arabia", "Russia", "US shale", "OPEC members"],
                chokepoints: ["Strait of Hormuz", "Suez Canal", "Bab-el-Mandeb"],
                note: "Roughly a fifth of the world's oil passes through the Strait of Hormuz. Conflict near these chokepoints spikes prices and moves energy stocks globally — often up for producers.")
        }
        if ind.contains("pharma") || ind.contains("drug") || ind.contains("biotech") {
            return GeoDependency(
                inputs: ["active pharmaceutical ingredients (APIs)", "precursor chemicals"],
                producers: ["India (generics)", "China (APIs)"],
                chokepoints: ["Indian Ocean routes"],
                note: "A large share of the world's drug ingredients are made in India and China. A disruption there is a supply-chain risk even for Western pharma brands.")
        }
        if ind.contains("retail") || ind.contains("apparel") || ind.contains("consumer") || ind.contains("electronics") {
            return GeoDependency(
                inputs: ["manufactured goods", "components", "textiles"],
                producers: ["China", "Vietnam", "Bangladesh", "Mexico"],
                chokepoints: ["Suez Canal", "Strait of Malacca", "Panama Canal"],
                note: "Consumer brands design in one country and manufacture in another. Shipping-lane disruptions (a blocked Suez, a Panama drought) raise costs and delay inventory.")
        }
        if ind.contains("mining") || ind.contains("metal") || ind.contains("material") {
            return GeoDependency(
                inputs: ["iron ore", "copper", "aluminium", "coal"],
                producers: ["Australia", "Brazil", "Chile", "China (demand)"],
                chokepoints: ["bulk shipping lanes"],
                note: "Miners sell into global industrial demand — China is the swing buyer. Its growth pace, more than the miner's home country, tends to set prices.")
        }
        if ind.contains("bank") || ind.contains("financ") || ind.contains("insurance") {
            return GeoDependency(
                inputs: ["deposits", "central-bank rate policy"],
                producers: ["domestic economy", "the home central bank"],
                chokepoints: [],
                note: "Banks are mostly a bet on their home economy and its central bank — less globally supply-chained, more exposed to domestic rates, housing, and credit cycles.")
        }
        if ind.contains("agri") || ind.contains("food") || ind.contains("farm") {
            return GeoDependency(
                inputs: ["grain", "fertilizer", "potash"],
                producers: ["US & Ukraine & Russia (grain)", "Canada & Russia (potash)"],
                chokepoints: ["Black Sea", "Bosphorus"],
                note: "Global food prices hinge on a few breadbaskets. War in the Black Sea region has repeatedly spiked grain and fertilizer costs worldwide.")
        }
        return GeoDependency(inputs: [], producers: [], chokepoints: [],
                             note: "No mapped supply chain for this industry — its exposure is mostly to broad market forces (rates, inflation, its home economy).")
    }
}
