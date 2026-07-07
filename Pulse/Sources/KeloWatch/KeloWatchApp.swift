import SwiftUI
import KeloKit

// Kelo on the wrist — a glance, nothing more. The Watch is a sensor + a quick
// read ([[project_life_app_ai]]): today's state as a ring, the one line that
// matters, and a single tap to check in. Full logging lives on the phone.

@main
struct KeloWatchApp: App {
    var body: some Scene {
        WindowGroup { WatchTodayView() }
    }
}

struct WatchTodayView: View {
    @State private var state = Self.currentState()
    private let rings = Self.currentRings()

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                // Three rings — Body · Money · Discipline — the same glance as
                // the phone, wrist-sized.
                ZStack {
                    ForEach(Array(rings.enumerated()), id: \.element.id) { i, ring in
                        let inset = CGFloat(i) * 16
                        ZStack {
                            Circle().stroke(ringColor(ring.kind).opacity(0.2), lineWidth: 9)
                            Circle()
                                .trim(from: 0, to: max(0.001, ring.fraction))
                                .stroke(ringColor(ring.kind), style: StrokeStyle(lineWidth: 9, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                        }
                        .padding(inset)
                    }
                }
                .frame(width: 104, height: 104)
                .padding(.top, 4)

                Text(state.headline)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(ringColor)
                    .multilineTextAlignment(.center)

                if let first = state.reasons.first {
                    Text(first.text)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 8)
        }
    }

    private var ringColor: Color {
        switch state.standing {
        case .strong: return .green
        case .steady:
            let a = KeloBrand.accent
            return Color(.sRGB, red: a.r, green: a.g, blue: a.b, opacity: 1)
        case .strained: return .orange
        }
    }

    private func ringColor(_ kind: Ring.Kind) -> Color {
        switch kind {
        case .body:       return Color(.sRGB, red: 0.90, green: 0.30, blue: 0.35, opacity: 1)
        case .money:      let a = KeloBrand.accent
                          return Color(.sRGB, red: a.r, green: a.g, blue: a.b, opacity: 1)
        case .discipline: return Color(.sRGB, red: 0.36, green: 0.66, blue: 0.52, opacity: 1)
        }
    }

    // Build the same DayState + rings the phone/desktop show, from on-device
    // data the Watch shares via KeloKit.
    private static func currentState() -> DayState {
        let health = HealthStore.load()
        let today = health.days.first { $0.date == isoDateString(Date()) }
        return DayState(.init(
            today: today,
            restingHRBaseline: health.restingHRBaseline(),
            recentLoad: health.recentLoad(),
            mood: MoodStore.today()?.mood))
    }

    private static func currentRings() -> [Ring] {
        let health = HealthStore.load()
        let today = health.days.first { $0.date == isoDateString(Date()) }
        let totals = SpendService.monthTotals(SpendStore.load())
        let streaks = Discipline.streaks(health: health, mood: MoodStore.load())
        return Rings.all(movement: MovementStore.today(),
                         trainedToday: today?.didTrain ?? false,
                         spentThisMonth: totals.spent, budgeted: totals.budgeted,
                         streaks: streaks)
    }
}
