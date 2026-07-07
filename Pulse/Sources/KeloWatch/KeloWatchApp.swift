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

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                // The day as a ring, Apple-Fitness style — one glanceable arc.
                ZStack {
                    Circle().stroke(Color.white.opacity(0.15), lineWidth: 10)
                    Circle()
                        .trim(from: 0, to: ringFill)
                        .stroke(ringColor, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Image(systemName: ringIcon)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(ringColor)
                }
                .frame(width: 96, height: 96)
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

    // A rough "how full is the day" arc from the composite standing.
    private var ringFill: CGFloat {
        switch state.standing {
        case .strong: return 1.0
        case .steady: return 0.6
        case .strained: return 0.3
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
    private var ringIcon: String {
        switch state.standing {
        case .strong: return "checkmark"
        case .steady: return "circle.dashed"
        case .strained: return "exclamationmark"
        }
    }

    // Build the same DayState the phone/desktop show, from on-device data the
    // Watch shares via KeloKit.
    private static func currentState() -> DayState {
        let health = HealthStore.load()
        let today = health.days.first { $0.date == isoDateString(Date()) }
        return DayState(.init(
            today: today,
            restingHRBaseline: health.restingHRBaseline(),
            recentLoad: health.recentLoad(),
            mood: MoodStore.today()?.mood))
    }
}
