import Foundation

// MARK: - Savings / investing benchmark
//
// "How much SHOULD I have saved by now, and how much should I be putting
// away?" answered two honest ways side by side ([[project_life_app_benchmarks]]):
//
//   1. Expenses-based (location-honest): the nest egg you need is your real
//      annual expenses MINUS the guaranteed state benefit you'll get, all
//      divided by the 4% safe-withdrawal rate (×25). Uses YOUR spending and
//      YOUR country's benefit — no country adjustment factor needed.
//   2. Salary-multiple (Fidelity-style): a simple age × salary rule of thumb,
//      shown as a cross-check. US-centric; labelled as such.
//
// Pure and testable — no I/O, no SwiftUI. Every assumption is named so a number
// is never presented as more certain than it is. Real over invented: the state
// benefits are actual programme estimates, labelled, not guesses.

public struct Benchmark {

    /// Estimated annual GUARANTEED retirement income from the state — the part
    /// you do NOT have to self-fund — EARNED by contributions/residency, not
    /// assumed. This is the correction that matters for someone on a short work
    /// permit: a few years in-country earns little-to-no state pension, so the
    /// benefit scales honestly toward zero rather than handing you a median
    /// figure you won't actually get.
    ///
    ///   Canada — CPP scales with contribution years (keep-what-you-earned,
    ///            not residency-based); OAS needs 10 residency years to collect
    ///            ANYTHING and 40 for the full amount → 0 below 10, linear to 40.
    ///   US     — Social Security needs ~10 years (40 credits) for ANY benefit
    ///            → 0 below 10, then scales up.
    /// Estimates in local currency, surfaced AS estimates; refine against the
    /// official calculators. Totalization agreements (which can combine years
    /// across countries) are noted in the card, not silently assumed.
    public static func annualStateBenefit(_ profile: Profile) -> Double {
        let contribYears = profile.pensionContributionYears ?? 0
        let residencyYears = profile.residencyYears ?? contribYears

        switch profile.country {
        case .canada:
            // CPP: full ~contribution over ~39 years; scale linearly, capped.
            let cppFull = 12_000.0                      // ~median-ish full CPP, CAD/yr
            let cpp = cppFull * min(1.0, Double(contribYears) / 39.0)
            // OAS: nothing under 10 residency years; linear 10→40 to full.
            let oasFull = 8_500.0                       // ~full OAS, CAD/yr
            let oas = residencyYears < 10 ? 0
                : oasFull * min(1.0, Double(residencyYears) / 40.0)
            return cpp + oas
        case .unitedStates:
            // Social Security: nothing under ~10 years (40 credits).
            guard contribYears >= 10 else { return 0 }
            let ssFull = 22_000.0                        // ~median SS, USD/yr (35 yrs)
            return ssFull * min(1.0, Double(contribYears) / 35.0)
        case .other:
            return 0        // conservative: assume self-funded
        }
    }

    /// Fidelity-style age → salary-multiple target (total saved ÷ salary).
    /// Interpolated between the published anchor ages.
    public static func salaryMultipleTarget(age: Int) -> Double {
        let anchors: [(Int, Double)] = [
            (30, 1), (35, 2), (40, 3), (45, 4),
            (50, 6), (55, 7), (60, 8), (67, 10),
        ]
        if age <= anchors.first!.0 { return anchors.first!.1 * Double(age) / 30.0 }
        if age >= anchors.last!.0 { return anchors.last!.1 }
        for i in 0..<(anchors.count - 1) {
            let (a0, m0) = anchors[i], (a1, m1) = anchors[i + 1]
            if age >= a0 && age <= a1 {
                let t = Double(age - a0) / Double(a1 - a0)
                return m0 + (m1 - m0) * t
            }
        }
        return anchors.last!.1
    }

    /// A longevity nudge: women statistically fund a longer retirement, so the
    /// target is modestly higher for the same age. Surfaced as an explicit,
    /// LABELLED factor — never baked in silently.
    public static func longevityFactor(_ gender: Gender) -> Double {
        switch gender {
        case .female: return 1.08   // ~longer life expectancy → larger nest egg
        case .male, .unspecified: return 1.0
        }
    }

    public struct Result {
        // Inputs echoed back so the card can show its work.
        public let annualExpenses: Double
        public let stateBenefit: Double
        public let currentSaved: Double

        // Method 1 — expenses ÷ 4% (the location-honest nest-egg target).
        public let expenseBasedTarget: Double
        // Method 2 — Fidelity salary-multiple (cross-check). nil w/o salary+age.
        public let salaryMultiple: Double?
        public let salaryBasedTarget: Double?

        /// Recommended annual amount to save/invest (~15% of salary rule).
        public let recommendedAnnualSaving: Double?
        /// Emergency fund target: 3–6 months of expenses (we show the 6-mo end).
        public let emergencyFundTarget: Double

        public let notes: [String]

        /// How the current saved amount compares to the expense-based target.
        public var fractionOfTarget: Double {
            expenseBasedTarget > 0 ? currentSaved / expenseBasedTarget : 0
        }
        public var onTrack: Bool { fractionOfTarget >= 0.9 }
    }

    /// Compute the benchmark. `annualExpenses` should be the user's real yearly
    /// spend (Kelo derives it from SpendService); `currentSaved` is what they
    /// actually hold (portfolio + cash).
    public static func compute(profile: Profile,
                               annualExpenses: Double,
                               currentSaved: Double) -> Result {
        let benefit = annualStateBenefit(profile)
        let longevity = longevityFactor(profile.gender)
        var notes: [String] = []

        // Method 1: (expenses − state benefit) × 25, longevity-adjusted.
        let fundedGap = max(0, annualExpenses - benefit)
        let expenseTarget = fundedGap * 25 * longevity
        notes.append("Nest-egg target = (your \(whole(annualExpenses)) yearly spending − ~\(whole(benefit)) est. \(benefitName(profile.country))) × 25 (the 4% rule).")
        // The residency/contribution caveat — the thing that bites on a short
        // work permit.
        let contrib = profile.pensionContributionYears ?? 0
        let residency = profile.residencyYears ?? contrib
        if benefit == 0 {
            notes.append("State benefit estimated at $0: \(shortStayReason(profile.country, contrib: contrib, residency: residency)) You may still keep contributions or bridge years via a totalization agreement — check the official calculator.")
        } else if contrib < 20 || residency < 20 {
            notes.append("State benefit is REDUCED for a shorter stay (\(contrib) contribution yrs, \(residency) residency yrs) — not the median. On a work permit you often self-fund most of retirement.")
        }
        if longevity != 1.0 {
            notes.append("Adjusted ×\(String(format: "%.2f", longevity)) for longer life expectancy — an estimate, not a certainty.")
        }

        // Method 2: Fidelity salary-multiple.
        var multiple: Double? = nil
        var salaryTarget: Double? = nil
        var recommendedSaving: Double? = nil
        if let age = profile.age, let salary = profile.annualSalary, salary > 0 {
            let m = salaryMultipleTarget(age: age)
            multiple = m
            salaryTarget = m * salary
            recommendedSaving = salary * 0.15
            notes.append("Salary-multiple cross-check: at \(age), the rule of thumb is ~\(String(format: "%.1f", m))× salary saved (US-centric — a sanity check, not the primary target).")
        } else {
            notes.append("Add your age and salary to profile.json for the salary-multiple cross-check and the 15%-of-income saving target.")
        }

        let emergency = annualExpenses / 12.0 * 6.0

        return Result(annualExpenses: annualExpenses,
                      stateBenefit: benefit,
                      currentSaved: currentSaved,
                      expenseBasedTarget: expenseTarget,
                      salaryMultiple: multiple,
                      salaryBasedTarget: salaryTarget,
                      recommendedAnnualSaving: recommendedSaving,
                      emergencyFundTarget: emergency,
                      notes: notes)
    }

    private static func benefitName(_ country: Country) -> String {
        switch country {
        case .canada: return "CPP + OAS"
        case .unitedStates: return "Social Security"
        case .other: return "state benefit"
        }
    }

    /// Why a short stay earns $0, in plain terms, per country.
    private static func shortStayReason(_ country: Country, contrib: Int, residency: Int) -> String {
        switch country {
        case .canada:
            return "Canada's OAS needs 10 residency years to pay anything (you have \(residency)), and CPP with \(contrib) contribution years is small."
        case .unitedStates:
            return "US Social Security needs ~10 years / 40 credits to pay anything (you have \(contrib))."
        case .other:
            return "no state pension assumed."
        }
    }

    /// Whole-dollar string without currency symbol drift — the card adds the
    /// symbol. (Avoids `Int.formatted()` colliding with Duration APIs.)
    private static func whole(_ v: Double) -> String {
        let n = NumberFormatter()
        n.numberStyle = .decimal
        n.maximumFractionDigits = 0
        return n.string(from: NSNumber(value: v)) ?? String(Int(v))
    }
}
