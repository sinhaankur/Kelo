import XCTest
@testable import KeloKit

final class BodyCompositionTests: XCTestCase {

    // BMI is computed from weight + height — never taken from the scale.
    func testBMIComputedFromWeightAndHeight() {
        let m = BodyMeasurement(date: "2026-07-07", weightKg: 80)
        // 80 kg at 180 cm → 24.69
        XCTAssertEqual(m.bmi(heightCm: 180)!, 24.69, accuracy: 0.05)
        // No height → no BMI, rather than a guess.
        XCTAssertNil(m.bmi(heightCm: nil))
    }

    func testBMIBands() {
        XCTAssertEqual(BMIBand.of(17), .underweight)
        XCTAssertEqual(BMIBand.of(22), .healthy)
        XCTAssertEqual(BMIBand.of(27), .overweight)
        XCTAssertEqual(BMIBand.of(32), .obese)
        // The overweight/obese labels carry the honest caveat.
        XCTAssertTrue(BMIBand.overweight.label.lowercased().contains("crude"))
    }

    func testWeightTrend() {
        let cal = Calendar.current
        func d(_ off: Int) -> String { isoDateString(cal.date(byAdding: .day, value: off, to: Date())!) }
        let data = BodyCompositionData(measurements: [
            BodyMeasurement(date: d(-28), weightKg: 82),
            BodyMeasurement(date: d(0), weightKg: 80),
        ])
        XCTAssertEqual(data.weightTrendKg(days: 30)!, -2, accuracy: 0.01)  // down 2 kg
    }

    func testLatestPicksMostRecent() {
        let data = BodyCompositionData(measurements: [
            BodyMeasurement(date: "2026-07-01", weightKg: 81),
            BodyMeasurement(date: "2026-07-07", weightKg: 80),
        ])
        XCTAssertEqual(data.latest?.weightKg, 80)
    }
}
