import XCTest
@testable import KeloKit

final class FaceMoodTests: XCTestCase {

    func testBigSmileReadsPositive() {
        let smile = FaceMood.Blendshapes(mouthSmileLeft: 0.9, mouthSmileRight: 0.9,
                                         cheekSquintLeft: 0.7, cheekSquintRight: 0.7)
        let v = FaceMood.valence(smile)
        XCTAssertGreaterThan(v, 0.5)
        XCTAssertEqual(FaceMood.mood(from: v), 5)
    }

    func testFrownAndBrowDownReadNegative() {
        let sad = FaceMood.Blendshapes(mouthFrownLeft: 0.8, mouthFrownRight: 0.8,
                                       browDownLeft: 0.6, browDownRight: 0.6)
        let v = FaceMood.valence(sad)
        XCTAssertLessThan(v, -0.15)
        XCTAssertLessThanOrEqual(FaceMood.mood(from: v), 2)
    }

    func testNeutralReadsMiddle() {
        let v = FaceMood.valence(FaceMood.Blendshapes())
        XCTAssertEqual(FaceMood.mood(from: v), 3)
    }

    // The honest label is non-negotiable: a face-derived entry must say so.
    func testEntryIsLabelledAsExpression() {
        let e = FaceMood.entry(from: FaceMood.Blendshapes(mouthSmileLeft: 0.9, mouthSmileRight: 0.9))
        XCTAssertEqual(e.note, "from facial expression")
        XCTAssertGreaterThanOrEqual(e.mood, 4)
    }

    // Valence stays clamped even with saturated inputs.
    func testValenceClamped() {
        let ecstatic = FaceMood.Blendshapes(mouthSmileLeft: 1, mouthSmileRight: 1,
                                            cheekSquintLeft: 1, cheekSquintRight: 1)
        XCTAssertLessThanOrEqual(FaceMood.valence(ecstatic), 1.0)
    }
}
