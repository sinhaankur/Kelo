import SwiftUI
import PulseKit

/// A native interactive vector world map — real per-country polygons (Natural
/// Earth, bundled) drawn with Canvas. Countries can be individually filled and
/// shaded: e.g. tinted red where there are active conflict events. Hovering a
/// country highlights it and names it. Markers (markets, chokepoints, events)
/// overlay on top. All native, offline, no web view.
struct VectorMapView: View {
    /// Country name → tint (e.g. conflict shading). Names match Natural Earth.
    let shading: [String: Color]
    let markers: [MapMarker]
    let selectedID: UUID?
    let onTapMarker: (MapMarker) -> Void

    @State private var hoverCountry: String? = nil

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack {
                // Ocean.
                LinearGradient(colors: [Color(red: 0.04, green: 0.07, blue: 0.12),
                                        Color(red: 0.02, green: 0.03, blue: 0.06)],
                               startPoint: .top, endPoint: .bottom)
                // Countries.
                Canvas { ctx, sz in
                    for country in WorldCountries.all {
                        let path = countryPath(country, sz)
                        let tint = shading[country.name]
                        let base = Color(red: 0.14, green: 0.20, blue: 0.29)
                        let fill = tint?.opacity(0.55) ?? base
                        let isHover = hoverCountry == country.name
                        ctx.fill(path, with: .color(isHover ? fill.opacity(0.95) : fill))
                        ctx.stroke(path, with: .color(Color.white.opacity(isHover ? 0.4 : 0.12)),
                                   lineWidth: isHover ? 1 : 0.4)
                    }
                }
                // Hover label.
                if let hc = hoverCountry {
                    Text(hc)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Capsule().fill(.black.opacity(0.7)))
                        .foregroundStyle(.white)
                        .position(x: 70, y: 16)
                }
                // Markers.
                ForEach(markers) { m in
                    let p = project(m.lat, m.lon, size)
                    MarkerDot(marker: m, selected: selectedID == m.id)
                        .position(p)
                        .onTapGesture { onTapMarker(m) }
                }
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let pt): hoverCountry = country(at: pt, size)
                case .ended: hoverCountry = nil
                }
            }
        }
    }

    private func countryPath(_ c: GeoCountry, _ size: CGSize) -> Path {
        var path = Path()
        for poly in c.polygons {
            var i = 0
            while i + 1 < poly.count {
                let pt = project(Double(poly[i + 1]), Double(poly[i]), size)
                if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
                i += 2
            }
            path.closeSubpath()
        }
        return path
    }

    // Hit-test which country a point falls in (bounding-box then contains).
    private func country(at pt: CGPoint, _ size: CGSize) -> String? {
        for c in WorldCountries.all {
            if countryPath(c, size).contains(pt) { return c.name }
        }
        return nil
    }

    private func project(_ lat: Double, _ lon: Double, _ size: CGSize) -> CGPoint {
        CGPoint(x: (lon + 180) / 360 * size.width, y: (90 - lat) / 180 * size.height)
    }
}
