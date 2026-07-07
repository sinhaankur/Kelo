import Foundation

// MARK: - Spend controller
//
// Pulse's spend side: expenses, per-category budgets, a savings goal, and a
// pre-spend "can I afford this?" check. Same principles as the rest of Pulse —
// on-device, gitignored, honest. It never moves money or connects to a bank;
// you enter expenses (or import a CSV your bank exports), and Pulse makes the
// cost of a purchase visible BEFORE you make it. No app can force restraint,
// but it can put the trade-off in front of you at the moment you decide.
//
// Files (all gitignored, in ~/Documents/stock-tracker):
//   spending.json — { expenses, budgets, goal }

/// A single logged expense. Amount is positive (money out), in the user's base
/// currency (config.baseCurrency; nil = that default).
public struct Expense: Codable, Identifiable {
    public let id: UUID
    public let date: String       // ISO "YYYY-MM-DD"
    public let amount: Double      // positive = spent
    public let category: String    // e.g. "Dining", "Rent", "Shopping"
    public let note: String?

    public init(id: UUID = UUID(), date: String, amount: Double,
                category: String, note: String? = nil) {
        self.id = id
        self.date = date
        self.amount = amount
        self.category = category
        self.note = note
    }

    public var day: Date? { parseISODate(date) }
}

/// A monthly spending limit for one category. `limit` is the cap per calendar
/// month; Pulse always reports what's LEFT, not just what's spent.
public struct Budget: Codable, Identifiable {
    public var id: String { category }
    public let category: String
    public let limit: Double

    public init(category: String, limit: Double) {
        self.category = category
        self.limit = limit
    }
}

/// A concrete savings goal — the thing spending is traded off against. Every
/// purchase can be shown as "N% of your goal" / "delays it by N days", which
/// reframes a spend as taking from your future self.
public struct SavingsGoal: Codable {
    public let name: String        // e.g. "Rebuild emergency fund"
    public let target: Double       // total amount to reach
    public let saved: Double        // already put aside toward it
    public let monthlyContribution: Double // what you add per month on plan
    public let targetDate: String?  // optional ISO "YYYY-MM-DD" you want it by

    public init(name: String, target: Double, saved: Double,
                monthlyContribution: Double, targetDate: String? = nil) {
        self.name = name
        self.target = target
        self.saved = saved
        self.monthlyContribution = monthlyContribution
        self.targetDate = targetDate
    }

    public var remaining: Double { max(0, target - saved) }
    public var progressFraction: Double { target > 0 ? min(1, saved / target) : 0 }
    /// Months to reach the goal at the planned contribution.
    public var monthsToGoal: Double? {
        monthlyContribution > 0 ? remaining / monthlyContribution : nil
    }
}

/// The whole spend-side dataset, persisted to spending.json.
public struct SpendData: Codable {
    public var expenses: [Expense]
    public var budgets: [Budget]
    public var goal: SavingsGoal?

    public init(expenses: [Expense] = [], budgets: [Budget] = [], goal: SavingsGoal? = nil) {
        self.expenses = expenses
        self.budgets = budgets
        self.goal = goal
    }
}

public enum SpendStore {
    public static var fileURL: URL {
        Portfolio.dirURL.appendingPathComponent("spending.json")
    }
    public static var exampleURL: URL {
        Portfolio.dirURL.appendingPathComponent("spending.example.json")
    }

    /// Load spend data; seed from the example on first run so there's always a
    /// hand-editable file (mirrors Portfolio.load).
    public static func load(from url: URL = fileURL) -> SpendData {
        let fm = FileManager.default
        if url == fileURL, !fm.fileExists(atPath: url.path),
           fm.fileExists(atPath: exampleURL.path) {
            try? fm.copyItem(at: exampleURL, to: url)
        }
        guard let data = try? Data(contentsOf: url),
              let d = try? JSONDecoder().decode(SpendData.self, from: data)
        else { return SpendData() }
        return d
    }

    public static func save(_ data: SpendData, to url: URL = fileURL) {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let out = try? enc.encode(data) {
            try? out.write(to: url, options: .atomic)
        }
    }

    public static func addExpense(_ e: Expense, to url: URL = fileURL) {
        var d = load(from: url)
        d.expenses.append(e)
        save(d, to: url)
    }

    public static func removeExpense(id: UUID, from url: URL = fileURL) {
        var d = load(from: url)
        d.expenses.removeAll { $0.id == id }
        save(d, to: url)
    }
}
