import SwiftUI
import PulseKit

/// An actual world map — continents drawn as vector shapes on an equirectangular
/// projection, with each market plotted at its real lat/long as a glowing dot
/// that turns green or red with its session. Drawn entirely in Canvas, no image
/// assets, so it scales crisply and ships in the binary.
struct WorldMapView: View {
    let tickers: [WorldMarkets.Ticker]

    // Market → (latitude, longitude) of its exchange city.
    private static let coords: [String: (lat: Double, lon: Double)] = [
        "^GSPC": (40.7, -74.0),   // New York
        "^IXIC": (40.7, -74.0),
        "^DJI":  (40.7, -74.0),
        "^GSPTSE": (43.7, -79.4), // Toronto
        "^FTSE": (51.5, -0.1),    // London
        "^GDAXI": (50.1, 8.7),    // Frankfurt
        "^FCHI": (48.9, 2.3),     // Paris
        "^N225": (35.7, 139.7),   // Tokyo
        "^HSI": (22.3, 114.2),    // Hong Kong
        "^AXJO": (-33.9, 151.2),  // Sydney
    ]

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                // Ocean backdrop.
                RoundedRectangle(cornerRadius: 10)
                    .fill(LinearGradient(colors: [Color(red: 0.05, green: 0.09, blue: 0.16),
                                                  Color(red: 0.03, green: 0.05, blue: 0.10)],
                                         startPoint: .top, endPoint: .bottom))
                // Continents — real coastlines (Natural Earth, bundled).
                Canvas { ctx, size in
                    for poly in WorldGeo.polygons {
                        var p = Path()
                        var i = 0
                        while i + 1 < poly.count {
                            let cg = project(Double(poly[i + 1]), Double(poly[i]), size)
                            if i == 0 { p.move(to: cg) } else { p.addLine(to: cg) }
                            i += 2
                        }
                        p.closeSubpath()
                        ctx.fill(p, with: .color(Color(red: 0.16, green: 0.22, blue: 0.31)))
                        ctx.stroke(p, with: .color(Color.white.opacity(0.10)), lineWidth: 0.4)
                    }
                }
                // Market dots at their real coordinates.
                ForEach(indexTickers, id: \.symbol) { t in
                    if let c = Self.coords[t.symbol] {
                        let pos = project(c.lat, c.lon, CGSize(width: w, height: h))
                        MarketDot(ticker: t).position(pos)
                    }
                }
            }
        }
    }

    // Only place the equity indices on the map (commodities/crypto have no city).
    private var indexTickers: [WorldMarkets.Ticker] {
        // De-dupe NYC (S&P/Nasdaq/Dow share a pin) — keep the S&P.
        var seen = Set<String>()
        return tickers.filter { t in
            guard Self.coords[t.symbol] != nil else { return false }
            let c = Self.coords[t.symbol]!
            let key = "\(c.lat),\(c.lon)"
            if seen.contains(key) { return false }
            seen.insert(key); return true
        }
    }

    // Equirectangular projection: lon -180..180 → 0..w, lat 90..-90 → 0..h.
    private func project(_ lat: Double, _ lon: Double, _ size: CGSize) -> CGPoint {
        CGPoint(x: (lon + 180) / 360 * size.width,
                y: (90 - lat) / 180 * size.height)
    }
}

private struct MarketDot: View {
    let ticker: WorldMarkets.Ticker
    var body: some View {
        let up = ticker.dayPct >= 0
        let color: Color = up ? .green : .red
        let intensity = min(1.0, abs(ticker.dayPct) / 4.0)
        return ZStack {
            Circle().fill(color.opacity(0.25 + intensity * 0.4))
                .frame(width: 10 + intensity * 10, height: 10 + intensity * 10)
                .blur(radius: 3)
            Circle().fill(color).frame(width: 7, height: 7)
                .overlay(Circle().strokeBorder(.white.opacity(0.6), lineWidth: 0.5))
        }
        .help("\(ticker.name): \(String(format: "%+.2f%%", ticker.dayPct))")
    }
}
