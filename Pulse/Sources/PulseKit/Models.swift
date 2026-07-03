import Foundation

// MARK: - Portfolio (read from ~/Documents/stock-tracker/portfolio.json)

public struct Holding: Codable, Identifiable {
    public var id: String { symbol }
    public let symbol: String
    public let quantity: Double
    public let costBasis: Double // per share/unit, in `currency`
    /// ISO "YYYY-MM-DD" the position was opened. Optional — when absent,
    /// Pulse estimates it from price history and labels it "est.".
    public let acquired: String?
    /// Currency of costBasis (e.g. "CAD"). Should match the listing's quote
    /// currency so per-position returns stay a pure ratio; nil = USD.
    public let currency: String?
    /// "Stock" / "ETF" / "Crypto" — from the brokerage report's security
    /// type. nil = unknown (hand-entered rows).
    public let assetClass: String?

    public init(symbol: String, quantity: Double, costBasis: Double,
                acquired: String? = nil, currency: String? = nil,
                assetClass: String? = nil) {
        self.symbol = symbol
        self.quantity = quantity
        self.costBasis = costBasis
        self.acquired = acquired
        self.currency = currency
        self.assetClass = assetClass
    }

    public var acquiredDate: Date? { acquired.flatMap(parseISODate) }
}

public struct CallPosition: Codable, Identifiable {
    public var id: String { "\(underlying)-\(strike)-\(expiry)" }
    public let underlying: String
    public let strike: Double
    public let expiry: String   // ISO date "YYYY-MM-DD"
    public let contracts: Int
    public let premiumPaid: Double // USD total for the position

    public init(underlying: String, strike: Double, expiry: String,
                contracts: Int, premiumPaid: Double) {
        self.underlying = underlying
        self.strike = strike
        self.expiry = expiry
        self.contracts = contracts
        self.premiumPaid = premiumPaid
    }

    public var expiryDate: Date? { parseISODate(expiry) }
    public var daysToExpiry: Int? {
        guard let d = expiryDate else { return nil }
        return Calendar.current.dateComponents([.day], from: Date(), to: d).day
    }
    /// Intrinsic value of the whole position at underlying price S.
    public func intrinsic(at s: Double) -> Double {
        max(0, s - strike) * 100.0 * Double(contracts)
    }
}

public struct Portfolio: Codable {
    public var holdings: [Holding]
    public var calls: [CallPosition]

    public init(holdings: [Holding], calls: [CallPosition]) {
        self.holdings = holdings
        self.calls = calls
    }

    public static var dirURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/stock-tracker")
    }
    public static var fileURL: URL {
        dirURL.appendingPathComponent("portfolio.json")
    }

    /// Load the user's portfolio; on first run, seed it from the example so
    /// there's always a file to edit.
    public static func load() -> Portfolio {
        let fm = FileManager.default
        if !fm.fileExists(atPath: fileURL.path) {
            let example = dirURL.appendingPathComponent("portfolio.example.json")
            try? fm.copyItem(at: example, to: fileURL)
        }
        guard let data = try? Data(contentsOf: fileURL),
              let p = try? JSONDecoder().decode(Portfolio.self, from: data)
        else { return Portfolio(holdings: [], calls: []) }
        return p
    }

    /// Persist back to portfolio.json (used by CSV import). Pretty-printed so
    /// the file stays hand-editable.
    public func save() throws {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(self).write(to: Portfolio.fileURL, options: .atomic)
    }
}

// MARK: - Quotes

public struct Quote {
    public let symbol: String
    public let price: Double
    public let previousClose: Double
    /// ~30 daily closes for the sparkline (oldest → newest).
    public let closes: [Double]
    /// The listing's quote currency, straight from Yahoo's meta ("CAD" for
    /// .TO, "USD" for NYSE, …) — never assumed.
    public let currency: String

    public init(symbol: String, price: Double, previousClose: Double,
                closes: [Double], currency: String = "USD") {
        self.symbol = symbol
        self.price = price
        self.previousClose = previousClose
        self.closes = closes
        self.currency = currency
    }

    public var dayChange: Double { price - previousClose }
    public var dayChangePct: Double {
        previousClose > 0 ? (price - previousClose) / previousClose * 100 : 0
    }
}
