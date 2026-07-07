import SwiftUI
import KeloKit

/// Kelo's day as three concentric rings — Apple-Fitness language applied to a
/// whole life: BODY (outer), MONEY (middle), DISCIPLINE (inner). One image,
/// three things to close. "Everything is related" made literal.
struct RingsView: View {
    let rings: [Ring]

    // Ring colours in the brand family — each distinct but coherent.
    private func color(_ kind: Ring.Kind) -> Color {
        switch kind {
        case .body:       return Color(.sRGB, red: 0.90, green: 0.30, blue: 0.35, opacity: 1) // vital red
        case .money:      return Color(KeloBrand.accent)                                        // amber-gold
        case .discipline: return Color(.sRGB, red: 0.36, green: 0.66, blue: 0.52, opacity: 1)  // steady green
        }
    }

    var body: some View {
        ZStack {
            ForEach(Array(rings.enumerated()), id: \.element.id) { i, ring in
                let inset = CGFloat(i) * 30
                RingArc(fraction: ring.fraction, color: color(ring.kind))
                    .padding(inset)
            }
        }
        .frame(width: 190, height: 190)
        .animation(.easeOut(duration: 0.6), value: rings.map(\.fraction))
    }
}

private struct RingArc: View {
    let fraction: Double
    let color: Color

    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.18), lineWidth: 18)
            Circle()
                .trim(from: 0, to: max(0.001, fraction))
                .stroke(color, style: StrokeStyle(lineWidth: 18, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

/// The rings plus their legend — a self-contained "today at a glance" block.
struct RingsSummary: View {
    let rings: [Ring]

    private func color(_ kind: Ring.Kind) -> Color {
        switch kind {
        case .body:       return Color(.sRGB, red: 0.90, green: 0.30, blue: 0.35, opacity: 1)
        case .money:      return Color(KeloBrand.accent)
        case .discipline: return Color(.sRGB, red: 0.36, green: 0.66, blue: 0.52, opacity: 1)
        }
    }
    private func title(_ kind: Ring.Kind) -> String {
        switch kind {
        case .body: return "Body"; case .money: return "Money"; case .discipline: return "Discipline"
        }
    }

    var body: some View {
        HStack(spacing: 18) {
            RingsView(rings: rings)
            VStack(alignment: .leading, spacing: 12) {
                ForEach(rings) { ring in
                    HStack(spacing: 8) {
                        Circle().fill(color(ring.kind)).frame(width: 9, height: 9)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(title(ring.kind))
                                .font(KeloFont.mono(10, .semibold))
                                .foregroundStyle(Color.keloMuted)
                            Text(ring.hasData ? ring.label : ring.label)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(ring.hasData ? Color.keloInk : Color.keloMuted)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }
}
