import SwiftUI
import KeloKit

@main
struct KeloMacApp: App {
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
        .commands {
            // The user owns their data: full export and full wipe,
            // first-class (all files are plain JSON on this machine).
            CommandMenu("Data") {
                Button("Export All Data…") { DataManager.exportAll() }
                Divider()
                Button("Delete All Data…") { DataManager.wipeAll() }
            }
        }

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

enum DataManager {
    static var allFiles: [URL] {
        [Portfolio.fileURL, AppConfig.fileURL, SnapshotStore.fileURL,
         PaperLedger.fileURL, Watchlist.fileURL]
    }

    static func exportAll() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.message = "Choose a folder — Pulse copies its JSON data files there (they include your positions and keys; treat the copy with the same care)"
        guard panel.runModal() == .OK, let dir = panel.url else { return }
        let fm = FileManager.default
        for url in allFiles where fm.fileExists(atPath: url.path) {
            let dest = dir.appendingPathComponent("pulse-export-" + url.lastPathComponent)
            try? fm.removeItem(at: dest)
            try? fm.copyItem(at: url, to: dest)
        }
    }

    static func wipeAll() {
        let alert = NSAlert()
        alert.messageText = "Delete all \(KeloInfo.name) data?"
        alert.informativeText = "Removes portfolio, config (including API keys), snapshots, paper trades and watchlist from this machine. This cannot be undone."
        alert.alertStyle = .critical
        alert.addButton(withTitle: "Delete Everything")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        for url in allFiles {
            try? FileManager.default.removeItem(at: url)
        }
        NSApp.terminate(nil)
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
            Text("\(KeloInfo.name) is locked — unlock in the app window")
        }
        Button("Open \(KeloInfo.name)") {
            NSApp.activate(ignoringOtherApps: true)
            for w in NSApp.windows where w.canBecomeMain { w.makeKeyAndOrderFront(nil) }
        }
        Divider()
        Button("Quit \(KeloInfo.name)") { NSApp.terminate(nil) }
    }
}
