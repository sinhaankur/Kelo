import SwiftUI
import LocalAuthentication

/// Privacy lock — this window shows real money, so it opens locked and
/// unlocks with Touch ID (or the account password as fallback). Re-lock any
/// time from the header. Toggleable via the "Require unlock" setting.
@MainActor
final class LockModel: ObservableObject {
    @AppStorage("lockEnabled") var lockEnabled = true
    @Published var unlocked = false
    @Published var failed = false

    func unlockIfNeeded() {
        guard lockEnabled, !unlocked else { unlocked = true; return }
        let ctx = LAContext()
        ctx.localizedReason = "unlock your portfolio"
        var err: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err) else {
            // No auth available on this Mac — fail open rather than lock the
            // user out of their own data.
            unlocked = true
            return
        }
        Task {
            do {
                let ok = try await ctx.evaluatePolicy(.deviceOwnerAuthentication,
                                                      localizedReason: "unlock your portfolio")
                await MainActor.run { self.unlocked = ok; self.failed = !ok }
            } catch {
                await MainActor.run { self.failed = true }
            }
        }
    }

    func lock() { unlocked = false; failed = false }
}

struct LockGate<Content: View>: View {
    // Injected — the app owns the model so the menu bar sees the same state.
    @ObservedObject var lock: LockModel
    @ViewBuilder var content: (LockModel) -> Content

    var body: some View {
        ZStack {
            content(lock)
                .blur(radius: lock.unlocked ? 0 : 22)
                .allowsHitTesting(lock.unlocked)
            if !lock.unlocked {
                VStack(spacing: 12) {
                    Image(systemName: "lock.fill").font(.system(size: 28)).foregroundStyle(.secondary)
                    Text("Pulse is locked").font(.system(size: 14, weight: .semibold))
                    Text("your positions stay private").font(.system(size: 11)).foregroundStyle(.secondary)
                    Button(lock.failed ? "Try again" : "Unlock") { lock.unlockIfNeeded() }
                        .keyboardShortcut(.return)
                }
                .padding(28)
                .background(RoundedRectangle(cornerRadius: 14).fill(.ultraThinMaterial))
            }
        }
        .onAppear { lock.unlockIfNeeded() }
    }
}
