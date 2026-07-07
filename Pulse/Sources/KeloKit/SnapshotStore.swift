import Foundation

/// One recorded end-of-refresh account value per calendar day. This is the
/// honest complement to the reconstructed GROWTH series: options have no
/// historical marks, but from today forward their real delayed marks are
/// RECORDED, not invented. Stored locally, gitignored, last write of the
/// day wins.
public struct DailySnapshot: Codable, Equatable {
    public let date: String    // "YYYY-MM-DD" in market time (America/New_York)
    public let holdings: Double
    public let options: Double
    public let cost: Double
    public var total: Double { holdings + options }

    public init(date: String, holdings: Double, options: Double, cost: Double) {
        self.date = date
        self.holdings = holdings
        self.options = options
        self.cost = cost
    }
}

public enum SnapshotStore {
    public static var fileURL: URL {
        Portfolio.dirURL.appendingPathComponent("snapshots.json")
    }

    public static func load(from url: URL = fileURL) -> [DailySnapshot] {
        guard let data = try? Data(contentsOf: url),
              let list = try? JSONDecoder().decode([DailySnapshot].self, from: data)
        else { return [] }
        return list
    }

    /// Replace today's entry (values move all day) and keep the list sorted.
    static func upsert(_ snap: DailySnapshot, into list: [DailySnapshot]) -> [DailySnapshot] {
        var out = list.filter { $0.date != snap.date }
        out.append(snap)
        out.sort { $0.date < $1.date }
        return out
    }

    /// Record after a successful refresh. Callers must only pass real values
    /// (all quotes present) — a partial fetch written here would poison the
    /// record.
    @discardableResult
    public static func record(holdings: Double, options: Double, cost: Double,
                              at date: Date = Date(),
                              to url: URL = fileURL) -> [DailySnapshot] {
        let snap = DailySnapshot(date: isoDateString(date), holdings: holdings,
                                 options: options, cost: cost)
        let updated = upsert(snap, into: load(from: url))
        if let data = try? JSONEncoder().encode(updated) {
            try? data.write(to: url, options: .atomic)
        }
        return updated
    }
}
