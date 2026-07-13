import Foundation

/// Builds the assistant's grounding Snapshot from Kelo's REAL on-device stores,
/// so the assistant is wired to live data — not a disconnected library.
///
/// The store-backed fields (day-state, rings, spend, savings, mood) are all
/// synchronous + on-device, so this is pure and testable with injected stores.
/// Portfolio value + holdings need live quotes (async, app layer), so the
/// caller passes those in when it has them; without them the assistant simply
/// doesn't mention the portfolio (honest — it only states what's known).
extension AssistantService.Snapshot {

    /// Assemble from the real stores. Every argument defaults to the live store
    /// load, so the app calls `.fromStores()` and tests inject fixtures.
    public static func fromStores(
        health: HealthData = HealthStore.load(),
        movement: MovementDay? = MovementStore.today(),
        spend: SpendData = SpendStore.load(),
        moodEntry: MoodEntry? = MoodStore.today(),
        profile: Profile = ProfileStore.load(),
        notes: [String] = NoteStore.contextLines(),
        currency: String = "USD",
        // App-layer extras (need live quotes) — optional.
        portfolioValue: Double? = nil,
        portfolioDayChangePct: Double? = nil,
        currentSaved: Double? = nil,
        topHoldings: [String] = []
    ) -> AssistantService.Snapshot {
        var s = AssistantService.Snapshot(currency: currency)
        s.notes = notes

        // ── Rings (the same real calls the dashboard makes) ──────────────
        let totals = SpendService.monthTotals(spend)
        let mood = MoodStore.load()
        let streaks = Discipline.streaks(health: health, mood: mood)
        let trainedToday = health.days.first { $0.date == isoDateString(Date()) }?.didTrain ?? false
        let rings = Rings.all(movement: movement, trainedToday: trainedToday,
                              spentThisMonth: totals.spent, budgeted: totals.budgeted,
                              streaks: streaks)
        for r in rings where r.hasData {
            switch r.kind {
            case .body:       s.bodyRingLabel = r.label; s.bodyRingFraction = r.fraction
            case .money:      s.moneyRingLabel = r.label; s.moneyRingFraction = r.fraction
            case .discipline: s.disciplineRingLabel = r.label; s.disciplineRingFraction = r.fraction
            }
        }

        // ── Day state (body + money + mood composite) ────────────────────
        // spendVsBudget: fraction of budget spent (1.0 = exactly on budget).
        let spendFraction = totals.budgeted > 0 ? totals.spent / totals.budgeted : nil
        let day = DayState(.init(
            today: movementToday(health),
            portfolioDayFraction: portfolioDayChangePct.map { $0 / 100 },
            spendVsBudget: spendFraction,
            mood: moodEntry?.mood
        ))
        s.dayStanding = day.standing.rawValue
        s.dayHeadline = day.headline
        s.dayReasons = day.reasons.map(\.text)

        // ── Spending ─────────────────────────────────────────────────────
        if totals.budgeted > 0 {
            s.spentThisMonth = totals.spent
            s.budgetedThisMonth = totals.budgeted
        }

        // ── Mood valence (MoodEntry is 1…5 → map to −2…+2) ───────────────
        if let m = moodEntry { s.moodValence = m.mood - 3 }

        // ── Savings benchmark (residency-honest target) ──────────────────
        // Annual expenses estimated from this month's budget × 12 (Kelo's
        // simplest honest annualisation from the numbers on hand).
        if let saved = currentSaved, totals.budgeted > 0 {
            let annualExpenses = totals.budgeted * 12
            let bench = Benchmark.compute(profile: profile,
                                          annualExpenses: annualExpenses,
                                          currentSaved: saved)
            s.savingsFractionOfTarget = bench.fractionOfTarget
            s.savingsOnTrack = bench.onTrack
        }

        // ── Portfolio (app-layer, live quotes) ───────────────────────────
        s.portfolioValue = portfolioValue
        s.portfolioDayChangePct = portfolioDayChangePct
        s.topHoldings = topHoldings

        return s
    }

    /// The most recent HealthDay, used for the DayState body signals.
    private static func movementToday(_ health: HealthData) -> HealthDay? {
        let today = isoDateString(Date())
        return health.days.first { $0.date == today } ?? health.days.last
    }
}
