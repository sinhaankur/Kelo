import Foundation

// MARK: - CrossFit / strength
//
// The structured training side, richer than a bare `TrainingSession`: named
// WODs with a result, and personal records for the lifts. Same on-device Store
// pattern as everything else. This is data the user logs — Kelo never invents a
// workout or a PR.

/// How a CrossFit workout is scored — determines what "result" means.
public enum WODScoring: String, Codable, CaseIterable {
    case forTime      // lower is better (e.g. "Fran" in 3:41)
    case amrap        // as many rounds/reps as possible — higher is better
    case load         // a weight (e.g. a heavy single)
    case reps         // total reps

    public var label: String {
        switch self {
        case .forTime: return "For time"
        case .amrap:   return "AMRAP"
        case .load:    return "Load"
        case .reps:    return "Reps"
        }
    }
}

/// One logged workout of the day.
public struct WOD: Codable, Identifiable {
    public let id: UUID
    public let date: String            // ISO "YYYY-MM-DD"
    public let name: String            // "Fran", "Murph", "Back Squat 5x5"…
    public let scoring: WODScoring
    /// The raw result, kept as text so any format works ("3:41", "12 rounds",
    /// "225 lb"). Comparison for PRs uses `numericResult`.
    public let result: String
    public let rxd: Bool               // as prescribed vs scaled
    public let note: String?

    public init(id: UUID = UUID(), date: String, name: String, scoring: WODScoring,
                result: String, rxd: Bool = false, note: String? = nil) {
        self.id = id
        self.date = date
        self.name = name
        self.scoring = scoring
        self.result = result
        self.rxd = rxd
        self.note = note
    }

    public var day: Date? { parseISODate(date) }

    /// Best-effort numeric extraction for PR comparison. Time "3:41" → 221
    /// (seconds); "225 lb" → 225; "12 rounds" → 12.
    public var numericResult: Double? {
        let t = result.trimmingCharacters(in: .whitespaces)
        if t.contains(":") {
            let parts = t.split(separator: ":").compactMap { Double($0) }
            if parts.count == 2 { return parts[0] * 60 + parts[1] }
        }
        let digits = t.filter { $0.isNumber || $0 == "." }
        return Double(digits)
    }
}

/// A named personal record — the best result for a movement, with when it was set.
public struct PersonalRecord: Identifiable {
    public var id: String { name }
    public let name: String
    public let best: String
    public let date: String
    public let scoring: WODScoring
}

public enum CrossFitStore {
    public static var fileURL: URL {
        Portfolio.dirURL.appendingPathComponent("crossfit.json")
    }

    public static func load(from url: URL = fileURL) -> [WOD] {
        guard let data = try? Data(contentsOf: url),
              let list = try? JSONDecoder().decode([WOD].self, from: data)
        else { return [] }
        return list.sorted { $0.date > $1.date }
    }

    public static func save(_ wods: [WOD], to url: URL = fileURL) {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let out = try? enc.encode(wods) { try? out.write(to: url, options: .atomic) }
    }

    public static func add(_ wod: WOD, to url: URL = fileURL) {
        var all = load(from: url)
        all.append(wod)
        save(all, to: url)
    }

    /// Personal records across all logged WODs — best result per movement name,
    /// respecting the scoring direction (for-time = lowest, others = highest).
    public static func personalRecords(from wods: [WOD]) -> [PersonalRecord] {
        let byName = Dictionary(grouping: wods) { $0.name }
        return byName.compactMap { name, list -> PersonalRecord? in
            let scored = list.filter { $0.numericResult != nil }
            guard let scoring = scored.first?.scoring else { return nil }
            let best: WOD?
            if scoring == .forTime {
                best = scored.min { ($0.numericResult ?? .infinity) < ($1.numericResult ?? .infinity) }
            } else {
                best = scored.max { ($0.numericResult ?? 0) < ($1.numericResult ?? 0) }
            }
            guard let b = best else { return nil }
            return PersonalRecord(name: name, best: b.result, date: b.date, scoring: scoring)
        }
        .sorted { $0.name < $1.name }
    }
}
