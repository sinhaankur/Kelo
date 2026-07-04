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
        "^BSESN": (19.1, 72.9),   // Mumbai
        "^AXJO": (-33.9, 151.2),  // Sydney
    ]

    /// Exchange coordinate lookup, shared with the tactical map.
    static func coord(for symbol: String) -> (lat: Double, lon: Double)? {
        coords[symbol]
    }
    /// The shared basemap image, for the tactical view.
    static var basemap: NSImage? { mapImage }

    // The bundled, pre-rendered map image (anti-aliased, transparent land on
    // clear background) — loaded once from the app bundle.
    static let mapImage: NSImage? = {
        if let url = Bundle.main.url(forResource: "worldmap", withExtension: "png"),
           let img = NSImage(contentsOf: url) { return img }
        // Dev fallback: load from the source Resources dir.
        let dev = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Resources/worldmap.png")
        return NSImage(contentsOf: dev)
    }()

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                // Deep-ocean radial backdrop.
                RadialGradient(colors: [Color(red: 0.08, green: 0.15, blue: 0.26),
                                        Color(red: 0.02, green: 0.04, blue: 0.09)],
                               center: .center, startRadius: 20, endRadius: w * 0.75)
                // The pre-rendered world map (crisp, anti-aliased).
                if let img = Self.mapImage {
                    Image(nsImage: img)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(2, contentMode: .fill)
                }
                // Live glowing market pins at real coordinates.
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
    @State private var hovering = false
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
            // Ring — brightens on hover.
            Circle().strokeBorder(color.opacity(hovering ? 1 : 0.8), lineWidth: hovering ? 2 : 1.2)
                .frame(width: hovering ? 18 : 14, height: hovering ? 18 : 14)
            // Bright core.
            Circle().fill(color).frame(width: 8, height: 8)
                .overlay(Circle().fill(.white.opacity(0.7)).frame(width: 3, height: 3).offset(x: -1, y: -1))
                .shadow(color: color, radius: 4)
        }
        .contentShape(Circle().size(width: 28, height: 28).offset(x: -14, y: -14))
        .onHover { hovering = $0 }
        .popover(isPresented: $hovering, arrowEdge: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text(ticker.name).font(.system(size: 12, weight: .semibold))
                HStack(spacing: 6) {
                    Text(String(format: "%+.2f%%", ticker.dayPct))
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundStyle(up ? .green : .red)
                    Text("today").font(.system(size: 10)).foregroundStyle(.tertiary)
                }
                Text(String(format: "%.1f", ticker.price))
                    .font(.system(size: 10.5, design: .monospaced)).foregroundStyle(.secondary)
            }
            .padding(10)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}
