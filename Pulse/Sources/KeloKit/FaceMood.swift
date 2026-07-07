import Foundation

// MARK: - Facial mood (on-device, honest)
//
// Reads facial EXPRESSION (via ARKit blendshapes on iOS) and maps it to a
// suggested mood. Built per Ankur's call to auto-read — but with one line Kelo
// will not cross: the resulting MoodEntry is LABELLED "from facial expression",
// never silently indistinguishable from a felt rating. Expression ≠ emotion
// (the science is clear a face doesn't reveal an inner state), so Kelo records
// what it actually measured — an expression — not a claim about how you feel.
//
// Pure valence math here (testable); the ARKit capture lives in the iOS layer.

public enum FaceMood {

    /// The blendshape signals we use, as 0…1 activations (ARKit names). Only a
    /// handful — the ones with the clearest valence.
    public struct Blendshapes {
        public var mouthSmileLeft: Double
        public var mouthSmileRight: Double
        public var mouthFrownLeft: Double
        public var mouthFrownRight: Double
        public var browDownLeft: Double
        public var browDownRight: Double
        public var browInnerUp: Double
        public var cheekSquintLeft: Double
        public var cheekSquintRight: Double

        public init(mouthSmileLeft: Double = 0, mouthSmileRight: Double = 0,
                    mouthFrownLeft: Double = 0, mouthFrownRight: Double = 0,
                    browDownLeft: Double = 0, browDownRight: Double = 0,
                    browInnerUp: Double = 0, cheekSquintLeft: Double = 0,
                    cheekSquintRight: Double = 0) {
            self.mouthSmileLeft = mouthSmileLeft; self.mouthSmileRight = mouthSmileRight
            self.mouthFrownLeft = mouthFrownLeft; self.mouthFrownRight = mouthFrownRight
            self.browDownLeft = browDownLeft; self.browDownRight = browDownRight
            self.browInnerUp = browInnerUp
            self.cheekSquintLeft = cheekSquintLeft; self.cheekSquintRight = cheekSquintRight
        }
    }

    /// Valence in −1 (clearly negative expression) … +1 (clearly positive).
    /// A genuine (Duchenne) smile pairs mouth-smile with cheek-squint; frowns
    /// and brow-lowering read negative; inner-brow-up reads worried/sad.
    public static func valence(_ b: Blendshapes) -> Double {
        let smile = (b.mouthSmileLeft + b.mouthSmileRight) / 2
        let cheek = (b.cheekSquintLeft + b.cheekSquintRight) / 2
        let frown = (b.mouthFrownLeft + b.mouthFrownRight) / 2
        let browDown = (b.browDownLeft + b.browDownRight) / 2

        let positive = smile * 0.8 + cheek * 0.2                 // Duchenne weighting
        let negative = frown * 0.6 + browDown * 0.3 + b.browInnerUp * 0.3
        return max(-1, min(1, positive - negative))
    }

    /// Map valence to Kelo's 1…5 mood scale.
    public static func mood(from valence: Double) -> Int {
        switch valence {
        case ..<(-0.5): return 1
        case ..<(-0.15): return 2
        case ..<0.15: return 3
        case ..<0.5: return 4
        default: return 5
        }
    }

    /// Build the MoodEntry from an expression reading — ALWAYS labelled so it's
    /// never mistaken for a felt self-rating.
    public static func entry(from b: Blendshapes, date: Date = Date()) -> MoodEntry {
        let m = mood(from: valence(b))
        return MoodEntry(date: isoDateString(date), mood: m, note: "from facial expression")
    }
}
