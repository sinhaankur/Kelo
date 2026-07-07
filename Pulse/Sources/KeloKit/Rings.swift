import Foundation

// MARK: - The three rings
//
// Kelo's day as one glanceable image, Apple-Fitness style: three concentric
// rings you try to close — BODY, MONEY, DISCIPLINE. "Everything is related" made
// literal: one day, three rings. The fractions are pure/testable here; the view
// just draws them.
//
// Each ring is 0…1 (how "closed" it is today) plus a short label. Honest: a ring
// with no data reads as empty (0) with an "add data" hint, never a fake number.

public struct Ring: Identifiable {
    public enum Kind: String { case body, money, discipline }
    public var id: String { kind.rawValue }
    public let kind: Kind
    public let fraction: Double        // 0…1, clamped
    public let label: String           // e.g. "8.2k steps"
    public let hasData: Bool

    public init(kind: Kind, fraction: Double, label: String, hasData: Bool) {
        self.kind = kind
        self.fraction = max(0, min(1, fraction))
        self.label = label
        self.hasData = hasData
    }
}

public enum Rings {

    /// BODY ring — how much you've moved today toward a step goal, blended with
    /// whether you trained. Closes as you move + train.
    public static func body(movement: MovementDay?, trainedToday: Bool,
                            stepGoal: Int = 8000) -> Ring {
        let hasMovement = (movement?.steps ?? 0) > 0 || (movement?.activeMinutes ?? 0) > 0
        guard hasMovement || trainedToday else {
            return Ring(kind: .body, fraction: 0, label: "no movement yet", hasData: false)
        }
        let steps = movement?.steps ?? 0
        let stepFrac = stepGoal > 0 ? Double(steps) / Double(stepGoal) : 0
        // Training gives a meaningful boost — a workout largely closes the ring.
        let frac = min(1, stepFrac * 0.7 + (trainedToday ? 0.5 : 0))
        let label = trainedToday ? "\(steps) steps · trained" : "\(steps) steps"
        return Ring(kind: .body, fraction: frac, label: label, hasData: true)
    }

    /// MONEY ring — closed when you're on-plan: full when spending is at/under
    /// budget, draining as you go over. (A ring you keep closed by NOT
    /// overspending — the opposite pressure to the body ring.)
    public static func money(spentThisMonth: Double, budgeted: Double) -> Ring {
        guard budgeted > 0 else {
            return Ring(kind: .money, fraction: 0, label: "set a budget", hasData: false)
        }
        // 1.0 when spent ≤ budget; falls toward 0 as you exceed it.
        let ratio = spentThisMonth / budgeted
        let frac = ratio <= 1 ? 1 - ratio * 0.15 : max(0, 1 - (ratio - 1))
        let label = ratio <= 1
            ? "on plan"
            : "\(Int((ratio - 1) * 100))% over"
        return Ring(kind: .money, fraction: frac, label: label, hasData: true)
    }

    /// DISCIPLINE ring — the share of today's habits already met (trained /
    /// slept / checked in). Closes as you hold the line.
    public static func discipline(streaks: [Streak]) -> Ring {
        guard !streaks.isEmpty else {
            return Ring(kind: .discipline, fraction: 0, label: "no habits yet", hasData: false)
        }
        let metToday = streaks.filter(\.metToday).count
        let frac = Double(metToday) / Double(streaks.count)
        let bestStreak = streaks.map(\.current).max() ?? 0
        let label = "\(metToday)/\(streaks.count) today"
            + (bestStreak > 1 ? " · \(bestStreak)-day streak" : "")
        return Ring(kind: .discipline, fraction: frac, label: label, hasData: true)
    }

    /// Build all three at once from the day's on-device data.
    public static func all(movement: MovementDay?, trainedToday: Bool,
                           spentThisMonth: Double, budgeted: Double,
                           streaks: [Streak]) -> [Ring] {
        [ body(movement: movement, trainedToday: trainedToday),
          money(spentThisMonth: spentThisMonth, budgeted: budgeted),
          discipline(streaks: streaks) ]
    }
}
