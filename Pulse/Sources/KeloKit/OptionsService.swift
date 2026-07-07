import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Real option quotes from CBOE's public delayed-quotes API (official exchange
/// data, ~15 min delayed, keyless). One fetch returns the entire chain for an
/// underlying; we index it by OCC symbol and look up our positions.
public enum OptionsService {
    public struct OptionQuote {
        public let bid: Double
        public let ask: Double
        public let last: Double
        public let iv: Double
        public let openInterest: Int
        /// Best available mark: mid of bid/ask when a live market exists,
        /// else the last trade.
        public var mark: Double {
            (bid > 0 && ask > 0) ? (bid + ask) / 2 : last
        }
    }

    private struct Chain: Decodable {
        struct Payload: Decodable {
            let options: [Contract]?
            let current_price: Double?
        }
        struct Contract: Decodable {
            let option: String
            let bid: Double?
            let ask: Double?
            let last_trade_price: Double?
            let iv: Double?
            let open_interest: Double?
        }
        let data: Payload
    }

    /// OCC symbol for a call: ROOT + yyMMdd + "C" + strike×1000, zero-padded
    /// to 8 digits (e.g. MSFT 2026-09-18 500 → MSFT260918C00500000).
    public static func occSymbol(for call: CallPosition) -> String {
        let compactExpiry = call.expiry.replacingOccurrences(of: "-", with: "")
        let yymmdd = String(compactExpiry.dropFirst(2))
        let strikeInt = Int((call.strike * 1000).rounded())
        return "\(call.underlying)\(yymmdd)C\(String(format: "%08d", strikeInt))"
    }

    /// Fetch the full chain for an underlying → [occSymbol: quote].
    public static func fetchChain(underlying: String) async -> [String: OptionQuote] {
        let url = URL(string: "https://cdn.cboe.com/api/global/delayed_quotes/options/\(underlying).json")!
        var req = URLRequest(url: url)
        req.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 15
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let chain = try? JSONDecoder().decode(Chain.self, from: data),
              let contracts = chain.data.options
        else { return [:] }
        var out: [String: OptionQuote] = [:]
        for c in contracts {
            out[c.option] = OptionQuote(
                bid: c.bid ?? 0,
                ask: c.ask ?? 0,
                last: c.last_trade_price ?? 0,
                iv: c.iv ?? 0,
                openInterest: Int(c.open_interest ?? 0),
            )
        }
        return out
    }

    /// Fetch chains for several underlyings concurrently, merged into one map.
    public static func fetchAll(underlyings: [String]) async -> [String: OptionQuote] {
        await withTaskGroup(of: [String: OptionQuote].self) { group in
            for u in Set(underlyings) { group.addTask { await fetchChain(underlying: u) } }
            var merged: [String: OptionQuote] = [:]
            for await m in group { merged.merge(m) { a, _ in a } }
            return merged
        }
    }
}
