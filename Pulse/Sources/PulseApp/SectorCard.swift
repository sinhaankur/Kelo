import SwiftUI
import PulseKit

/// What your money is actually exposed to, by industry — so single-sector
/// concentration (all tech, all banks, all one income strategy) is visible.
/// This is the risk that hides behind "I own lots of stocks": if they're all
/// in one sector, one shock hits all of them together.
struct SectorCard: View {
    @ObservedObject var model: AppModel

    private let palette: [Color] = [.cyan, .orange, .purple, .green, .pink, .yellow,
                                    .blue, .mint, .red, .teal, .indigo]

    var body: some View {
        Card(title: "SECTORS & INDUSTRIES", trailing: model.industryBySymbol.isEmpty
             ? "needs a Finnhub key for industry data" : "where your money actually works") {
            let slices = model.sectors
            if slices.isEmpty {
                Text("resolving industries for your holdings…")
                    .font(.system(size: 11, design: .monospaced)).foregroundStyle(.tertiary)
            } else {
                let total = slices.reduce(0.0) { $0 + $1.value }
                VStack(alignment: .leading, spacing: 10) {
                    // Stacked bar of the whole portfolio by sector.
                    GeometryReader { geo in
                        HStack(spacing: 2) {
                            ForEach(slices.indices, id: \.self) { i in
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(palette[i % palette.count].opacity(0.8))
                                    .frame(width: max(3, geo.size.width * slices[i].value / total))
                            }
                        }
                    }
                    .frame(height: 14)
                    // Legend rows with % and a concentration flag.
                    ForEach(slices.indices, id: \.self) { i in
                        let s = slices[i]
                        HStack(spacing: 8) {
                            Circle().fill(palette[i % palette.count]).frame(width: 7, height: 7)
                            Text(s.name).font(.system(size: 11.5))
                            Text("\(s.count)")
                                .font(.system(size: 9.5, design: .monospaced))
                                .foregroundStyle(.tertiary)
                            Spacer()
                            Text(usd(s.value)).font(.system(size: 10.5, design: .monospaced))
                                .foregroundStyle(.secondary)
                            Text("\(Int(s.pct))%")
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundStyle(s.pct > 30 ? .red : s.pct > 20 ? .orange : .secondary)
                                .frame(width: 38, alignment: .trailing)
                        }
                    }
                    if let top = slices.first, top.pct > 30 {
                        Text("⚠ \(Int(top.pct))% sits in \(top.name.lowercased()) — a shock to that one sector hits that whole slice at once. Real diversification spreads across sectors, not just tickers.")
                            .font(.system(size: 10.5)).foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}
