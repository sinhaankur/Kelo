import SwiftUI

/// "What's right / what's wrong" — deterministic stats computed from live
/// data. No model, no opinion: win rate, extremes, concentration, and risk
/// flags with the numbers that justify them.
struct StatsCard: View {
    @ObservedObject var model: AppModel

    private struct PositionStat {
        let label: String
        let plPct: Double
        let dayPct: Double?
        let value: Double
    }

    private var stats: [PositionStat] {
        var out: [PositionStat] = []
        for h in model.portfolio.holdings {
            let cost = h.costBasis * h.quantity
            guard cost > 0, let q = model.quotes[h.symbol] else { continue }
            let value = model.holdingValue(h)
            out.append(.init(label: h.symbol, plPct: (value - cost) / cost * 100,
                             dayPct: q.dayChangePct, value: value))
        }
        for c in model.portfolio.calls {
            guard c.premiumPaid > 0, let v = model.callValue(c) else { continue }
            out.append(.init(label: "\(c.underlying) \(Int(c.strike))C", plPct: (v - c.premiumPaid) / c.premiumPaid * 100,
                             dayPct: nil, value: v))
        }
        return out
    }

    private var flags: [(ok: Bool, text: String)] {
        var f: [(Bool, String)] = []
        let s = stats
        guard !s.isEmpty else { return [] }
        let total = s.reduce(0) { $0 + $1.value }

        let winners = s.filter { $0.plPct >= 0 }.count
        f.append((winners * 2 >= s.count,
                  "Win rate \(winners)/\(s.count) positions in profit"))

        if let top = s.max(by: { $0.value < $1.value }), total > 0 {
            let pct = top.value / total * 100
            f.append((pct <= 40,
                      "Concentration: \(top.label) is \(Int(pct))% of the portfolio\(pct > 40 ? " — heavy" : "")"))
        }
        for c in model.portfolio.calls {
            if let dte = c.daysToExpiry, dte < 14 {
                f.append((false, "\(c.underlying) \(Int(c.strike))C expires in \(dte)d — theta decay is steepest now"))
            }
            if let spot = model.quotes[c.underlying]?.price, spot < c.strike {
                let need = (c.strike - spot) / spot * 100
                f.append((false, "\(c.underlying) \(Int(c.strike))C is OTM — needs \(String(format: "%.1f", need))% move by \(c.expiry)"))
            }
        }
        return f
    }

    var body: some View {
        let s = stats
        VStack(alignment: .leading, spacing: 10) {
            Text("RIGHT / WRONG")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .tracking(2).foregroundStyle(.secondary)

            if s.isEmpty {
                Text("waiting for quotes…").font(.system(size: 11, design: .monospaced)).foregroundStyle(.tertiary)
            } else {
                HStack(spacing: 10) {
                    if let best = s.max(by: { $0.plPct < $1.plPct }) {
                        tile("BEST", best.label, String(format: "%+.1f%%", best.plPct), best.plPct >= 0 ? .green : .red)
                    }
                    if let worst = s.min(by: { $0.plPct < $1.plPct }) {
                        tile("WORST", worst.label, String(format: "%+.1f%%", worst.plPct), worst.plPct >= 0 ? .green : .red)
                    }
                    if let mover = s.compactMap({ st in st.dayPct.map { (st.label, $0) } })
                        .max(by: { abs($0.1) < abs($1.1) }) {
                        tile("TODAY'S MOVER", mover.0, String(format: "%+.2f%%", mover.1), mover.1 >= 0 ? .green : .red)
                    }
                    Spacer()
                }
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(flags.indices, id: \.self) { i in
                        let flag = flags[i]
                        HStack(spacing: 7) {
                            Image(systemName: flag.ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(flag.ok ? Color.green : Color.orange)
                            Text(flag.text).font(.system(size: 11.5)).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.045)))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.white.opacity(0.07)))
    }

    private func tile(_ label: String, _ symbol: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 8.5, weight: .medium, design: .monospaced))
                .tracking(1).foregroundStyle(.tertiary)
            Text(symbol).font(.system(size: 12, weight: .semibold, design: .monospaced))
            Text(value).font(.system(size: 12, design: .monospaced)).foregroundStyle(color)
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.04)))
    }
}
