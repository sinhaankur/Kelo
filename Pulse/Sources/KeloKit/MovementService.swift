import Foundation

// MARK: - Movement service (Core Motion, iOS/iPadOS/watchOS)
//
// The live "are you sitting, standing, walking, or running right now" signal
// the Watch doesn't auto-classify — from Core Motion (`CMMotionActivityManager`
// for state + confidence, `CMPedometer` for steps/distance). Strictly opt-in:
// motion permission is the gate. Read-only. On macOS this is a stub so the
// shared model compiles.
//
// The service accumulates the day into a `MovementDay` ([[Movement.swift]]),
// which flows into the composite ([[DayState.swift]]) — because in Kelo the
// body and the money are one connected picture, not separate tabs.

public struct MovementReading {
    public let state: ActivityState
    public let steps: Int
    public let distanceKm: Double
    public init(state: ActivityState, steps: Int, distanceKm: Double) {
        self.state = state; self.steps = steps; self.distanceKm = distanceKm
    }
}

public enum MovementError: Error { case unavailable, notAuthorized }

#if canImport(CoreMotion) && !os(macOS)
import CoreMotion

public final class MovementService {
    private let activity = CMMotionActivityManager()
    private let pedometer = CMPedometer()

    public init() {}

    public static var isAvailable: Bool {
        CMMotionActivityManager.isActivityAvailable() && CMPedometer.isStepCountingAvailable()
    }

    /// Live activity state updates (still / walking / running / …). The user
    /// grants motion access via the system prompt on first start.
    public func startLiveUpdates(_ onChange: @escaping (ActivityState) -> Void) {
        guard Self.isAvailable else { return }
        activity.startActivityUpdates(to: .main) { a in
            guard let a else { return }
            onChange(Self.classify(a))
        }
    }

    public func stopLiveUpdates() { activity.stopActivityUpdates() }

    /// Today's steps + distance so far, from midnight.
    public func todaysTotals() async throws -> (steps: Int, distanceKm: Double) {
        guard Self.isAvailable else { throw MovementError.unavailable }
        let start = Calendar.current.startOfDay(for: Date())
        return try await withCheckedThrowingContinuation { cont in
            pedometer.queryPedometerData(from: start, to: Date()) { data, error in
                if let error { cont.resume(throwing: error); return }
                let steps = data?.numberOfSteps.intValue ?? 0
                let meters = data?.distance?.doubleValue ?? 0
                cont.resume(returning: (steps, meters / 1000))
            }
        }
    }

    /// Reconstruct today's sit-vs-move split from the activity history — the
    /// data the Watch doesn't summarise for you. Returns minutes active/sitting.
    public func todaysSitStand() async throws -> (active: Int, sitting: Int) {
        guard Self.isAvailable else { throw MovementError.unavailable }
        let start = Calendar.current.startOfDay(for: Date())
        let events: [CMMotionActivity] = try await withCheckedThrowingContinuation { cont in
            activity.queryActivityStarting(from: start, to: Date(), to: .main) { acts, error in
                if let error { cont.resume(throwing: error); return }
                cont.resume(returning: acts ?? [])
            }
        }
        // Sum the duration of each segment by whether it was stationary.
        var active = 0.0, sitting = 0.0
        for (i, a) in events.enumerated() {
            let end = i + 1 < events.count ? events[i + 1].startDate : Date()
            let mins = end.timeIntervalSince(a.startDate) / 60
            if a.stationary { sitting += mins } else { active += mins }
        }
        return (Int(active), Int(sitting))
    }

    /// Pull a full snapshot and fold it into today's MovementDay (persisted).
    @discardableResult
    public func syncToday() async throws -> MovementDay {
        let totals = try await todaysTotals()
        let split = try await todaysSitStand()
        let day = MovementDay(date: isoDateString(Date()),
                              steps: totals.steps, distanceKm: totals.distanceKm,
                              activeMinutes: split.active, sittingMinutes: split.sitting)
        MovementStore.upsert(day)
        return day
    }

    private static func classify(_ a: CMMotionActivity) -> ActivityState {
        if a.running { return .running }
        if a.walking { return .walking }
        if a.cycling { return .cycling }
        if a.automotive { return .automotive }
        if a.stationary { return .stationary }
        return .unknown
    }
}

#else

public final class MovementService {
    public init() {}
    public static var isAvailable: Bool { false }
    public func startLiveUpdates(_ onChange: @escaping (ActivityState) -> Void) {}
    public func stopLiveUpdates() {}
    public func todaysTotals() async throws -> (steps: Int, distanceKm: Double) { throw MovementError.unavailable }
    public func todaysSitStand() async throws -> (active: Int, sitting: Int) { throw MovementError.unavailable }
    @discardableResult
    public func syncToday() async throws -> MovementDay { throw MovementError.unavailable }
}

#endif
