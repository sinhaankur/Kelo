import Foundation

// MARK: - Body composition
//
// Weight, BMI, body-fat, lean mass — from a smart scale (via HealthKit, which
// most scales already write to) or an uploaded clinical report (GE/DEXA/InBody
// don't do consumer Bluetooth, so those come in as an OCR'd report, not a live
// connection).
//
// Honest by design: BMI is a blunt instrument — it can't tell muscle from fat —
// so Kelo COMPUTES it from weight + height (never depends on the scale to
// report it) and labels it as crude, preferring body-fat % / lean mass when a
// scale actually measures them. On-device, gitignored, same Store pattern.

public struct BodyMeasurement: Codable, Identifiable, Equatable {
    public var id: String { date }
    public let date: String            // "YYYY-MM-DD"
    public var weightKg: Double?
    public var bodyFatPercent: Double? // 0…100
    public var leanMassKg: Double?
    /// Where it came from — "scale" (HealthKit), "report" (OCR), "manual".
    public var source: String

    public init(date: String, weightKg: Double? = nil, bodyFatPercent: Double? = nil,
                leanMassKg: Double? = nil, source: String = "manual") {
        self.date = date
        self.weightKg = weightKg
        self.bodyFatPercent = bodyFatPercent
        self.leanMassKg = leanMassKg
        self.source = source
    }

    public var day: Date? { parseISODate(date) }

    /// BMI from weight + a height (cm). Computed here so Kelo never relies on the
    /// machine reporting BMI. nil when either input is missing.
    public func bmi(heightCm: Double?) -> Double? {
        guard let w = weightKg, let h = heightCm, h > 0 else { return nil }
        let m = h / 100
        return w / (m * m)
    }
}

/// The standard WHO BMI bands — labelled, and always paired with the caveat
/// that BMI is crude (a muscular person reads "overweight" wrongly).
public enum BMIBand: String {
    case underweight, healthy, overweight, obese

    public static func of(_ bmi: Double) -> BMIBand {
        switch bmi {
        case ..<18.5: return .underweight
        case ..<25:   return .healthy
        case ..<30:   return .overweight
        default:      return .obese
        }
    }
    public var label: String {
        switch self {
        case .underweight: return "Underweight"
        case .healthy:     return "Healthy range"
        case .overweight:  return "Overweight (BMI is crude — check body-fat)"
        case .obese:       return "Obese (BMI is crude — check body-fat)"
        }
    }
}

public struct BodyCompositionData: Codable {
    public var measurements: [BodyMeasurement]
    public init(measurements: [BodyMeasurement] = []) { self.measurements = measurements }

    public var latest: BodyMeasurement? { measurements.max { $0.date < $1.date } }

    /// Weight change over the trailing `days`, if there are two points to compare.
    public func weightTrendKg(days: Int = 30, asOf date: Date = Date()) -> Double? {
        let sorted = measurements.compactMap { m -> (Date, Double)? in
            guard let d = m.day, let w = m.weightKg else { return nil }
            return (d, w)
        }.sorted { $0.0 < $1.0 }
        guard let last = sorted.last else { return nil }
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: date) else { return nil }
        let baseline = sorted.first { $0.0 >= cutoff } ?? sorted.first
        guard let base = baseline, base.0 < last.0 else { return nil }
        return last.1 - base.1
    }
}

public enum BodyCompositionStore {
    public static var fileURL: URL {
        Portfolio.dirURL.appendingPathComponent("body-composition.json")
    }

    public static func load(from url: URL = fileURL) -> BodyCompositionData {
        guard let data = try? Data(contentsOf: url),
              let d = try? JSONDecoder().decode(BodyCompositionData.self, from: data)
        else { return BodyCompositionData() }
        return d
    }

    public static func save(_ data: BodyCompositionData, to url: URL = fileURL) {
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let out = try? enc.encode(data) { try? out.write(to: url, options: .atomic) }
    }

    public static func upsert(_ m: BodyMeasurement, to url: URL = fileURL) {
        var d = load(from: url)
        d.measurements.removeAll { $0.date == m.date }
        d.measurements.append(m)
        d.measurements.sort { $0.date < $1.date }
        save(d, to: url)
    }
}
