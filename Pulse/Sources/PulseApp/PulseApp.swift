import SwiftUI
import PulseKit

@main
struct PulseApp: App {
    // Owned here so the window and the menu bar share one live state.
    @StateObject private var model = AppModel()
    @StateObject private var lock = LockModel()

    var body: some Scene {
        WindowGroup {
            ContentView(model: model, lock: lock)
        }
        // Fixed default size — never let content width (e.g. a 60-position
        // legend) drive the window off the screen.
        .defaultSize(width: 1000, height: 940)

        // Glanceable pulse in the menu bar. Percentages only in the label;
        // dollar figures appear in the dropdown and only while unlocked.
        MenuBarExtra {
            MenuBarSummary(model: model, lock: lock)
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "waveform.path.ecg")
                if lock.unlocked, model.totalValue > 0 {
                    let holdingsValue = model.portfolio.holdings
                        .reduce(0.0) { $0 + model.holdingValue($1) }
                    if holdingsValue > 0 {
                        Text(String(format: "%+.1f%%", model.dayPL / holdingsValue * 100))
                            .font(.system(size: 11, design: .monospaced))
                    }
                }
            }
        }
    }
}

private struct MenuBarSummary: View {
    @ObservedObject var model: AppModel
    @ObservedObject var lock: LockModel

    var body: some View {
        if lock.unlocked {
            let allTime = model.totalValue - model.totalCost
            Text("Portfolio \(usd(model.totalValue))")
            Text("Today \(usd(model.dayPL)) (holdings) · All-time \(usd(allTime))")
            if let mover = model.portfolio.holdings
                .compactMap({ h in model.quotes[h.symbol].map { (h.symbol, $0.dayChangePct) } })
                .max(by: { abs($0.1) < abs($1.1) }) {
                Text("Mover: \(mover.0) \(String(format: "%+.2f%%", mover.1))")
            }
            Divider()
            Button("Refresh") { model.refresh() }
        } else {
            Text("Pulse is locked — unlock in the app window")
        }
        Button("Open Pulse") {
            NSApp.activate(ignoringOtherApps: true)
            for w in NSApp.windows where w.canBecomeMain { w.makeKeyAndOrderFront(nil) }
        }
        Divider()
        Button("Quit Pulse") { NSApp.terminate(nil) }
    }
}
