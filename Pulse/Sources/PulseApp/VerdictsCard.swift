import SwiftUI
import PulseKit

/// A single decay marker with a tappable "why". The plain line stays inline;
/// the (i) opens a popover with the exact rule, threshold, and reasoning —
/// so no label is ever a mystery.
struct MarkerChip: View {
    let marker: PositionVerdict.Marker
    @State private var showWhy = false
    var body: some View {
        HStack(spacing: 4) {
            Text(marker.text)
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                showWhy.toggle()
            } label: {
                Image(systemName: "info.circle")
                    .font(.system(size: 9)).foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .help("Why this flag fired")
            .popover(isPresented: $showWhy, arrowEdge: .trailing) {
                Text(marker.explanation)
                    .font(.system(size: 12))
                    .frame(width: 320, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(14)
            }
        }
    }
}

/// A committed call for every position — EXIT CANDIDATE / REVIEW / HOLD —
/// with the specific decay markers that fired. Direction without ambiguity,
/// grounded only in what is observably true, never in price prediction.
struct VerdictsCard: View {
    @ObservedObject var model: AppModel
    @State private var showAllExits = false

    var body: some View {
        let verdicts = model.verdicts
        let exits = verdicts.filter { $0.call == .exit }
        let reviews = verdicts.filter { $0.call == .review }
        let holds = verdicts.filter { $0.call == .hold }

        Card(title: "VERDICTS", trailing: "every position, a plain call · condition-based, not prediction") {
            if verdicts.isEmpty {
                Text("waiting for quotes + timelines…")
                    .font(.system(size: 11, design: .monospaced)).foregroundStyle(.tertiary)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        summaryTile("EXIT CANDIDATES", "\(exits.count)",
                                    usd(exits.reduce(0) { $0 + $1.valueAtStake }), .red)
                        summaryTile("REVIEW", "\(reviews.count)",
                                    usd(reviews.reduce(0) { $0 + $1.valueAtStake }), .orange)
                        summaryTile("HOLD", "\(holds.count)",
                                    usd(holds.reduce(0) { $0 + $1.valueAtStake }), .green)
                        Spacer()
                    }
                    if !exits.isEmpty {
                        VStack(alignment: .leading, spacing: 7) {
                            ForEach((showAllExits ? exits : Array(exits.prefix(8))), id: \.symbol) { v in
                                verdictRow(v, color: .red)
                            }
                            if exits.count > 8 {
                                Button(showAllExits ? "show fewer" : "show all \(exits.count) exit candidates") {
                                    showAllExits.toggle()
                                }
                                .font(.system(size: 11))
                            }
                        }
                        Text("EXIT CANDIDATE means: the direction is out, unless you can write down a specific reason this company recovers that the market hasn't priced. If you can't write the sentence, that's the answer. Click a symbol for its lifecycle + news.")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if !reviews.isEmpty {
                        DisclosureGroup("\(reviews.count) positions marked REVIEW — one marker fired") {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(reviews.prefix(20), id: \.symbol) { v in
                                    verdictRow(v, color: .orange)
                                }
                                if reviews.count > 20 {
                                    Text("… and \(reviews.count - 20) more")
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            .padding(.top, 4)
                        }
                        .font(.system(size: 11.5))
                    }
                }
            }
        }
    }

    private func verdictRow(_ v: PositionVerdict, color: Color) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Button {
                model.outlookTarget = AppModel.OutlookTarget(symbol: v.symbol)
            } label: {
                HStack(spacing: 3) {
                    Text(v.symbol)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(color)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 7, weight: .semibold)).foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)
            .frame(minWidth: 86, alignment: .leading)
            // Each marker is its own info chip — tap the (i) for the exact
            // rule and why it matters.
            VStack(alignment: .leading, spacing: 3) {
                ForEach(v.markers.indices, id: \.self) { i in
                    MarkerChip(marker: v.markers[i])
                }
            }
            Spacer()
            Text(usd(v.valueAtStake))
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(.tertiary)
        }
    }

    private func summaryTile(_ label: String, _ count: String, _ value: String, _ color: Color) -> some View {
        summaryTileImpl(label, count, value, color)
    }

    private func summaryTileImpl(_ label: String, _ count: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 8.5, weight: .medium, design: .monospaced))
                .tracking(1).foregroundStyle(.tertiary)
            HStack(spacing: 6) {
                Text(count).font(.system(size: 15, weight: .bold, design: .monospaced))
                    .foregroundStyle(color)
                Text(value).font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
    }
}
