import Foundation

// MARK: - SpendService
//
// The spend-CONTROL logic, not just reporting. Four mechanisms the user asked
// for, all as pure functions (fully testable, no I/O):
//   1. Budgets + live "left this month" (shows what's LEFT, not just spent)
//   2. Pre-spend "can I afford this?" check (budget left + goal delay + savings
//      impact — the trade-off made visible at decision time)
//   3. Savings-goal reframing (a spend as % of the goal / days it delays it)
//   4. Under-budget streak (honest accountability over time)
//
// Honest by design: this makes the cost visible before you spend. It can't force
// restraint — the choice stays yours (same principle as Pulse never trading).

public enum SpendService {

    // MARK: Calendar helpers (current month window)

    /// Start of the current calendar month.
    public static func monthStart(_ now: Date = Date(), calendar: Calendar = .current) -> Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
    }
    /// Days elapsed in the current month (1-based) and total days in the month.
    public static func monthProgress(_ now: Date = Date(), calendar: Calendar = .current) -> (dayOfMonth: Int, daysInMonth: Int) {
        let day = calendar.component(.day, from: now)
        let range = calendar.range(of: .day, in: .month, for: now)?.count ?? 30
        return (day, range)
    }

    /// Expenses that fall in the current calendar month.
    public static func thisMonthExpenses(_ expenses: [Expense], now: Date = Date(), calendar: Calendar = .current) -> [Expense] {
        let start = monthStart(now, calendar: calendar)
        return expenses.filter { e in
            guard let d = e.day else { return false }
            return d >= start && d <= now
        }
    }

    // MARK: 1 + 3. Budget status per category ("left this month")

    public struct BudgetStatus {
        public let category: String
        public let limit: Double
        public let spent: Double
        public var left: Double { max(0, limit - spent) }
        public var fraction: Double { limit > 0 ? spent / limit : 0 }
        public var over: Bool { spent > limit }
        /// Burning too fast: fraction of budget used already exceeds the fraction
        /// of the month elapsed (e.g. 87% spent on the 12th).
        public let paceHot: Bool
    }

    /// Month-to-date status for every budget, plus an "Uncategorised" catch-all
    /// for spending in categories that have no budget.
    public static func budgetStatuses(_ data: SpendData, now: Date = Date(), calendar: Calendar = .current) -> [BudgetStatus] {
        let month = thisMonthExpenses(data.expenses, now: now, calendar: calendar)
        let byCat = Dictionary(grouping: month, by: { $0.category })
            .mapValues { $0.reduce(0) { $0 + $1.amount } }
        let (dayOfMonth, daysInMonth) = monthProgress(now, calendar: calendar)
        let monthFrac = daysInMonth > 0 ? Double(dayOfMonth) / Double(daysInMonth) : 1

        var out: [BudgetStatus] = data.budgets.map { b in
            let spent = byCat[b.category] ?? 0
            let frac = b.limit > 0 ? spent / b.limit : 0
            return BudgetStatus(category: b.category, limit: b.limit, spent: spent,
                                paceHot: frac > monthFrac + 0.15 && frac < 1)
        }
        // categories with spend but no budget → surfaced so nothing hides
        let budgeted = Set(data.budgets.map { $0.category })
        for (cat, spent) in byCat where !budgeted.contains(cat) {
            out.append(BudgetStatus(category: cat, limit: 0, spent: spent, paceHot: false))
        }
        return out.sorted { $0.spent > $1.spent }
    }

    /// Total spent this month + total budgeted.
    public static func monthTotals(_ data: SpendData, now: Date = Date(), calendar: Calendar = .current) -> (spent: Double, budgeted: Double) {
        let spent = thisMonthExpenses(data.expenses, now: now, calendar: calendar).reduce(0) { $0 + $1.amount }
        let budgeted = data.budgets.reduce(0) { $0 + $1.limit }
        return (spent, budgeted)
    }

    // MARK: 2. Pre-spend "can I afford this?" check

    public struct AffordCheck {
        public let amount: Double
        public let category: String?
        /// Budget left in that category BEFORE this spend (nil if no budget set).
        public let categoryLeftBefore: Double?
        /// Would this spend blow the category budget?
        public let breaksBudget: Bool
        /// Days this spend pushes the savings goal later (nil if no goal).
        public let goalDelayDays: Int?
        /// This spend as a fraction of the whole goal (nil if no goal).
        public let goalFraction: Double?
        /// A blunt verdict line in Pulse's voice.
        public let verdict: String
    }

    /// The decision-time check: "I'm thinking of spending $X on <category>."
    public static func canAfford(amount: Double, category: String?, data: SpendData,
                                 now: Date = Date(), calendar: Calendar = .current) -> AffordCheck {
        // category budget headroom
        var catLeft: Double? = nil
        var breaks = false
        if let cat = category, let b = data.budgets.first(where: { $0.category == cat }) {
            let statuses = budgetStatuses(data, now: now, calendar: calendar)
            let spent = statuses.first(where: { $0.category == cat })?.spent ?? 0
            let left = max(0, b.limit - spent)
            catLeft = left
            breaks = amount > left
        }
        // goal impact: this spend is money NOT saved → it delays the goal by
        // amount / monthlyContribution of a month, in days.
        var delayDays: Int? = nil
        var goalFrac: Double? = nil
        if let g = data.goal {
            if g.target > 0 { goalFrac = amount / g.target }
            if g.monthlyContribution > 0 {
                let monthsDelayed = amount / g.monthlyContribution
                delayDays = Int((monthsDelayed * 30.44).rounded())
            }
        }
        // verdict
        let verdict: String
        if breaks, let left = catLeft, let cat = category {
            verdict = "Over budget — only \(money(left)) left in \(cat) this month. Skip it or move it."
        } else if let dd = delayDays, dd >= 1, let g = data.goal {
            verdict = "You can — but it pushes '\(g.name)' back \(dd) day\(dd == 1 ? "" : "s")."
        } else if let left = catLeft {
            verdict = "Fits — \(money(left - amount)) would be left in the budget after."
        } else {
            verdict = "No budget set for this — log it so it counts."
        }
        return AffordCheck(amount: amount, category: category,
                           categoryLeftBefore: catLeft, breaksBudget: breaks,
                           goalDelayDays: delayDays, goalFraction: goalFrac,
                           verdict: verdict)
    }

    // MARK: 4. Under-budget streak + monthly scorecard

    /// Consecutive days (ending today) where that day's logged spend was under
    /// the daily-average budget (total monthly budget / days in month). A simple,
    /// honest "restraint streak".
    public static func underBudgetStreak(_ data: SpendData, now: Date = Date(), calendar: Calendar = .current) -> Int {
        let (_, daysInMonth) = monthProgress(now, calendar: calendar)
        let dailyBudget = daysInMonth > 0 ? data.budgets.reduce(0) { $0 + $1.limit } / Double(daysInMonth) : 0
        guard dailyBudget > 0 else { return 0 }
        // sum spend per day
        let byDay = Dictionary(grouping: data.expenses.compactMap { e -> (Date, Double)? in
            e.day.map { (calendar.startOfDay(for: $0), e.amount) }
        }, by: { $0.0 }).mapValues { $0.reduce(0) { $0 + $1.1 } }

        var streak = 0
        var day = calendar.startOfDay(for: now)
        while true {
            let spent = byDay[day] ?? 0
            if spent <= dailyBudget { streak += 1 } else { break }
            guard let prev = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = prev
            // stop after a month of look-back
            if streak >= 60 { break }
        }
        return streak
    }

    public struct Scorecard {
        public let spent: Double
        public let budgeted: Double
        public var savedVsBudget: Double { budgeted - spent } // + = under budget
        public let biggestLeakCategory: String?
        public let biggestLeakOver: Double // amount over budget in that category
        public let verdict: String
    }

    /// A blunt end-of-view verdict in Pulse's direct voice — names the single
    /// biggest leak rather than a wall of numbers.
    public static func scorecard(_ data: SpendData, now: Date = Date(), calendar: Calendar = .current) -> Scorecard {
        let totals = monthTotals(data, now: now, calendar: calendar)
        let statuses = budgetStatuses(data, now: now, calendar: calendar)
        // Find the single biggest over-budget category (broken into explicit
        // steps so the type-checker stays fast + the intent is obvious).
        var leakCategory: String? = nil
        var leakOver: Double = 0
        for s in statuses where s.over && s.limit > 0 {
            let over = s.spent - s.limit
            if over > leakOver {
                leakOver = over
                leakCategory = s.category
            }
        }
        let verdict: String
        if let cat = leakCategory {
            verdict = "\(cat) is your leak — \(money(leakOver)) over budget this month. Fix that one thing."
        } else if totals.spent <= totals.budgeted {
            verdict = "Under budget so far. Keep it boring."
        } else {
            verdict = "Over budget overall — tighten up before month-end."
        }
        return Scorecard(spent: totals.spent, budgeted: totals.budgeted,
                         biggestLeakCategory: leakCategory, biggestLeakOver: leakOver,
                         verdict: verdict)
    }

    // small local money formatter (kept independent of Format.swift's currency)
    private static func money(_ v: Double) -> String {
        let n = NumberFormatter()
        n.numberStyle = .decimal
        n.maximumFractionDigits = v.truncatingRemainder(dividingBy: 1) == 0 ? 0 : 2
        return "$" + (n.string(from: NSNumber(value: v)) ?? String(format: "%.0f", v))
    }
}
