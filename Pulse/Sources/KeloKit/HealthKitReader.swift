import Foundation

// MARK: - HealthKit reader (iOS / iPadOS)
//
// The reason Kelo goes to the phone at all: Apple Health is where the real
// sleep / resting-HR / workout data already lives, and the Mac can't read it.
// This reader pulls that data and maps it straight onto the `HealthDay` the
// rest of Kelo already understands ([[Health.swift]]) — so the composite
// ([[DayState.swift]]) is fed by REAL measurements instead of hand-logging.
//
// Strictly opt-in ([[feedback_user_action_only]]): nothing is read until the
// user grants per-type read permission, and Kelo only ever READS Health data —
// it never writes back. On platforms without HealthKit (macOS, Linux) this
// compiles to a stub that reports "unavailable", so shared code stays simple.

public struct HealthKitDay {
    public let sleepHours: Double?
    public let restingHR: Double?
    public let workouts: [TrainingSession]
    public init(sleepHours: Double?, restingHR: Double?, workouts: [TrainingSession]) {
        self.sleepHours = sleepHours
        self.restingHR = restingHR
        self.workouts = workouts
    }

    /// Fold today's Apple Health reading into a `HealthDay`, preserving any
    /// self-rated `readiness` the user already entered (Health can't know that).
    public func merged(into existing: HealthDay?, date: String) -> HealthDay {
        HealthDay(
            date: date,
            sleepHours: sleepHours ?? existing?.sleepHours,
            restingHR: restingHR ?? existing?.restingHR,
            readiness: existing?.readiness,
            sessions: workouts.isEmpty ? (existing?.sessions ?? []) : workouts)
    }
}

public enum HealthKitError: Error, Equatable {
    case unavailable          // no HealthKit on this platform/device
    case notAuthorized        // user hasn't granted read access
}

#if canImport(HealthKit)
import HealthKit

/// Reads Apple Health into Kelo. Actor-isolated so the HKHealthStore is
/// touched from one place; all queries are read-only.
public final class HealthKitReader {
    private let store = HKHealthStore()

    public init() {}

    public static var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    /// The read types Kelo asks for — the minimum that feeds the composite.
    private var readTypes: Set<HKObjectType> {
        var t: Set<HKObjectType> = []
        if let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) { t.insert(sleep) }
        if let hr = HKObjectType.quantityType(forIdentifier: .restingHeartRate) { t.insert(hr) }
        t.insert(HKObjectType.workoutType())
        return t
    }

    /// Ask the user for read access. Returns only after they've decided; the
    /// system sheet is the consent gate — Kelo never reads before this.
    public func requestAuthorization() async throws {
        guard Self.isAvailable else { throw HealthKitError.unavailable }
        try await store.requestAuthorization(toShare: [], read: readTypes)
    }

    /// Read a single day's signals (defaults to today, in the user's calendar).
    public func read(day date: Date = Date(),
                     calendar: Calendar = .current) async throws -> HealthKitDay {
        guard Self.isAvailable else { throw HealthKitError.unavailable }
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? date

        async let sleep = readSleepHours(start: start, end: end)
        async let hr = readRestingHR(start: start, end: end)
        async let workouts = readWorkouts(start: start, end: end)
        return HealthKitDay(sleepHours: try await sleep,
                            restingHR: try await hr,
                            workouts: try await workouts)
    }

    // MARK: individual queries

    private func readSleepHours(start: Date, end: Date) async throws -> Double? {
        guard let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return nil }
        let samples = try await categorySamples(type: type, start: start, end: end)
        // Sum time in any "asleep" stage; ignore "in bed" / "awake".
        let asleep = samples.filter { s in
            if #available(iOS 16.0, *) {
                return HKCategoryValueSleepAnalysis(rawValue: s.value)?.isAsleep ?? false
            } else {
                return s.value == HKCategoryValueSleepAnalysis.asleep.rawValue
            }
        }
        guard !asleep.isEmpty else { return nil }
        let seconds = asleep.reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
        return seconds / 3600.0
    }

    private func readRestingHR(start: Date, end: Date) async throws -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: .restingHeartRate) else { return nil }
        let stats = try await statistics(type: type, start: start, end: end, options: .discreteAverage)
        guard let q = stats?.averageQuantity() else { return nil }
        return q.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
    }

    private func readWorkouts(start: Date, end: Date) async throws -> [TrainingSession] {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let workouts: [HKWorkout] = try await withCheckedThrowingContinuation { cont in
            let q = HKSampleQuery(sampleType: .workoutType(), predicate: predicate,
                                  limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
                if let error { cont.resume(throwing: error); return }
                cont.resume(returning: (samples as? [HKWorkout]) ?? [])
            }
            store.execute(q)
        }
        return workouts.map { w in
            let minutes = Int((w.duration / 60).rounded())
            // Apple Health has no RPE; leave a neutral-moderate 5 for the load
            // math and let the user adjust — honest placeholder, not a guess
            // dressed as measured.
            let meters: Double?
            if #available(iOS 16.0, *) {
                meters = w.statistics(for: HKQuantityType(.distanceWalkingRunning))?
                    .sumQuantity()?.doubleValue(for: .meter())
            } else {
                meters = w.totalDistance?.doubleValue(for: .meter())
            }
            let km = meters.map { $0 / 1000 }
            return TrainingSession(kind: Self.name(for: w.workoutActivityType),
                                   minutes: max(1, minutes), rpe: 5,
                                   distanceKm: km, note: "from Apple Health")
        }
    }

    // MARK: query helpers

    private func categorySamples(type: HKCategoryType, start: Date, end: Date) async throws -> [HKCategorySample] {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        return try await withCheckedThrowingContinuation { cont in
            let q = HKSampleQuery(sampleType: type, predicate: predicate,
                                  limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
                if let error { cont.resume(throwing: error); return }
                cont.resume(returning: (samples as? [HKCategorySample]) ?? [])
            }
            store.execute(q)
        }
    }

    private func statistics(type: HKQuantityType, start: Date, end: Date,
                            options: HKStatisticsOptions) async throws -> HKStatistics? {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        return try await withCheckedThrowingContinuation { cont in
            let q = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate,
                                      options: options) { _, stats, error in
                if let error { cont.resume(throwing: error); return }
                cont.resume(returning: stats)
            }
            store.execute(q)
        }
    }

    private static func name(for t: HKWorkoutActivityType) -> String {
        switch t {
        case .running: return "Run"
        case .cycling: return "Ride"
        case .swimming: return "Swim"
        case .traditionalStrengthTraining, .functionalStrengthTraining: return "Lift"
        case .rowing: return "Row"
        case .highIntensityIntervalTraining, .crossTraining: return "CrossFit"
        case .flexibility, .yoga, .mindAndBody: return "Mobility"
        default: return "Workout"
        }
    }
}

@available(iOS 16.0, *)
private extension HKCategoryValueSleepAnalysis {
    var isAsleep: Bool {
        switch self {
        case .asleepUnspecified, .asleepCore, .asleepDeep, .asleepREM: return true
        default: return false
        }
    }
}

#else

// Non-HealthKit platforms (macOS desktop, Linux, TUI): a stub with the same
// surface so shared code compiles. The macOS app hand-logs via LogTodaySheet.
public final class HealthKitReader {
    public init() {}
    public static var isAvailable: Bool { false }
    public func requestAuthorization() async throws { throw HealthKitError.unavailable }
    public func read(day date: Date = Date(),
                     calendar: Calendar = .current) async throws -> HealthKitDay {
        throw HealthKitError.unavailable
    }
}

#endif
