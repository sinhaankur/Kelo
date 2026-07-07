import Foundation

// MARK: - Mood & Discipline
//
// The "fix my life" layer. Two things Kelo tracks so you can see whether you're
// holding the line: MOOD (how you actually feel — the subjective signal that
// ties body + money to your day) and DISCIPLINE (streaks across the habits that
// matter). Everything is related, so these feed the same DayState composite.
//
// Honest + user-action-only: Kelo shows the pattern and the streak, it never
// nags on its own. You log mood; discipline is COMPUTED from what you already
// track (trained, slept, logged, stayed under budget) — no new logging burden.

/// A daily mood entry — one self-rating plus an optional note, keyed like
/// every other day so it lines up with health, movement, and money.
public struct MoodEntry: Codable, Identifiable, Equatable {
    public var id: String { date }
    public let date: String            // "YYYY-MM-DD"
    /// 1 (low) – 5 (great). Deliberately coarse — a real feeling, not a metric.
    public let mood: Int
    public let note: String?

    public init(date: String, mood: Int, note: String? = nil) {
        self.date = date
        self.mood = max(1, min(5, mood))
        self.note = note
    }

    public var label: String {
        switch mood {
        case 1: return "Low"
        case 2: return "Off"
        case 3: return "Okay"
        case 4: return "Good"
        default: return "Great"
        }
    }
    public var emoji: String {
        switch mood {
        case 1: return "😞"
        case 2: return "😕"
        case 3: return "😐"
        case 4: return "🙂"
        default: return "😄"
        }
    }
}

public enum MoodStore {
    public static var fileURL: URL {
        Portfolio.dirURL.appendingPathComponent("mood.json")
    }
    public static func load(from url: URL = fileURL) -> [MoodEntry] {
        guard let data = try? Data(contentsOf: url),
              let list = try? JSONDecoder().decode([MoodEntry].self, from: data)
        else { return [] }
        return list.sorted { $0.date < $1.date }
    }
    public static func save(_ entries: [MoodEntry], to url: URL = fileURL) {
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let out = try? enc.encode(entries) { try? out.write(to: url, options: .atomic) }
    }
    public static func upsert(_ e: MoodEntry, to url: URL = fileURL) {
        var all = load(from: url).filter { $0.date != e.date }
        all.append(e); all.sort { $0.date < $1.date }
        save(all, to: url)
    }
    public static func today(_ url: URL = fileURL) -> MoodEntry? {
        load(from: url).first { $0.date == isoDateString(Date()) }
    }
}

// MARK: - Discipline (streaks)

/// One tracked habit and how consistently you're holding it. "Fixing your life"
/// = building and keeping these streaks.
public struct Streak: Identifiable {
    public let id: String              // the habit key
    public let title: String
    public let icon: String
    /// Consecutive days (ending today or yesterday) the habit was met.
    public let current: Int
    /// Whether today itself is already met.
    public let metToday: Bool

    public init(id: String, title: String, icon: String, current: Int, metToday: Bool) {
        self.id = id; self.title = title; self.icon = icon
        self.current = current; self.metToday = metToday
    }
}

public enum Discipline {
    /// Compute streaks from the data Kelo already has. A day "counts" for a
    /// habit when its condition holds; the streak is the run of counting days
    /// ending today (or yesterday, so a not-yet-done-today day doesn't break a
    /// live streak). Pure + testable.
    ///
    /// `days` maps "YYYY-MM-DD" → whether the habit was met that day.
    public static func streak(metByDay: [String: Bool], asOf date: Date = Date(),
                              calendar: Calendar = .current) -> (current: Int, metToday: Bool) {
        let today = calendar.startOfDay(for: date)
        let metToday = metByDay[isoDateString(today)] ?? false
        // Start from today if met, else from yesterday, so an unfinished today
        // doesn't zero a real streak.
        var cursor = metToday ? today : (calendar.date(byAdding: .day, value: -1, to: today) ?? today)
        var count = 0
        while true {
            let key = isoDateString(cursor)
            if metByDay[key] == true {
                count += 1
                guard let prev = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
                cursor = prev
            } else { break }
        }
        return (count, metToday)
    }

    /// Build the standard Kelo streaks from health + spend history. Each habit's
    /// per-day "met" map is derived, then streaked. Kept deterministic so it's
    /// unit-tested.
    public static func streaks(health: HealthData, mood: [MoodEntry],
                               asOf date: Date = Date()) -> [Streak] {
        // Trained: any session that day.
        let trained = Dictionary(uniqueKeysWithValues:
            health.days.map { ($0.date, $0.didTrain) })
        // Slept 7h+.
        let slept = Dictionary(uniqueKeysWithValues:
            health.days.map { ($0.date, ($0.sleepHours ?? 0) >= 7) })
        // Logged mood at all.
        let logged = Dictionary(uniqueKeysWithValues: mood.map { ($0.date, true) })

        let t = streak(metByDay: trained, asOf: date)
        let s = streak(metByDay: slept, asOf: date)
        let m = streak(metByDay: logged, asOf: date)
        return [
            Streak(id: "trained", title: "Trained", icon: "figure.strengthtraining.traditional",
                   current: t.current, metToday: t.metToday),
            Streak(id: "slept", title: "Slept 7h+", icon: "bed.double.fill",
                   current: s.current, metToday: s.metToday),
            Streak(id: "logged", title: "Checked in", icon: "checkmark.circle.fill",
                   current: m.current, metToday: m.metToday),
        ]
    }
}
