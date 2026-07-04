import SwiftUI
import PulseKit

/// A visual world view — regions of the globe laid out as glowing tiles that
/// turn green or red with their market's session, so you SEE the state of the
/// world at a glance before you read a single number. Stock-focused: the
/// tiles are the major exchanges, plus commodities and crypto.
struct WorldMapCard: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Card(title: "WORLD VIEW", trailing: "the planet's session, at a glance") {
            if let w = model.worldMarkets, !w.tickers.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text(w.breadthSummary)
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                    // The actual map — continents with market pins glowing
                    // green/red at their real geographic positions.
                    WorldMapView(tickers: w.tickers)
                        .frame(height: 200)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    // Region rows of glowing tiles (west → east) below the map,
                    // so commodities/crypto (no map pin) are covered too.
                    ForEach(w.byRegion(), id: \.region) { group in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(group.region.uppercased())
                                .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                                .tracking(1.5).foregroundStyle(.tertiary)
                            HStack(spacing: 8) {
                                ForEach(group.items, id: \.symbol) { t in
                                    MarketTile(ticker: t)
                                }
                                Spacer(minLength: 0)
                            }
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

/// A single glowing market tile — color and glow scale with the day's move.
private struct MarketTile: View {
    let ticker: WorldMarkets.Ticker

    var body: some View {
        let up = ticker.dayPct >= 0
        let color: Color = up ? .green : .red
        let intensity = min(1.0, abs(ticker.dayPct) / 4.0) // 4%+ = full glow
        VStack(spacing: 3) {
            Text(shortName)
                .font(.system(size: 10, weight: .semibold))
                .lineLimit(1).minimumScaleFactor(0.7)
            Text(String(format: "%+.1f%%", ticker.dayPct))
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
        }
        .frame(width: 92, height: 46)
        .background(
            RoundedRectangle(cornerRadius: 9)
                .fill(color.opacity(0.10 + intensity * 0.22))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .strokeBorder(color.opacity(0.3 + intensity * 0.5), lineWidth: 1)
        )
        .shadow(color: color.opacity(intensity * 0.5), radius: intensity * 8)
        .help("\(ticker.name): \(String(format: "%+.2f%%", ticker.dayPct)) today")
    }

    // Compact label for the tile.
    private var shortName: String {
        ticker.name
            .replacingOccurrences(of: " (Canada)", with: "")
            .replacingOccurrences(of: " (UK)", with: "")
            .replacingOccurrences(of: " (Germany)", with: "")
            .replacingOccurrences(of: " (France)", with: "")
            .replacingOccurrences(of: " (Japan)", with: "")
            .replacingOccurrences(of: " (HK)", with: "")
            .replacingOccurrences(of: " (Australia)", with: "")
            .replacingOccurrences(of: " (WTI)", with: "")
    }
}
