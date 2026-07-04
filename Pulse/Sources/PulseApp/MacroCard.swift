import SwiftUI
import PulseKit

/// The live macro backdrop — inflation, the cost of money, how much money
/// exists, the dollar, the 10-year — from the St. Louis Fed (FRED), keyless.
/// These are the forces the per-stock Macro Lens explains; here they're the
/// actual current readings, so "why and how" is grounded in today's numbers.
struct MacroCard: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Card(title: "MACRO BACKDROP", trailing: "live from FRED (US Federal Reserve data) · keyless") {
            if let m = model.macroData, !m.readings.isEmpty {
                VStack(alignment: .leading, spacing: 9) {
                    ForEach(m.readings.indices, id: \.self) { i in
                        let r = m.readings[i]
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(r.label)
                                .font(.system(size: 12, weight: .medium))
                                .frame(width: 130, alignment: .leading)
                            Text(valueLabel(r))
                                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                .foregroundStyle(.primary)
                                .frame(width: 90, alignment: .leading)
                            Text(r.note)
                                .font(.system(size: 10.5)).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer()
                        }
                    }
                    Text("open any stock's Outlook to see how these forces reach that specific company (its sector + country).")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.tertiary).padding(.top, 2)
                }
            } else {
                Text("fetching macro data…")
                    .font(.system(size: 11, design: .monospaced)).foregroundStyle(.tertiary)
            }
        }
    }

    private func valueLabel(_ r: MacroData.Reading) -> String {
        if let yoy = r.yoyPct {
            return String(format: "%+.1f%% YoY", yoy)
        }
        return r.unit == "%" ? String(format: "%.2f%%", r.value)
             : r.unit == "$B" ? String(format: "$%.0fB", r.value)
             : String(format: "%.1f", r.value)
    }
}

/// World Monitor — a companion global-intelligence dashboard (open-source,
/// AGPL). Pulse links to it rather than embedding it, to keep the licenses
/// clean; credited to its author.
struct WorldMonitorLink: View {
    var body: some View {
        Card(title: "GEOPOLITICAL DASHBOARD", trailing: "companion tool · opens in browser") {
            HStack(spacing: 10) {
                Image(systemName: "globe.americas.fill")
                    .font(.system(size: 20)).foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text("World Monitor")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Real-time global intelligence — 500+ feeds, conflict tracking, a country-instability index. Open it alongside Pulse for the geopolitical picture behind the macro numbers.")
                        .font(.system(size: 10.5)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("open-source (AGPL) by koala73 — a separate project, linked not embedded")
                        .font(.system(size: 9, design: .monospaced)).foregroundStyle(.tertiary)
                }
                Spacer()
                Button("Open") {
                    if let url = URL(string: "https://github.com/koala73/worldmonitor") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        }
    }
}
