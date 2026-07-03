import SwiftUI
import PulseKit

/// When each position was opened and how it has done since — dates the user
/// gave us are shown plainly; dates Pulse detected from price history carry
/// a "~" and an EST pill, because an inference is not a fact.
struct TimelineCard: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Card(title: "TIMELINE", trailing: "since invested · ~ = estimated from cost basis") {
            if model.timelines.isEmpty {
                Text("detecting invested dates from price history…")
                    .font(.system(size: 11, design: .monospaced)).foregroundStyle(.tertiary)
            } else {
                Grid(alignment: .trailing, horizontalSpacing: 16, verticalSpacing: 10) {
                    GridRow {
                        head("SYMBOL", leading: true); head("INVESTED"); head("HELD")
                        head("RETURN"); head("ANN."); head("VS S&P"); head("")
                    }
                    ForEach(model.sortedHoldings) { h in
                        if let t = model.timelines[h.symbol] {
                            GridRow {
                                Button {
                                    model.outlookTarget = AppModel.OutlookTarget(symbol: h.symbol)
                                } label: {
                                    HStack(spacing: 4) {
                                        Text(h.symbol)
                                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 8, weight: .semibold))
                                            .foregroundStyle(.tertiary)
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .help("Outlook + lifecycle for \(h.symbol)")
                                .gridColumnAlignment(.leading)
                                HStack(spacing: 5) {
                                    Text(t.acquiredLabel).cell()
                                    if t.estimated { EstPill() }
                                }
                                Text(t.heldLabel).cell()
                                Text(String(format: "%+.1f%%", t.totalReturnPct)).cell()
                                    .foregroundStyle(t.totalReturnPct >= 0 ? Color.green : Color.red)
                                Text(t.annualizedPct.map { String(format: "%+.1f%%/y", $0) } ?? "—").cell()
                                    .foregroundStyle(.secondary)
                                benchCell(t)
                                Sparkline(closes: t.closesSince)
                                    .frame(width: 110, height: 20)
                            }
                        }
                    }
                }
            }
        }
    }

    /// Position return vs the S&P 500 over the SAME window — green only when
    /// it actually beat the index.
    private func benchCell(_ t: PositionTimeline) -> some View {
        Group {
            if let b = t.benchmarkPct {
                let diff = t.totalReturnPct - b
                Text(String(format: "%+.1fpp", diff)).cell()
                    .foregroundStyle(diff >= 0 ? Color.green : Color.orange)
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

private struct EstPill: View {
    var body: some View {
        Text("EST")
            .font(.system(size: 8, weight: .semibold, design: .monospaced))
            .padding(.horizontal, 4).padding(.vertical, 1.5)
            .background(Capsule().fill(Color.yellow.opacity(0.15)))
            .foregroundStyle(Color.yellow)
            .help("No acquired date in portfolio.json — estimated from where the price last crossed your cost basis")
    }
}
