import SwiftUI
import KeloKit

/// The Overview command center — "am I okay, and what do I do today?"
/// answered at a glance. A health banner, the broker's daily brief (top
/// actions ranked by dollars at stake), and clean account stats.

// MARK: - Health banner

/// One honest line on the state of the account, color-coded — the first
/// thing the eye lands on.
struct HealthBanner: View {
    @ObservedObject var model: AppModel

    private enum Health { case good, watch, poor }

    private var assessment: (Health, String, String) {
        let exits = model.verdicts.filter { $0.call == .exit }
        let exitValue = exits.reduce(0.0) { $0 + $1.valueAtStake }
        let clusterPct = model.clusters.first?.pct ?? 0
        let allTimePct = model.totalCost > 0
            ? (model.totalValue - model.totalCost) / model.totalCost * 100 : 0

        if exits.count >= 20 || clusterPct > 30 {
            return (.poor,
                    "Your account needs attention",
                    "\(exits.count) positions are exit candidates (\(usd(exitValue))) and \(Int(clusterPct))% sits in one correlated strategy. The work now is subtraction, not addition — clear the dead weight before adding anything.")
        }
        if exits.count >= 5 || clusterPct > 15 || allTimePct < -5 {
            return (.watch,
                    "Healthy, with cleanup to do",
                    "The core is fine, but \(exits.count) exit candidates and some concentration are dragging on it. Trim those and the account gets simpler and stronger.")
        }
        return (.good,
                "In good shape",
                "No structural alarms. Keep contributing, let the core compound, and don't churn what's working.")
    }

    var body: some View {
        let (health, title, detail) = assessment
        let color: Color = health == .good ? .green : health == .watch ? .orange : .red
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: health == .good ? "checkmark.seal.fill"
                  : health == .watch ? "exclamationmark.triangle.fill" : "cross.case.fill")
                .font(.system(size: 22))
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 15, weight: .semibold))
                Text(detail).font(.system(size: 11.5)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(color.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(color.opacity(0.25)))
    }
}

// MARK: - Broker's daily brief

/// What a broker would put in front of you: the highest-dollar actions,
/// ranked, each a click to its detail. Direction, not a to-read list.
struct DailyBriefCard: View {
    @ObservedObject var model: AppModel

    private struct Item { let icon: String; let color: Color; let text: String; let symbol: String? }

    private var items: [Item] {
        var out: [Item] = []
        // 1. Biggest concentration risk.
        if let c = model.clusters.first, c.pct > 15 {
            out.append(Item(icon: "scalemass", color: .red,
                            text: "Reduce the \(c.symbols.count)-ticker income-ETF cluster — \(Int(c.pct))% of the account (\(usd(c.value))) in one bet",
                            symbol: nil))
        }
        // 2. Exit candidates, as a batch with dollars.
        let exits = model.verdicts.filter { $0.call == .exit }
        if !exits.isEmpty {
            let v = exits.reduce(0.0) { $0 + $1.valueAtStake }
            out.append(Item(icon: "xmark.bin", color: .red,
                            text: "Clear \(exits.count) exit candidates (\(usd(v))) — dead weight with no recovery signal",
                            symbol: exits.first?.symbol))
        }
        // 3. Decaying income — capital coming back as "yield".
        if let r = model.incomeReport {
            let decaying = r.positions.filter(\.decaying)
            if !decaying.isEmpty {
                out.append(Item(icon: "drop.triangle", color: .orange,
                                text: "\(decaying.count) payers are shrinking their distributions — that income is principal returning, not earnings",
                                symbol: decaying.first?.symbol))
            }
        }
        // 4. The constructive move.
        out.append(Item(icon: "arrow.up.forward.circle", color: .green,
                        text: "Redeploy freed cash into a broad index core (e.g. XEQT.TO) and keep contributing — at this size, deposits move the needle more than picks",
                        symbol: nil))
        return out
    }

    var body: some View {
        Card(title: "TODAY'S BRIEF", trailing: "ranked by dollars at stake · your move, not a directive") {
            VStack(alignment: .leading, spacing: 9) {
                ForEach(items.indices, id: \.self) { i in
                    let item = items[i]
                    HStack(alignment: .top, spacing: 9) {
                        Text("\(i + 1)")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .frame(width: 14, alignment: .trailing)
                        Image(systemName: item.icon)
                            .font(.system(size: 12)).foregroundStyle(item.color)
                            .frame(width: 16)
                        if let s = item.symbol {
                            Button { model.outlookTarget = AppModel.OutlookTarget(symbol: s) } label: {
                                Text(item.text).font(.system(size: 11.5)).foregroundStyle(.primary)
                                    .multilineTextAlignment(.leading)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .buttonStyle(.plain)
                        } else {
                            Text(item.text).font(.system(size: 11.5)).foregroundStyle(.primary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                    }
                }
            }
        }
    }
}

// MARK: - Account stats strip

/// The numbers that matter, big and clean: value, invested, all-time,
/// today. One glance answers "where do I stand."
struct AccountStatsCard: View {
    @ObservedObject var model: AppModel

    var body: some View {
        let allTime = model.totalValue - model.totalCost
        let allTimePct = model.totalCost > 0 ? allTime / model.totalCost * 100 : 0
        let holdingsValue = model.portfolio.holdings.reduce(0.0) { $0 + model.holdingValue($1) }
        let dayPct = holdingsValue > 0 ? model.dayPL / holdingsValue * 100 : 0

        Card(title: "ACCOUNT") {
            VStack(alignment: .leading, spacing: 12) {
                // Hero: portfolio value big, with today's move beside it.
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(usd(model.totalValue))
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .contentTransition(.numericText())
                    HStack(spacing: 4) {
                        Image(systemName: model.dayPL >= 0 ? "arrow.up.right" : "arrow.down.right")
                            .font(.system(size: 11, weight: .bold))
                        Text("\(usd(model.dayPL)) (\(String(format: "%+.2f%%", dayPct))) today")
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                    }
                    .foregroundStyle(model.dayPL >= 0 ? .green : .red)
                    Spacer()
                }
                Divider()
                // Sub-stats.
                HStack(spacing: 0) {
                    stat("INVESTED", usd(model.totalCost), nil, .secondary)
                    divider
                    stat("ALL-TIME", usd(allTime), String(format: "%+.1f%%", allTimePct),
                         allTime >= 0 ? .green : .red)
                    divider
                    stat("HOLDINGS", "\(model.portfolio.holdings.count)", "positions", .secondary)
                }
            }
        }
    }

    private var divider: some View {
        Rectangle().fill(Color.primary.opacity(0.08)).frame(width: 1, height: 34)
    }

    private func stat(_ label: String, _ value: String, _ sub: String?, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.system(size: 8.5, weight: .medium, design: .monospaced))
                .tracking(1).foregroundStyle(.tertiary)
            Text(value).font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundStyle(color)
            if let sub {
                Text(sub).font(.system(size: 11, design: .monospaced)).foregroundStyle(color.opacity(0.8))
            } else {
                Text(" ").font(.system(size: 11))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
    }
}
