import Foundation

// MARK: - Health domain
//
// Kelo's body side. Same principles as the wealth side ([[Spending.swift]]):
// on-device, gitignored, honest, and it never acts on its own — you log a
// day, or a wearable export is imported; Kelo only reads it back and puts it
// beside your money. No auto-anything.
//
// The health day is deliberately COARSE to start: a handful of signals that
// actually move how you feel and perform (sleep, resting HR, a readiness/
// energy self-rating, and the training LOAD you put in). Richer domains —
// DNA, the injury map, per-workout movement (Strava-style GPS) — hang off
// this same date key as they land, so the composite ([[DayState.swift]]) can
// fuse body + money for a single "how are you set up today" reading.
//
// Files (gitignored, in ~/Documents/stock-tracker):
//   health.json — { days: [HealthDay] }

/// One recorded day of body signals, keyed the same way money is
/// (`isoDateString`, America/New_York) so a health day and a `DailySnapshot`
/// line up 1:1 for correlation. Every field is optional: a day you only
/// logged sleep is still a valid day, and the composite degrades honestly
/// rather than inventing the blanks.
public struct HealthDay: Codable, Identifiable, Equatable {
    public var id: String { date }
    public let date: String            // "YYYY-MM-DD"
    /// Hours slept last night (e.g. 7.5). nil = not logged.
    public var sleepHours: Double?
    /// Resting heart rate, bpm. Lower vs. your own baseline = better recovered.
    public var restingHR: Double?
    /// Self-rated readiness/energy 1–10 — the one honest subjective signal.
    public var readiness: Int?
    /// Training load put in today (see `TrainingSession`). Empty = a rest day,
    /// which is data, not a gap.
    public var sessions: [TrainingSession]

    public init(date: String, sleepHours: Double? = nil, restingHR: Double? = nil,
                readiness: Int? = nil, sessions: [TrainingSession] = []) {
        self.date = date
        self.sleepHours = sleepHours
        self.restingHR = restingHR
        self.readiness = readiness
        self.sessions = sessions
    }

    public var day: Date? { parseISODate(date) }

    /// Total training load for the day — the simple, honest product of how
    /// long and how hard (RPE 1–10). Minutes × RPE, summed. A 60-min session
    /// at RPE 8 = 480; a 20-min easy row at RPE 3 = 60.
    public var trainingLoad: Double {
        sessions.reduce(0) { $0 + Double($1.minutes) * Double($1.rpe) }
    }

    public var didTrain: Bool { !sessions.isEmpty }
}

/// One bout of movement. Kind is free enough to cover CrossFit WODs, a run,
/// a lift, a row — later, a GPS-tracked session (Strava-style) attaches its
/// route/distance here without changing the shape.
public struct TrainingSession: Codable, Identifiable, Equatable {
    public let id: UUID
    public let kind: String            // "CrossFit", "Run", "Lift", "Row"…
    public let minutes: Int
    /// Rate of Perceived Exertion, 1 (trivial) – 10 (maximal).
    public let rpe: Int
    /// Optional distance in km for movement sessions (runs/rides). nil = not
    /// a distance sport, or not tracked.
    public var distanceKm: Double?
    public let note: String?

    public init(id: UUID = UUID(), kind: String, minutes: Int, rpe: Int,
                distanceKm: Double? = nil, note: String? = nil) {
        self.id = id
        self.kind = kind
        self.minutes = minutes
        self.rpe = max(1, min(10, rpe))
        self.distanceKm = distanceKm
        self.note = note
    }
}

/// The whole body-side dataset, persisted to health.json.
public struct HealthData: Codable {
    public var days: [HealthDay]

    public init(days: [HealthDay] = []) { self.days = days }

    /// Most recent logged day, if any.
    public var latest: HealthDay? {
        days.max { $0.date < $1.date }
    }

    /// Baseline resting HR from the trailing `window` logged values — the
    /// number a single day is only meaningful AGAINST. nil until there's
    /// enough history to be honest about it.
    public func restingHRBaseline(window: Int = 14) -> Double? {
        let vals = days.sorted { $0.date < $1.date }.suffix(window).compactMap(\.restingHR)
        guard vals.count >= 3 else { return nil }
        return vals.reduce(0, +) / Double(vals.count)
    }

    /// Trailing training load over `days` days ending today — the "how much
    /// have I been asking of my body lately" number that a rest day should be
    /// read against.
    public func recentLoad(days windowDays: Int = 7, asOf date: Date = Date()) -> Double {
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -windowDays, to: date)
        else { return 0 }
        return days.filter { ($0.day ?? .distantPast) > cutoff }
            .reduce(0) { $0 + $1.trainingLoad }
    }
}

public enum HealthStore {
    public static var fileURL: URL {
        Portfolio.dirURL.appendingPathComponent("health.json")
    }
    public static var exampleURL: URL {
        Portfolio.dirURL.appendingPathComponent("health.example.json")
    }

    /// Load body data; seed from the example on first run so there's always a
    /// hand-editable file (mirrors `SpendStore.load` / `Portfolio.load`).
    public static func load(from url: URL = fileURL) -> HealthData {
        let fm = FileManager.default
        if url == fileURL, !fm.fileExists(atPath: url.path),
           fm.fileExists(atPath: exampleURL.path) {
            try? fm.copyItem(at: exampleURL, to: url)
        }
        guard let data = try? Data(contentsOf: url),
              let d = try? JSONDecoder().decode(HealthData.self, from: data)
        else { return HealthData() }
        return d
    }

    public static func save(_ data: HealthData, to url: URL = fileURL) {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let out = try? enc.encode(data) {
            try? out.write(to: url, options: .atomic)
        }
    }

    /// Upsert a day (last write for a date wins) and keep the list sorted —
    /// the same contract as `SnapshotStore.upsert`, so re-logging today just
    /// updates it rather than duplicating.
    public static func upsert(_ day: HealthDay, to url: URL = fileURL) {
        var d = load(from: url)
        d.days.removeAll { $0.date == day.date }
        d.days.append(day)
        d.days.sort { $0.date < $1.date }
        save(d, to: url)
    }
}
