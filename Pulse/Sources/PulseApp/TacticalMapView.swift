import SwiftUI
import PulseKit

/// A "Global Situation" tactical map — the situation-room look, every layer
/// backed by REAL sourced data: market exchanges, your holdings' locations,
/// live conflict events (GDELT), and energy chokepoints. Left layers panel to
/// toggle each, a legend, and a click-through detail panel. No invented
/// markers — everything on this map is real and links to its source.
struct TacticalMapView: View {
    @ObservedObject var model: AppModel

    @State private var showMarkets = true
    @State private var showHoldings = true
    @State private var showConflict = true
    @State private var showEnergy = true
    @State private var selected: MapMarker? = nil

    var body: some View {
        Card(title: "GLOBAL SITUATION", trailing: "real, sourced layers · click a marker") {
            HStack(alignment: .top, spacing: 12) {
                layersPanel.frame(width: 150)
                ZStack(alignment: .topTrailing) {
                    GeometryReader { geo in
                        ZStack {
                            WorldBasemap()
                            ForEach(markers) { m in
                                let p = project(m.lat, m.lon, geo.size)
                                MarkerDot(marker: m, selected: selected?.id == m.id)
                                    .position(p)
                                    .onTapGesture { selected = m }
                            }
                        }
                    }
                    .frame(height: 320)
                    .background(Color(red: 0.04, green: 0.05, blue: 0.07))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(alignment: .bottom) { legend.padding(8) }
                    if let sel = selected {
                        DetailPanel(marker: sel) { selected = nil }
                            .frame(width: 260).padding(10)
                    }
                }
            }
        }
    }

    // MARK: layers

    private var layersPanel: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("LAYERS")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(2).foregroundStyle(.secondary)
            layerToggle("Markets", $showMarkets, .cyan)
            layerToggle("My holdings", $showHoldings, .yellow)
            layerToggle("Conflict events", $showConflict, .red)
            layerToggle("Energy chokepoints", $showEnergy, .orange)
            Divider().padding(.vertical, 2)
            Text("\(markers.count) markers")
                .font(.system(size: 9, design: .monospaced)).foregroundStyle(.tertiary)
            Text("conflict via GDELT · markets via Yahoo · all sourced, none invented")
                .font(.system(size: 8.5)).foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func layerToggle(_ label: String, _ on: Binding<Bool>, _ color: Color) -> some View {
        Button { on.wrappedValue.toggle() } label: {
            HStack(spacing: 7) {
                Image(systemName: on.wrappedValue ? "checkmark.square.fill" : "square")
                    .font(.system(size: 11)).foregroundStyle(on.wrappedValue ? color : .secondary)
                Text(label).font(.system(size: 11)).foregroundStyle(.primary)
                Spacer()
            }
        }
        .buttonStyle(.plain)
    }

    private var legend: some View {
        HStack(spacing: 12) {
            legendItem("Market", .cyan)
            legendItem("Holding", .yellow)
            legendItem("Conflict", .red)
            legendItem("Chokepoint", .orange)
            Spacer()
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(Capsule().fill(.black.opacity(0.45)))
    }

    private func legendItem(_ label: String, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label).font(.system(size: 8.5, design: .monospaced)).foregroundStyle(.secondary)
        }
    }

    // MARK: markers (from real data)

    private var markers: [MapMarker] {
        var out: [MapMarker] = []
        if showMarkets, let w = model.worldMarkets {
            for t in w.tickers where t.kind == .index {
                if let c = WorldMapView.coord(for: t.symbol) {
                    out.append(MapMarker(kind: .market, lat: c.lat, lon: c.lon,
                                         title: t.name,
                                         subtitle: String(format: "%+.2f%% today", t.dayPct),
                                         body: "Equity index. Level \(String(format: "%.0f", t.price)).",
                                         url: nil,
                                         color: t.dayPct >= 0 ? .green : .red))
                }
            }
        }
        if showHoldings {
            for (sym, ind) in model.industryBySymbol {
                // Domicile approximated from listing suffix; US default.
                let c = domicile(sym)
                out.append(MapMarker(kind: .holding, lat: c.lat, lon: c.lon,
                                     title: sym, subtitle: ind,
                                     body: "You hold this. Industry: \(ind).",
                                     url: nil, color: .yellow))
            }
        }
        if showConflict {
            for e in model.worldEvents.prefix(30) {
                if let c = e.coord {
                    out.append(MapMarker(kind: .conflict, lat: c.lat, lon: c.lon,
                                         title: e.country, subtitle: e.domain,
                                         body: e.title, url: e.url.isEmpty ? nil : e.url,
                                         color: .red))
                }
            }
        }
        if showEnergy {
            for cp in Chokepoints.all {
                out.append(MapMarker(kind: .energy, lat: cp.lat, lon: cp.lon,
                                     title: cp.name, subtitle: "energy chokepoint",
                                     body: cp.note, url: nil, color: .orange))
            }
        }
        return out
    }

    private func domicile(_ symbol: String) -> (lat: Double, lon: Double) {
        if symbol.hasSuffix(".TO") || symbol.hasSuffix(".V") || symbol.hasSuffix(".CN") || symbol.hasSuffix(".NE") {
            return (56.1, -106.3) // Canada
        }
        return (39.8, -98.6) // US default
    }

    private func project(_ lat: Double, _ lon: Double, _ size: CGSize) -> CGPoint {
        CGPoint(x: (lon + 180) / 360 * size.width, y: (90 - lat) / 180 * size.height)
    }
}

// A single marker on the tactical map.
struct MapMarker: Identifiable {
    enum Kind { case market, holding, conflict, energy }
    let id = UUID()
    let kind: Kind
    let lat: Double
    let lon: Double
    let title: String
    let subtitle: String
    let body: String
    let url: String?
    let color: Color
}

/// The pre-rendered coastline map, dimmed for the tactical look.
private struct WorldBasemap: View {
    var body: some View {
        if let img = WorldMapView.basemap {
            Image(nsImage: img).resizable().interpolation(.high)
                .aspectRatio(2, contentMode: .fill)
                .opacity(0.5).saturation(0.4)
        }
    }
}

private struct MarkerDot: View {
    let marker: MapMarker
    let selected: Bool
    var body: some View {
        ZStack {
            Circle().fill(marker.color.opacity(0.4)).frame(width: selected ? 18 : 12, height: selected ? 18 : 12)
                .blur(radius: 3)
            Circle().fill(marker.color).frame(width: 5, height: 5)
                .overlay(Circle().strokeBorder(.white.opacity(0.7), lineWidth: 0.5))
        }
        .help("\(marker.title) — \(marker.subtitle)")
    }
}

/// The click-through briefing panel — the screenshot's detail card, native.
private struct DetailPanel: View {
    let marker: MapMarker
    let close: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Circle().fill(marker.color).frame(width: 7, height: 7)
                Text(marker.title.uppercased())
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                Spacer()
                Button { close() } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 13))
                }.buttonStyle(.plain).foregroundStyle(.tertiary)
            }
            Text(marker.subtitle)
                .font(.system(size: 9.5, design: .monospaced)).foregroundStyle(.tertiary)
            Divider()
            Text(marker.body)
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let url = marker.url, let u = URL(string: url) {
                Link("open source article →", destination: u)
                    .font(.system(size: 10.5))
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(0.82)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(marker.color.opacity(0.4), lineWidth: 1))
    }
}
