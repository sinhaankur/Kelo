import Foundation

// MARK: - Portfolio (read from ~/Documents/stock-tracker/portfolio.json)

struct Holding: Codable, Identifiable {
    var id: String { symbol }
    let symbol: String
    let quantity: Double
    let costBasis: Double // USD per share/unit
}

struct CallPosition: Codable, Identifiable {
    var id: String { "\(underlying)-\(strike)-\(expiry)" }
    let underlying: String
    let strike: Double
    let expiry: String   // ISO date "YYYY-MM-DD"
    let contracts: Int
    let premiumPaid: Double // USD total for the position

    var expiryDate: Date? {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "America/New_York")
        return f.date(from: expiry)
    }
    var daysToExpiry: Int? {
        guard let d = expiryDate else { return nil }
        return Calendar.current.dateComponents([.day], from: Date(), to: d).day
    }
    /// Intrinsic value of the whole position at underlying price S.
    func intrinsic(at s: Double) -> Double {
        max(0, s - strike) * 100.0 * Double(contracts)
    }
}

struct Portfolio: Codable {
    var holdings: [Holding]
    var calls: [CallPosition]

    static var fileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/stock-tracker/portfolio.json")
    }

    /// Load the user's portfolio; on first run, seed it from the example so
    /// there's always a file to edit.
    static func load() -> Portfolio {
        let fm = FileManager.default
        if !fm.fileExists(atPath: fileURL.path) {
            let example = fileURL.deletingLastPathComponent()
                .appendingPathComponent("portfolio.example.json")
            try? fm.copyItem(at: example, to: fileURL)
        }
        guard let data = try? Data(contentsOf: fileURL),
              let p = try? JSONDecoder().decode(Portfolio.self, from: data)
        else { return Portfolio(holdings: [], calls: []) }
        return p
    }
}

// MARK: - Quotes

struct Quote {
    let symbol: String
    let price: Double
    let previousClose: Double
    /// ~30 daily closes for the sparkline (oldest → newest).
    let closes: [Double]
    var dayChange: Double { price - previousClose }
    var dayChangePct: Double {
        previousClose > 0 ? (price - previousClose) / previousClose * 100 : 0
    }
}
