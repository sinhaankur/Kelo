import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - Congress trades (US STOCK Act disclosures)
//
// What members of Congress disclose trading, as public record under the STOCK
// Act. This is a TRANSPARENCY + research lens, NOT a buy signal, and the code
// is honest about why: disclosures are filed up to 30–45+ days AFTER the trade
// (`disclosureLagDays`), amounts are broad RANGES ($1,001–$15,000), and every
// row links to the actual filing (`docURL`). Nothing here is invented — the
// numbers, including post-disclosure performance, come straight from the feed.
//
// Source (verified 2026-07-22): the MIT-licensed kadoa-org/congress-trading-
// monitor dataset — both chambers, keyless static JSON. The older Stock Watcher
// S3 buckets are dead (403). If the source moves, change `feedURL`; on failure
// the last good fetch is served from the local cache.

public struct CongressTrade: Codable, Identifiable {
    public enum Chamber: String, Codable { case house, senate, unknown }
    /// The disclosed action. The feed labels are wordier ("Sale (Full)",
    /// "Sale (Partial)", "Purchase", "Exchange") — normalized to the call.
    public enum Kind: String, Codable { case buy, sell, exchange, unknown }

    public let id: String
    public let filerName: String
    public let chamber: Chamber
    public let party: String?        // "D" / "R" / "I" / nil
    public let state: String?        // 2-letter, drives the map
    public let office: String?       // e.g. "U.S. Representative · CT-04"
    public let ticker: String
    public let assetName: String?
    public let kind: Kind
    /// Disclosed amount RANGE (never an exact figure), in USD.
    public let amountLow: Double?
    public let amountHigh: Double?
    public let amountLabel: String?
    public let transactionDate: String? // ISO "YYYY-MM-DD"
    public let filingDate: String?      // ISO "YYYY-MM-DD"
    /// Days between the trade and its disclosure — the legally-permitted lag
    /// that makes this backward-looking. Precomputed by the feed when present.
    public let disclosureLagDays: Int?
    public let docURL: String?          // link to the actual PTR filing
    /// Post-disclosure performance, straight from the feed (fraction, e.g.
    /// -0.65 = the stock is down 65% since). `excessSince` is vs the market.
    /// nil when the feed hasn't computed it — never guessed.
    public let returnSince: Double?
    public let excessSince: Double?

    public init(id: String, filerName: String, chamber: Chamber, party: String?,
                state: String?, office: String?, ticker: String, assetName: String?,
                kind: Kind, amountLow: Double?, amountHigh: Double?, amountLabel: String?,
                transactionDate: String?, filingDate: String?, disclosureLagDays: Int?,
                docURL: String?, returnSince: Double?, excessSince: Double?) {
        self.id = id; self.filerName = filerName; self.chamber = chamber
        self.party = party; self.state = state; self.office = office
        self.ticker = ticker; self.assetName = assetName; self.kind = kind
        self.amountLow = amountLow; self.amountHigh = amountHigh; self.amountLabel = amountLabel
        self.transactionDate = transactionDate; self.filingDate = filingDate
        self.disclosureLagDays = disclosureLagDays; self.docURL = docURL
        self.returnSince = returnSince; self.excessSince = excessSince
    }

    public var transactionDateValue: Date? { transactionDate.flatMap(parseISODate) }
    public var filingDateValue: Date? { filingDate.flatMap(parseISODate) }
    /// A tradable US equity ticker (skip options/bonds/blank rows so the map
    /// and scorecards only reason about things that have a price).
    public var isEquity: Bool {
        let t = ticker.trimmingCharacters(in: .whitespaces)
        return !t.isEmpty && t != "--" && t.uppercased() == t
            && t.allSatisfy { $0.isLetter || $0 == "." || $0 == "-" }
    }
}

// MARK: - Per-member scorecard (how each trader is doing)

/// An honest, backward-looking read on one filer's disclosed record — never a
/// prediction, only what their disclosed moves have done since. `hitRate` is
/// the share of moves that "worked" (a buy that rose / a sell that fell),
/// counting only rows where the feed actually reports a return.
public struct MemberScorecard: Identifiable {
    public let filerName: String
    public let chamber: CongressTrade.Chamber
    public let party: String?
    public let state: String?
    public let tradeCount: Int          // total disclosed moves seen
    public let scoredCount: Int         // moves with a known return
    public let hitRate: Double?         // 0…1, nil when nothing is scored yet
    public let avgReturnSince: Double?  // mean returnSince across scored moves
    public var id: String { filerName }
}

public enum CongressService {
    /// Both-chamber disclosures, keyless. Swap this one constant if the source
    /// moves; the local cache covers an outage.
    static let feedURL = URL(string:
        "https://raw.githubusercontent.com/kadoa-org/congress-trading-monitor/main/public/data/trades.json")!

    // MARK: fetch

    /// Recent disclosures, newest filing first. Falls back to the on-disk cache
    /// when the network is down, so the section is never blank offline.
    public static func recentTrades(max: Int = 400) async -> [CongressTrade] {
        var req = URLRequest(url: feedURL)
        req.setValue("Mozilla/5.0 Kelo", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 20
        if let (data, resp) = try? await URLSession.shared.data(for: req),
           (resp as? HTTPURLResponse)?.statusCode == 200,
           let trades = decode(data), !trades.isEmpty {
            cache(data)
            return sortedTrimmed(trades, max: max)
        }
        // Offline / source down: serve the last good pull.
        if let data = try? Data(contentsOf: cacheURL), let trades = decode(data) {
            return sortedTrimmed(trades, max: max)
        }
        return []
    }

    private static func sortedTrimmed(_ trades: [CongressTrade], max: Int) -> [CongressTrade] {
        Array(trades
            .sorted { ($0.filingDateValue ?? .distantPast) > ($1.filingDateValue ?? .distantPast) }
            .prefix(max))
    }

    // MARK: decode (pure — unit-tested from fixture JSON)

    /// The feed's raw record. Defensive: unknown/missing fields never throw the
    /// whole decode (a schema drift shouldn't blank the feature).
    private struct Raw: Decodable {
        let id: String?
        let filer_name: String?
        let chamber: String?
        let party: String?
        let state: String?
        let office: String?
        let ticker: String?
        let asset_name: String?
        let transaction_type: String?
        let amount_range_low: Double?
        let amount_range_high: Double?
        let amount_range_label: String?
        let transaction_date: String?
        let filing_date: String?
        let days_to_file: Int?
        let doc_url: String?
        let ret_since: Double?
        let excess_since: Double?
    }

    /// Decode the feed JSON into normalized trades. Public for tests.
    public static func decode(_ data: Data) -> [CongressTrade]? {
        guard let raws = try? JSONDecoder().decode([Raw].self, from: data) else { return nil }
        return raws.compactMap { r in
            guard let ticker = r.ticker?.trimmingCharacters(in: .whitespaces), !ticker.isEmpty
            else { return nil }
            return CongressTrade(
                id: r.id ?? "\(r.filer_name ?? "?")-\(ticker)-\(r.transaction_date ?? "?")",
                filerName: r.filer_name ?? "Unknown",
                chamber: parseChamber(r.chamber),
                party: r.party, state: r.state, office: r.office,
                ticker: ticker.uppercased(), assetName: r.asset_name,
                kind: parseKind(r.transaction_type),
                amountLow: r.amount_range_low, amountHigh: r.amount_range_high,
                amountLabel: r.amount_range_label,
                transactionDate: r.transaction_date, filingDate: r.filing_date,
                disclosureLagDays: r.days_to_file, docURL: r.doc_url,
                returnSince: r.ret_since, excessSince: r.excess_since)
        }
    }

    /// Normalize the feed's transaction label to a call. Public for tests.
    public static func parseKind(_ raw: String?) -> CongressTrade.Kind {
        let s = (raw ?? "").lowercased()
        if s.contains("purchase") || s.contains("buy") { return .buy }
        if s.contains("sale") || s.contains("sell") { return .sell }
        if s.contains("exchange") { return .exchange }
        return .unknown
    }

    static func parseChamber(_ raw: String?) -> CongressTrade.Chamber {
        switch (raw ?? "").lowercased() {
        case "house": return .house
        case "senate": return .senate
        default: return .unknown
        }
    }

    // MARK: scoring (pure — unit-tested)

    /// Did a disclosed move "work"? A buy that rose, or a sell that fell (the
    /// member avoided a loss), given the post-disclosure return. nil when there
    /// is no return to judge, or the move isn't directional (exchange/unknown).
    public static func moveWorked(kind: CongressTrade.Kind, returnSince: Double?) -> Bool? {
        guard let r = returnSince else { return nil }
        switch kind {
        case .buy: return r > 0
        case .sell: return r < 0
        case .exchange, .unknown: return nil
        }
    }

    /// Aggregate disclosures into a per-member scorecard — the "how each trader
    /// is doing" view. Only equity rows count; hit-rate and average return use
    /// only rows the feed actually scored (never guessed).
    public static func memberScorecards(_ trades: [CongressTrade]) -> [MemberScorecard] {
        let byMember = Dictionary(grouping: trades.filter { $0.isEquity }, by: \.filerName)
        return byMember.map { name, rows in
            let scored = rows.compactMap { r -> (worked: Bool?, ret: Double)? in
                guard let ret = r.returnSince else { return nil }
                return (moveWorked(kind: r.kind, returnSince: ret), ret)
            }
            let directional = scored.compactMap { $0.worked }
            let hitRate = directional.isEmpty ? nil
                : Double(directional.filter { $0 }.count) / Double(directional.count)
            let avgRet = scored.isEmpty ? nil
                : scored.map(\.ret).reduce(0, +) / Double(scored.count)
            let first = rows.first
            return MemberScorecard(
                filerName: name, chamber: first?.chamber ?? .unknown,
                party: first?.party, state: first?.state,
                tradeCount: rows.count, scoredCount: scored.count,
                hitRate: hitRate, avgReturnSince: avgRet)
        }
        // Most active first — the Senate movers the user cares about surface at top.
        .sorted { $0.tradeCount > $1.tradeCount }
    }

    // MARK: local cache (mirrors Watchlist/Storage; hardened owner-only)

    static var cacheURL: URL { KeloStorage.baseURL.appendingPointComponentSafe("congress-cache.json") }

    private static func cache(_ data: Data) {
        try? data.write(to: cacheURL, options: .atomic)
        Security.hardenFile(at: cacheURL)
    }
}

private extension URL {
    /// Small guard so a stray path separator can't escape the data dir.
    func appendingPointComponentSafe(_ name: String) -> URL {
        appendingPathComponent(name.replacingOccurrences(of: "/", with: "_"))
    }
}
