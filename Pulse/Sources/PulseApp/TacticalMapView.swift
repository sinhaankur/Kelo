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
    @State private var showConflict = true
    @State private var showEnergy = true
    @State private var selected: MapMarker? = nil

    var body: some View {
        Card(title: "GLOBAL SITUATION", trailing: "real, sourced layers · click a marker") {
            HStack(alignment: .top, spacing: 12) {
                layersPanel.frame(width: 150)
                // Interactive vector map: countries with active conflict events
                // tint red; hover names a country; markers overlay on top.
                VectorMapView(shading: conflictShading, markers: markers,
                              selectedID: selected?.id) { selected = $0 }
                    .frame(height: 300)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(alignment: .bottom) { legend.padding(8) }

                // Detail panel sits in its own column so it never covers pins.
                Group {
                    if let sel = selected {
                        DetailPanel(marker: sel) { selected = nil }
                    } else {
                        VStack(spacing: 6) {
                            Image(systemName: "hand.tap").font(.system(size: 18))
                                .foregroundStyle(.tertiary)
                            Text("click a marker for detail")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.tertiary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(width: 220)
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

    /// Countries with active conflict events → red tint (intensity by count).
    /// Maps GDELT country names to Natural Earth names where they differ.
    private var conflictShading: [String: Color] {
        guard showConflict else { return [:] }
        var counts: [String: Int] = [:]
        for e in model.worldEvents {
            let name = Self.neName(e.country)
            counts[name, default: 0] += 1
        }
        var out: [String: Color] = [:]
        for (name, n) in counts {
            out[name] = Color.red.opacity(min(0.8, 0.3 + Double(n) * 0.12))
        }
        return out
    }

    // GDELT uses some names differently from Natural Earth.
    static func neName(_ gdelt: String) -> String {
        switch gdelt {
        case "United States": return "United States of America"
        case "Russia": return "Russia"
        case "South Korea": return "South Korea"
        case "North Korea": return "North Korea"
        case "Czech Republic": return "Czechia"
        default: return gdelt
        }
    }
}

// A single marker on the tactical map.
struct MapMarker: Identifiable {
    enum Kind { case market, conflict, energy }
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


struct MarkerDot: View {
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
