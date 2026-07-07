import SwiftUI
import KeloKit

/// Calls logged as paper trades, scored against what actually happened —
/// entry vs now, vs the S&P over the same window, direction verdict so far.
/// The learning loop: prove the read works on paper before any real order.
struct PaperLedgerCard: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Card(title: "PAPER TRADES", trailing: "calls scored against reality · no real orders") {
            VStack(alignment: .leading, spacing: 10) {
                Grid(alignment: .trailing, horizontalSpacing: 14, verticalSpacing: 9) {
                    GridRow {
                        head("CALL", leading: true); head("DATE"); head("ENTRY")
                        head("NOW"); head("MOVE"); head("VS S&P"); head("SO FAR"); head("")
                    }
                    ForEach(model.paperReviews, id: \.trade.id) { r in
                        GridRow {
                            Text("\(r.trade.side) \(r.trade.symbol)")
                                .font(.system(size: 12.5, weight: .semibold, design: .monospaced))
                                .foregroundStyle(r.trade.side == "BUY" ? Color.green : Color.orange)
                                .gridColumnAlignment(.leading)
                            Text(r.trade.date).cell()
                            Text(usd(r.trade.entryPrice)).cell()
                            Text(r.currentPrice.map(usd) ?? "…").cell()
                            Text(r.movePct.map { String(format: "%+.2f%%", $0) } ?? "—").cell()
                                .foregroundStyle((r.movePct ?? 0) >= 0 ? Color.green : Color.red)
                            Text(r.benchmarkPct.map { String(format: "%+.2f%%", $0) } ?? "—").cell()
                                .foregroundStyle(.secondary)
                            verdict(r)
                            Button {
                                model.deletePaperTrade(id: r.trade.id)
                            } label: {
                                Image(systemName: "xmark.circle").font(.system(size: 11))
                            }
                            .buttonStyle(.plain).foregroundStyle(.tertiary)
                            .help("Remove this paper trade")
                        }
                    }
                }
                if let line = scoreline {
                    Text(line)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var scoreline: String? {
        let scored = model.paperReviews.compactMap(\.callRightSoFar)
        guard !scored.isEmpty else { return nil }
        let right = scored.filter { $0 }.count
        let moves = model.paperReviews.compactMap(\.movePct)
        let benches = model.paperReviews.compactMap(\.benchmarkPct)
        let avgMove = moves.reduce(0, +) / Double(max(1, moves.count))
        let avgBench = benches.isEmpty ? nil : benches.reduce(0, +) / Double(benches.count)
        var s = "direction right so far: \(right)/\(scored.count) · avg move \(String(format: "%+.2f%%", avgMove))"
        if let b = avgBench { s += " vs S&P \(String(format: "%+.2f%%", b))" }
        return s + " — small sample, not an edge"
    }

    private func verdict(_ r: PaperReview) -> some View {
        Group {
            if let right = r.callRightSoFar {
                Image(systemName: right ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(right ? Color.green : Color.red)
            } else {
                Text("—").cell().foregroundStyle(.secondary)
            }
        }
    }

    private func head(_ s: String, leading: Bool = false) -> some View {
        Text(s).font(.system(size: 9, weight: .medium, design: .monospaced))
            .tracking(1).foregroundStyle(.tertiary)
            .gridColumnAlignment(leading ? .leading : .trailing)
    }
}
