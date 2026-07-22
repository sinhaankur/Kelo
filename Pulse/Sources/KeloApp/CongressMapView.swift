import SwiftUI
import KeloKit

/// The Congress trades map — members plotted on the US by the state they
/// represent, marker coloured by their net disclosed direction (more buys =
/// green, more sells = red). Click a state's marker for that member's recent
/// moves and honest scorecard. Reuses the same VectorMapView + MapMarker as the
/// tactical map; every marker is real, sourced disclosure data, nothing invented.
struct CongressMapView: View {
    @ObservedObject var model: AppModel
    @State private var selected: MapMarker? = nil

    var body: some View {
        Card(title: "CONGRESS TRADES MAP",
             trailing: "members by state · click a marker") {
            VStack(alignment: .leading, spacing: 8) {
                honestyCaption
                HStack(alignment: .top, spacing: 12) {
                    VectorMapView(shading: [:], markers: markers, selectedID: selected?.id) {
                        selected = $0
                    }
                    .frame(height: 300)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(alignment: .bottom) { legend.padding(8) }

                    Group {
                        if let sel = selected {
                            DetailPanel(marker: sel) { selected = nil }
                        } else {
                            VStack(spacing: 6) {
                                Image(systemName: "hand.tap").font(.system(size: 18))
                                    .foregroundStyle(.tertiary)
                                Text(model.congressTrades.isEmpty
                                     ? "fetching disclosures…" : "click a state for its member")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.tertiary)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                    .frame(width: 220)
                }
            }
        }
    }

    private var honestyCaption: some View {
        Text("disclosed under the STOCK Act · filed 30–45+ days after the trade · amounts are ranges · backward-looking, not a signal")
            .font(.system(size: 9.5, design: .monospaced))
            .foregroundStyle(.tertiary)
            .fixedSize(horizontal: false, vertical: true)
    }

    // One marker per state, summarizing the members who trade from there. Color
    // by net direction across that state's disclosed moves.
    private var markers: [MapMarker] {
        let byState = Dictionary(grouping: model.congressTrades.filter { $0.isEquity && $0.state != nil },
                                 by: { $0.state!.uppercased() })
        return byState.compactMap { state, rows -> MapMarker? in
            guard let c = CongressGeo.center(state) else { return nil }
            let buys = rows.filter { $0.kind == .buy }.count
            let sells = rows.filter { $0.kind == .sell }.count
            let members = Set(rows.map(\.filerName))
            let color: Color = buys > sells ? .green : (sells > buys ? .red : .yellow)
            let topMembers = members.prefix(4).joined(separator: ", ")
            let body = "\(rows.count) disclosed moves · \(buys) buys / \(sells) sells\nMembers: \(topMembers)\(members.count > 4 ? " +\(members.count - 4) more" : "")"
            return MapMarker(kind: .congress, lat: c.lat, lon: c.lon,
                             title: state, subtitle: "\(members.count) member\(members.count == 1 ? "" : "s")",
                             body: body, url: nil, color: color)
        }
    }

    private var legend: some View {
        HStack(spacing: 12) {
            legendItem("Net buying", .green)
            legendItem("Net selling", .red)
            legendItem("Even", .yellow)
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
}
