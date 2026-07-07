import Foundation

/// Correlation-cluster detection. A portfolio of 439 tickers can still be a
/// concentrated bet if most of them move together — which is exactly the
/// trap the single-stock option-income ("YieldMax-style") complex creates:
/// dozens of tickers, one underlying strategy, one shared failure mode. This
/// makes that hidden concentration visible so it can be counted as the single
/// risk it actually is.
public struct HoldingCluster {
    public let name: String
    public let symbols: [String]
    public let value: Double
    public let cost: Double
    public var pct: Double // of the whole portfolio, by value
    public let note: String
}

public enum ClusterService {
    /// Known single-stock / option-income ETF families (YieldMax, Roundhill,
    /// Harvest, Hamilton, Purpose, Defiance, GraniteShares income lines).
    /// These sell calls on ONE volatile underlying and pay the premium as
    /// "yield" — high distributions, structural NAV decay, and they all fail
    /// together when volatility regimes turn.
    static let incomeEtfExact: Set<String> = [
        "MSTY","CONY","TSLY","NVDY","AMDY","MRNY","MARO","AMZY","ULTY","YMAG","ABNY",
        "AIYY","XYZY","SNOY","MSFO","PLTY","TSLP","DIPS","NFLP","AAPY","YPLT","APLY",
        "OARK","FBY","QDTE","XDTE","USOY","YBIT","NVDH","HBIX","HPYT","GROY","GOGY",
        "BTCY","ETHY","CSCMY","HIYY","ALOY","HTAE","EGGQ","EGGY","BITK","AMDW","TSLW",
        "YTSL","PLTW","HGY","BDRY","THTA","SINK","DIPS","APLY","BITO",
    ]

    static func base(_ symbol: String) -> String {
        symbol.split(separator: ".").first.map(String.init)?
            .split(separator: "-").first.map(String.init) ?? symbol
    }

    /// Is this an option-income / single-stock yield ETF? Exact list plus the
    /// telltale trailing-Y naming (e.g. "CONY", "AAPY") — conservative so it
    /// doesn't sweep in normal tickers.
    public static func isEquitySymbolPublic(_ symbol: String) -> Bool {
        SentimentService.isEquitySymbol(symbol)
    }

    public static func isIncomeEtf(_ symbol: String) -> Bool {
        let b = base(symbol).uppercased()
        if incomeEtfExact.contains(b) { return true }
        // Trailing-Y single-stock income names are ≥4 chars and not common
        // equities; keep it tight to avoid false positives.
        let normalEquitiesEndingY = Set(["BBY","EBAY","BABY","STAY","JOBY","RELY"])
        return b.count >= 4 && b.hasSuffix("Y") && !normalEquitiesEndingY.contains(b)
    }

    public static func clusters(holdings: [Holding],
                                quotes: [String: Quote],
                                fxRates: [String: Double]) -> [HoldingCluster] {
        func fx(_ c: String?) -> Double { fxRates[c ?? "USD"] ?? 1 }
        func value(_ h: Holding) -> Double {
            (quotes[h.symbol].map { $0.price * fx($0.currency) } ?? 0) * h.quantity
        }
        func cost(_ h: Holding) -> Double { h.costBasis * h.quantity * fx(h.currency) }

        let total = holdings.reduce(0.0) { $0 + value($1) }
        guard total > 0 else { return [] }
        var out: [HoldingCluster] = []

        return incomeClusters(holdings: holdings, value: value, cost: cost, total: total)
    }

    static func incomeClusters(holdings: [Holding],
                               value: (Holding) -> Double,
                               cost: (Holding) -> Double,
                               total: Double) -> [HoldingCluster] {
        var out: [HoldingCluster] = []
        let income = holdings.filter { isIncomeEtf($0.symbol) }
        if income.count >= 5 {
            let clusterValue = income.reduce(0.0) { $0 + value($1) }
            let clusterCost = income.reduce(0.0) { $0 + cost($1) }
            out.append(HoldingCluster(
                name: "Single-stock / option-income ETFs",
                symbols: income.map(\.symbol).sorted(),
                value: clusterValue, cost: clusterCost, pct: clusterValue / total * 100,
                note: "\(income.count) tickers, ONE strategy: sell calls on a volatile stock, pay the premium as yield, bleed NAV. They rise and fall together — this is a single concentrated bet wearing \(income.count) costumes, not diversification. The high distributions are largely your own capital returning, taxed as income."))
        }
        return out.sorted { $0.pct > $1.pct }
    }

    /// A sector/industry slice of the portfolio — how much rides on tech vs
    /// banks vs energy, so single-sector concentration is visible.
    public struct SectorSlice {
        public let name: String
        public let value: Double
        public let count: Int
        public var pct: Double
    }

    /// Group holdings by industry using a symbol→industry map (fetched from
    /// Finnhub fundamentals). ETFs/crypto/unknowns fall into buckets of their
    /// own so nothing is silently miscategorized.
    public static func sectors(holdings: [Holding],
                               quotes: [String: Quote],
                               fxRates: [String: Double],
                               industryBySymbol: [String: String]) -> [SectorSlice] {
        func fx(_ c: String?) -> Double { fxRates[c ?? "USD"] ?? 1 }
        func value(_ h: Holding) -> Double {
            (quotes[h.symbol].map { $0.price * fx($0.currency) } ?? 0) * h.quantity
        }
        let total = holdings.reduce(0.0) { $0 + value($1) }
        guard total > 0 else { return [] }

        var byIndustry: [String: (Double, Int)] = [:]
        for h in holdings {
            let v = value(h)
            guard v > 0 else { continue }
            let key: String
            if isIncomeEtf(h.symbol) {
                key = "Option-income ETFs"
            } else if (h.assetClass ?? "") == "Crypto" {
                key = "Crypto"
            } else if (h.assetClass ?? "") == "ETF" {
                key = "Diversified ETFs"
            } else if let ind = industryBySymbol[h.symbol], !ind.isEmpty {
                key = ind
            } else {
                key = "Other / unknown"
            }
            let prev = byIndustry[key] ?? (0, 0)
            byIndustry[key] = (prev.0 + v, prev.1 + 1)
        }
        return byIndustry
            .map { SectorSlice(name: $0.key, value: $0.value.0, count: $0.value.1,
                               pct: $0.value.0 / total * 100) }
            .sorted { $0.value > $1.value }
    }
}
