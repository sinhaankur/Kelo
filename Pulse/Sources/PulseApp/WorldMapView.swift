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
                // Deep-ocean radial backdrop.
                RadialGradient(colors: [Color(red: 0.07, green: 0.13, blue: 0.22),
                                        Color(red: 0.02, green: 0.04, blue: 0.09)],
                               center: .center, startRadius: 20, endRadius: w * 0.7)
                // Faint lat/long graticule for a "control room" feel.
                Canvas { ctx, size in
                    let line = Color.white.opacity(0.04)
                    for gx in stride(from: 0.0, through: 360.0, by: 30.0) {
                        let x = gx / 360 * size.width
                        ctx.stroke(Path { $0.move(to: CGPoint(x: x, y: 0)); $0.addLine(to: CGPoint(x: x, y: size.height)) },
                                   with: .color(line), lineWidth: 0.5)
                    }
                    for gy in stride(from: 0.0, through: 180.0, by: 30.0) {
                        let y = gy / 180 * size.height
                        ctx.stroke(Path { $0.move(to: CGPoint(x: 0, y: y)); $0.addLine(to: CGPoint(x: size.width, y: y)) },
                                   with: .color(line), lineWidth: 0.5)
                    }
                }
                // Continents — real coastlines, filled with a subtle vertical
                // gradient and a crisp lit edge.
                Canvas { ctx, size in
                    let fill = GraphicsContext.Shading.linearGradient(
                        Gradient(colors: [Color(red: 0.20, green: 0.30, blue: 0.42),
                                          Color(red: 0.13, green: 0.20, blue: 0.30)]),
                        startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height))
                    for poly in WorldGeo.polygons {
                        var p = Path()
                        var i = 0
                        while i + 1 < poly.count {
                            let cg = project(Double(poly[i + 1]), Double(poly[i]), size)
                            if i == 0 { p.move(to: cg) } else { p.addLine(to: cg) }
                            i += 2
                        }
                        p.closeSubpath()
                        ctx.fill(p, with: fill)
                        ctx.stroke(p, with: .color(Color(red: 0.45, green: 0.62, blue: 0.80).opacity(0.5)),
                                   lineWidth: 0.5)
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
            .overlay(RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
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
    @State private var pulse = false
    var body: some View {
        let up = ticker.dayPct >= 0
        let color: Color = up ? Color(red: 0.25, green: 0.9, blue: 0.5)
                              : Color(red: 1.0, green: 0.35, blue: 0.4)
        let intensity = min(1.0, abs(ticker.dayPct) / 4.0)
        return ZStack {
            // Outer breathing halo.
            Circle().fill(color.opacity(0.35))
                .frame(width: 22 + intensity * 16, height: 22 + intensity * 16)
                .blur(radius: 7)
                .scaleEffect(pulse ? 1.15 : 0.9)
            // Ring.
            Circle().strokeBorder(color.opacity(0.8), lineWidth: 1.2)
                .frame(width: 14, height: 14)
            // Bright core.
            Circle().fill(color).frame(width: 8, height: 8)
                .overlay(Circle().fill(.white.opacity(0.7)).frame(width: 3, height: 3).offset(x: -1, y: -1))
                .shadow(color: color, radius: 4)
        }
        .help("\(ticker.name): \(String(format: "%+.2f%%", ticker.dayPct)) today")
        .onAppear {
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}
