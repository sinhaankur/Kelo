import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Live macro state from FRED (the St. Louis Fed's public data), via its
/// keyless `fredgraph.csv` endpoint — no key, no config, on-device. These
/// are the actual forces the Macro Lens talks about: inflation, the cost of
/// money, how much money exists, and the dollar. Facts, reported; never a
/// prediction of what they do next.
public struct MacroData {
    public struct Reading {
        public let label: String
        public let value: Double
        public let unit: String
        /// Year-over-year change where it's meaningful (inflation, money
        /// supply); nil for level series (rates, the index itself).
        public let yoyPct: Double?
        public let asOf: String
        /// Plain-language note on what this level tends to mean.
        public let note: String
    }
    public let readings: [Reading]
    public let fetchedAt: Date

    /// Inflation (CPI YoY) — the number that turns nominal gains into real
    /// ones. Used to compute inflation-adjusted returns instead of the fixed
    /// 3.5% placeholder.
    public var inflationYoYPct: Double? {
        readings.first { $0.label == "Inflation (CPI)" }?.yoyPct
    }
}

public enum MacroDataService {
    private struct Series {
        let id: String
        let label: String
        let unit: String
        let yoy: Bool
        let note: (Double, Double?) -> String
    }

    private static let series: [Series] = [
        Series(id: "CPIAUCSL", label: "Inflation (CPI)", unit: "%", yoy: true) { _, yoy in
            guard let y = yoy else { return "" }
            return y > 4 ? "prices rising fast — erodes cash and fixed income, pressures rates up"
                 : y > 2.5 ? "above the ~2% target — the Fed watches this closely"
                 : "cool — gives the Fed room to cut rates"
        },
        Series(id: "FEDFUNDS", label: "Fed funds rate", unit: "%", yoy: false) { v, _ in
            v > 4 ? "restrictive — expensive money weighs on growth stocks and borrowers"
                  : v > 2 ? "neutral-ish"
                  : "easy money — tends to inflate asset prices"
        },
        Series(id: "M2SL", label: "Money supply (M2)", unit: "$B", yoy: true) { _, yoy in
            guard let y = yoy else { return "" }
            return y > 8 ? "money printing fast — classic fuel for inflation and asset bubbles"
                 : y < 0 ? "money supply SHRINKING — rare and tight; a headwind for risk assets"
                 : "growing at a normal pace"
        },
        Series(id: "DTWEXBGS", label: "US dollar index", unit: "", yoy: true) { _, yoy in
            guard let y = yoy else { return "" }
            return y > 3 ? "strong dollar — weighs on commodities, gold, and foreign returns"
                 : y < -3 ? "weak dollar — lifts commodities, gold, and your non-USD holdings"
                 : "roughly stable"
        },
        Series(id: "DGS10", label: "US 10-year yield", unit: "%", yoy: false) { v, _ in
            v > 4.5 ? "elevated — the discount rate the whole market is valued against is high"
                    : "moderate"
        },
    ]

    public static func fetch() async -> MacroData {
        var readings: [MacroData.Reading] = []
        for s in series {
            guard let obs = await fetchSeries(id: s.id), let last = obs.last else { continue }
            var yoy: Double? = nil
            if s.yoy {
                // 12 monthly observations back, or nearest available.
                let target = obs.count >= 13 ? obs[obs.count - 13].value : obs.first?.value
                if let base = target, base > 0 {
                    yoy = (last.value - base) / base * 100
                }
            }
            readings.append(MacroData.Reading(
                label: s.label, value: last.value, unit: s.unit,
                yoyPct: yoy, asOf: last.date, note: s.note(last.value, yoy)))
        }
        return MacroData(readings: readings, fetchedAt: Date())
    }

    private static func fetchSeries(id: String) async -> [(date: String, value: Double)]? {
        guard let url = URL(string: "https://fred.stlouisfed.org/graph/fredgraph.csv?id=\(id)") else { return nil }
        var req = URLRequest(url: url)
        req.timeoutInterval = 12
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let text = String(data: data, encoding: .utf8) else { return nil }
        return parseCsv(text)
    }

    /// FRED CSV: header row, then "YYYY-MM-DD,value" with "." for missing.
    static func parseCsv(_ text: String) -> [(date: String, value: Double)] {
        var out: [(String, Double)] = []
        for line in text.split(whereSeparator: \.isNewline).dropFirst() {
            let cols = line.split(separator: ",")
            guard cols.count >= 2, let v = Double(cols[1]) else { continue }
            out.append((String(cols[0]), v))
        }
        return out
    }
}
