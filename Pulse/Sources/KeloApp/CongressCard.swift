import SwiftUI
import KeloKit

/// The Congress trades tables — "how each trader is doing" (per-member
/// scorecards) and "what each move is" (recent disclosures). Every number is
/// sourced from the disclosure feed; the performance is backward-looking and
/// labelled as such, never a forecast or a buy signal.
struct CongressCard: View {
    @ObservedObject var model: AppModel

    var body: some View {
        if model.congressTrades.isEmpty {
            Card(title: "CONGRESS TRADES") {
                Text("fetching STOCK Act disclosures… (both chambers, updates a few times a day)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
        } else {
            activeMembersCard
            recentMovesCard
        }
    }

    // MARK: most-active members (how each trader is doing)

    private var activeMembersCard: some View {
        Card(title: "MOST ACTIVE MEMBERS",
             trailing: "hit-rate = disclosed moves that worked, backward-looking") {
            Grid(alignment: .trailing, horizontalSpacing: 16, verticalSpacing: 9) {
                GridRow {
                    head("MEMBER", leading: true); head("STATE"); head("MOVES")
                    head("HIT-RATE"); head("AVG SINCE")
                }
                ForEach(model.congressScores.prefix(12)) { s in
                    GridRow {
                        HStack(spacing: 5) {
                            partyDot(s.party)
                            Text(s.filerName)
                                .font(.system(size: 12, weight: .medium))
                                .lineLimit(1)
                        }
                        .gridColumnAlignment(.leading)
                        Text(s.state ?? "—").cell().foregroundStyle(.secondary)
                        Text("\(s.tradeCount)").cell()
                        // Only claim a hit-rate when moves were actually scored.
                        Text(s.hitRate.map { String(format: "%.0f%%", $0 * 100) } ?? "—")
                            .cell()
                            .foregroundStyle(hitColor(s.hitRate))
                        RetPill(fraction: s.avgReturnSince)
                    }
                }
            }
        }
    }

    // MARK: recent moves (what each move is)

    private var recentMovesCard: some View {
        Card(title: "RECENT DISCLOSED MOVES",
             trailing: "click a ticker for its outlook") {
            Grid(alignment: .trailing, horizontalSpacing: 14, verticalSpacing: 9) {
                GridRow {
                    head("MEMBER", leading: true); head("TICKER"); head("ACTION")
                    head("AMOUNT"); head("FILED"); head("SINCE")
                }
                ForEach(model.congressTrades.filter { $0.isEquity }.prefix(30)) { t in
                    GridRow {
                        Text(t.filerName)
                            .font(.system(size: 11.5)).lineLimit(1)
                            .gridColumnAlignment(.leading)
                        Button {
                            model.outlookTarget = AppModel.OutlookTarget(symbol: t.ticker)
                        } label: {
                            HStack(spacing: 3) {
                                Text(t.ticker)
                                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 7)).foregroundStyle(.tertiary)
                            }
                        }
                        .buttonStyle(.plain)
                        .help("Outlook for \(t.ticker)")
                        ActionPill(kind: t.kind)
                        Text(t.amountLabel ?? amountFallback(t))
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundStyle(.secondary)
                        LagBadge(days: t.disclosureLagDays)
                        RetPill(fraction: t.returnSince)
                    }
                }
            }
        }
    }

    // MARK: helpers

    private func amountFallback(_ t: CongressTrade) -> String {
        guard let lo = t.amountLow, let hi = t.amountHigh else { return "—" }
        return "\(usd(lo))–\(usd(hi))"
    }

    private func hitColor(_ r: Double?) -> Color {
        guard let r else { return .secondary }
        return r >= 0.6 ? .green : (r <= 0.4 ? .red : .primary)
    }

    private func partyDot(_ party: String?) -> some View {
        let color: Color = party == "D" ? .blue : (party == "R" ? .red : .gray)
        return Circle().fill(color.opacity(0.8)).frame(width: 6, height: 6)
    }

    private func head(_ s: String, leading: Bool = false) -> some View {
        Text(s).font(.system(size: 9, weight: .medium, design: .monospaced))
            .tracking(1).foregroundStyle(.tertiary)
            .gridColumnAlignment(leading ? .leading : .trailing)
    }
}

// MARK: - Small pills

/// Post-disclosure return as a fraction (0.25 = +25%). "—" when the feed hasn't
/// computed it — never a guessed number.
private struct RetPill: View {
    let fraction: Double?
    var body: some View {
        let v = (fraction ?? 0) * 100
        Text(fraction.map { String(format: "%+.0f%%", $0 * 100) } ?? "—")
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .padding(.horizontal, 7).padding(.vertical, 2.5)
            .background(Capsule().fill((v >= 0 ? Color.green : Color.red)
                .opacity(fraction == nil ? 0.06 : 0.14)))
            .foregroundStyle(fraction == nil ? Color.secondary
                             : (v >= 0 ? Color.green : Color.red))
    }
}

private struct ActionPill: View {
    let kind: CongressTrade.Kind
    var body: some View {
        let (label, color): (String, Color) = {
            switch kind {
            case .buy: return ("BUY", .green)
            case .sell: return ("SELL", .red)
            case .exchange: return ("EXCH", .orange)
            case .unknown: return ("—", .secondary)
            }
        }()
        Text(label)
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .padding(.horizontal, 7).padding(.vertical, 2.5)
            .background(Capsule().fill(color.opacity(0.14)))
            .foregroundStyle(color)
    }
}

/// Disclosure lag — the legally-permitted delay that makes this backward-looking.
/// Orange when unusually late (>45d), so the honesty is visible per row.
private struct LagBadge: View {
    let days: Int?
    var body: some View {
        let d = days ?? 0
        Text(days.map { "\($0)d" } ?? "—")
            .font(.system(size: 10.5, weight: .medium, design: .monospaced))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(d > 45 ? Color.orange.opacity(0.16)
                                       : Color.primary.opacity(0.06)))
            .foregroundStyle(d > 45 ? .orange : .secondary)
            .help("Filed \(days.map(String.init) ?? "?") days after the trade")
    }
}
