import SwiftUI
import KeloKit
#if canImport(ARKit)
import ARKit
#endif

/// "Check in with your face" — reads your expression on-device (ARKit
/// blendshapes) and sets today's mood. Everything stays on the phone; the
/// camera feed is never recorded or sent anywhere. The saved entry is labelled
/// "from facial expression" (honest: expression isn't the same as how you feel).
struct FaceCheckInView: View {
    @ObservedObject var model: KeloModel
    @Environment(\.dismiss) private var dismiss
    @State private var detected: Int?
    @State private var status = "Look at the camera…"

    var body: some View {
        VStack(spacing: 16) {
            Text("Face check-in")
                .font(KeloFont.display(20, .semibold)).foregroundStyle(Color.keloInk)

            #if canImport(ARKit)
            if ARFaceTrackingConfiguration.isSupported {
                FaceScanner { blendshapes in
                    let v = FaceMood.valence(blendshapes)
                    detected = FaceMood.mood(from: v)
                    status = "Reading your expression…"
                }
                .frame(height: 320)
                .clipShape(RoundedRectangle(cornerRadius: 20))
            } else {
                unsupported
            }
            #else
            unsupported
            #endif

            if let d = detected {
                Text("\(MoodEntry(date: "d", mood: d).emoji)  \(MoodEntry(date: "d", mood: d).label)")
                    .font(KeloFont.display(22, .semibold)).foregroundStyle(Color.keloAccent)
            } else {
                Text(status).font(.callout).foregroundStyle(.secondary)
            }

            Text("Kelo reads your expression on-device. Expression isn't the same as how you feel — this is saved as a facial reading, and you can always log your real mood by hand.")
                .font(.caption).foregroundStyle(.tertiary)
                .multilineTextAlignment(.center).padding(.horizontal)

            Button {
                if let d = detected {
                    model.logFacialMood(d)
                    dismiss()
                }
            } label: {
                Text("Save this reading").fontWeight(.semibold).frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).tint(.keloAccent)
            .disabled(detected == nil)

            Button("Cancel") { dismiss() }.font(.footnote)
        }
        .padding()
        .background(Color.keloPaper.ignoresSafeArea())
    }

    private var unsupported: some View {
        VStack(spacing: 8) {
            Image(systemName: "faceid").font(.system(size: 40)).foregroundStyle(.secondary)
            Text("Face reading needs a Face ID camera. Log your mood by hand instead.")
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(height: 320)
    }
}

#if canImport(ARKit)
/// Minimal ARKit face-tracking view that streams blendshape readings up. No
/// frames are stored; only the numeric coefficients are read, on-device.
private struct FaceScanner: UIViewRepresentable {
    let onRead: (FaceMood.Blendshapes) -> Void

    func makeUIView(context: Context) -> ARSCNView {
        let view = ARSCNView()
        view.session.delegate = context.coordinator
        let config = ARFaceTrackingConfiguration()
        view.session.run(config)
        return view
    }
    func updateUIView(_ uiView: ARSCNView, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(onRead) }
    static func dismantleUIView(_ uiView: ARSCNView, coordinator: Coordinator) {
        uiView.session.pause()
    }

    final class Coordinator: NSObject, ARSessionDelegate {
        let onRead: (FaceMood.Blendshapes) -> Void
        private var last = Date.distantPast
        init(_ onRead: @escaping (FaceMood.Blendshapes) -> Void) { self.onRead = onRead }

        func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
            guard let face = anchors.compactMap({ $0 as? ARFaceAnchor }).first else { return }
            // Throttle to ~3/s — enough to feel live, cheap on battery.
            guard Date().timeIntervalSince(last) > 0.33 else { return }
            last = Date()
            let s = face.blendShapes
            func v(_ k: ARFaceAnchor.BlendShapeLocation) -> Double { (s[k]?.doubleValue) ?? 0 }
            let b = FaceMood.Blendshapes(
                mouthSmileLeft: v(.mouthSmileLeft), mouthSmileRight: v(.mouthSmileRight),
                mouthFrownLeft: v(.mouthFrownLeft), mouthFrownRight: v(.mouthFrownRight),
                browDownLeft: v(.browDownLeft), browDownRight: v(.browDownRight),
                browInnerUp: v(.browInnerUp),
                cheekSquintLeft: v(.cheekSquintLeft), cheekSquintRight: v(.cheekSquintRight))
            DispatchQueue.main.async { self.onRead(b) }
        }
    }
}
#endif
