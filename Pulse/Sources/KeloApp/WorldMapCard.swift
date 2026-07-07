import SwiftUI
import KeloKit

/// The world view — just the map. Every exchange is a glowing pin at its real
/// location; hover a pin to see that market's name and move. Commodities and
/// crypto (no geographic home) sit in a slim strip beneath, also hover-first.
struct WorldMapCard: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Card(title: "WORLD VIEW", trailing: "hover any market for detail") {
            if let w = model.worldMarkets, !w.tickers.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text(w.breadthSummary)
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                    WorldMapView(tickers: w.tickers)
                        .frame(height: 260)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    // Non-geographic markets (gold, oil, crypto) as small dots.
                    let extras = w.tickers.filter { $0.kind == .commodity || $0.kind == .crypto }
                    if !extras.isEmpty {
                        HStack(spacing: 14) {
                            ForEach(extras, id: \.symbol) { t in
                                HStack(spacing: 5) {
                                    Circle().fill(t.dayPct >= 0 ? Color.green : Color.red)
                                        .frame(width: 6, height: 6)
                                    Text(t.name).font(.system(size: 10.5)).foregroundStyle(.secondary)
                                    Text(String(format: "%+.1f%%", t.dayPct))
                                        .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                                        .foregroundStyle(t.dayPct >= 0 ? .green : .red)
                                }
                                .help("\(t.name): \(String(format: "%+.2f%%", t.dayPct)) today")
                            }
                            Spacer()
                        }
                    }
                }
            } else {
                Text("loading the world…")
                    .font(.system(size: 11, design: .monospaced)).foregroundStyle(.tertiary)
            }
        }
    }
}
