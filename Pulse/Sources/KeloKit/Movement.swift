import Foundation

// MARK: - Movement / activity
//
// The thing Ankur says the Watch doesn't do reliably: know whether you're
// sitting, standing, walking, or running right now, and how much you've moved.
// On iPhone this comes from Core Motion (`CMMotionActivityManager` for the live
// state, `CMPedometer` for steps/distance) — a different, richer source than a
// started HealthKit workout. Strictly opt-in (motion permission is the gate).
//
// Pure model here; the iOS layer supplies the Core Motion bridge. On macOS this
// is a stub so shared code compiles.

public enum ActivityState: String, Codable, CaseIterable {
    case stationary, walking, running, cycling, automotive, unknown

    public var label: String {
        switch self {
        case .stationary: return "Still"
        case .walking:    return "Walking"
        case .running:    return "Running"
        case .cycling:    return "Cycling"
        case .automotive: return "Driving"
        case .unknown:    return "—"
        }
    }
    public var icon: String {
        switch self {
        case .stationary: return "figure.stand"
        case .walking:    return "figure.walk"
        case .running:    return "figure.run"
        case .cycling:    return "figure.outdoor.cycle"
        case .automotive: return "car.fill"
        case .unknown:    return "questionmark"
        }
    }
}

/// A day's movement picture — accumulated from the live activity stream + the
/// pedometer. Hangs off the same date key as `HealthDay`.
public struct MovementDay: Codable, Identifiable, Equatable {
    public var id: String { date }
    public let date: String
    public var steps: Int
    public var distanceKm: Double
    /// Minutes spent standing/moving vs. sitting — the sit/stand balance.
    public var activeMinutes: Int
    public var sittingMinutes: Int

    public init(date: String, steps: Int = 0, distanceKm: Double = 0,
                activeMinutes: Int = 0, sittingMinutes: Int = 0) {
        self.date = date
        self.steps = steps
        self.distanceKm = distanceKm
        self.activeMinutes = activeMinutes
        self.sittingMinutes = sittingMinutes
    }

    /// Fraction of the tracked day spent sitting — the number to nudge on.
    public var sittingFraction: Double {
        let total = activeMinutes + sittingMinutes
        return total > 0 ? Double(sittingMinutes) / Double(total) : 0
    }
    /// A gentle flag: sitting most of a meaningful tracked stretch.
    public var tooSedentary: Bool {
        (activeMinutes + sittingMinutes) >= 120 && sittingFraction > 0.85
    }
}

public enum MovementStore {
    public static var fileURL: URL {
        Portfolio.dirURL.appendingPathComponent("movement.json")
    }

    public static func load(from url: URL = fileURL) -> [MovementDay] {
        guard let data = try? Data(contentsOf: url),
              let list = try? JSONDecoder().decode([MovementDay].self, from: data)
        else { return [] }
        return list
    }

    public static func save(_ days: [MovementDay], to url: URL = fileURL) {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let out = try? enc.encode(days) { try? out.write(to: url, options: .atomic) }
    }

    public static func upsert(_ day: MovementDay, to url: URL = fileURL) {
        var days = load(from: url).filter { $0.date != day.date }
        days.append(day)
        days.sort { $0.date < $1.date }
        save(days, to: url)
    }

    public static func today(_ url: URL = fileURL) -> MovementDay? {
        let t = isoDateString(Date())
        return load(from: url).first { $0.date == t }
    }
}
