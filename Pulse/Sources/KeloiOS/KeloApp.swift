import SwiftUI
import KeloKit

// Kelo for iPhone + iPad. Shares the exact KeloKit core with the Mac app;
// its reason to exist is the phone's access to Apple Health, which the Mac
// can't read. This first cut is the unified hero — today's Day State fed by
// HealthKit — plus honest, user-driven sync. Everything stays on-device and
// opt-in ([[feedback_user_action_only]]).

@main
struct KeloApp: App {
    @StateObject private var model = KeloModel()
    var body: some Scene {
        WindowGroup {
            RootView(model: model)
                .onAppear { model.startMovement() }
        }
    }
}

/// The iOS view-model. Deliberately thin — it reuses KeloKit's stores and the
/// pure `DayState` engine, adding only the HealthKit bridge that's unique to
/// this platform.
@MainActor
final class KeloModel: ObservableObject {
    @Published var health = HealthStore.load()
    @Published var portfolio = Portfolio.load()
    @Published var movement = MovementStore.today()
    @Published var liveActivity: ActivityState = .unknown
    @Published var lastSync: Date?
    @Published var syncing = false
    @Published var healthAuthorized = false
    @Published var statusLine: String?

    private let reader = HealthKitReader()
    private let motion = MovementService()

    var healthKitAvailable: Bool { HealthKitReader.isAvailable }
    var movementAvailable: Bool { MovementService.isAvailable }

    /// Begin the live walk/run/still stream — the signal the Watch doesn't
    /// auto-classify. Opt-in; the OS prompts for motion access on first call.
    func startMovement() {
        motion.startLiveUpdates { [weak self] state in
            Task { @MainActor in self?.liveActivity = state }
        }
    }

    /// Today's Day State. On iOS the money side is read from the synced JSON
    /// (portfolio/spending) if present; the body side is HealthKit-fed. Unknown
    /// signals are omitted, never guessed — same honesty rule as the Mac.
    var dayState: DayState {
        let card = SpendService.scorecard(SpendStore.load())
        let spendFraction = card.budgeted > 0 ? card.spent / card.budgeted : nil
        let today = isoDateString(Date())
        let todayHealth = health.days.first { $0.date == today }
        return DayState(.init(
            today: todayHealth,
            restingHRBaseline: health.restingHRBaseline(),
            recentLoad: health.recentLoad(),
            portfolioDayFraction: nil,      // wired once quote sync lands
            spendVsBudget: spendFraction))
    }

    var todayHealth: HealthDay? {
        let today = isoDateString(Date())
        return health.days.first { $0.date == today }
    }

    /// Ask for Health access, then pull today's real signals in — only ever
    /// from an explicit user tap. Kelo reads Health; it never writes it.
    func syncFromHealth() async {
        guard healthKitAvailable else {
            statusLine = "Apple Health isn't available on this device."
            return
        }
        syncing = true
        defer { syncing = false }
        do {
            try await reader.requestAuthorization()
            healthAuthorized = true
            let reading = try await reader.read()
            let today = isoDateString(Date())
            let merged = reading.merged(into: todayHealth, date: today)
            HealthStore.upsert(merged)
            health = HealthStore.load()
            // Movement is part of the same body picture — pull it in the same tap.
            if movementAvailable {
                movement = try? await motion.syncToday()
            }
            lastSync = Date()
            statusLine = "Synced today from Apple Health."
        } catch HealthKitError.notAuthorized {
            statusLine = "Health access not granted — enable it in Settings › Health › Kelo."
        } catch {
            statusLine = "Couldn't read Health right now."
        }
    }
}
