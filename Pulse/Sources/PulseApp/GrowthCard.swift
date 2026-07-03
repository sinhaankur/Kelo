import SwiftUI
import PulseKit

/// The account's actual growth curve — holdings market value reconstructed
/// day by day from each position's invested date, drawn against the capital
/// deployed. Options are excluded (no historical marks) and the card says so.
struct GrowthCard: View {
    @ObservedObject var model: AppModel

    var body: some View {
        let coverage: String? = model.portfolioHistory.flatMap { h in
            h.covered < h.total ? "covers \(h.covered) of \(h.total) positions — others lack price history" : nil
        }
        Card(title: "GROWTH", trailing: coverage ?? "value vs cost deployed · options excluded") {
            if let h = model.portfolioHistory, h.values.count >= 2,
               let first = h.dates.first, let lastValue = h.values.last, let lastCost = h.costs.last {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 14) {
                        Text(usd(lastValue))
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                        let gain = lastValue - lastCost
                        Text("\(usd(abs(gain))) \(gain >= 0 ? "above" : "below") cost")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(gain >= 0 ? Color.green : Color.red)
                        Spacer()
                        Text("since \(isoDateString(first))")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                    GrowthChart(values: h.values, costs: h.costs)
                        .frame(height: 90)
                    if let latest = model.snapshots.last {
                        Text("recorded incl. options: \(model.snapshots.count) day\(model.snapshots.count == 1 ? "" : "s") · latest \(usd(latest.total)) — real marks logged daily from now on")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                }
            } else {
                Text("reconstructing account history from invested dates…")
                    .font(.system(size: 11, design: .monospaced)).foregroundStyle(.tertiary)
            }
        }
    }
}

/// Value line with gradient underfill + dashed cost-deployed steps.
private struct GrowthChart: View {
    let values: [Double]
    let costs: [Double]

    var body: some View {
        GeometryReader { geo in
            let all = values + costs
            if let lo = all.min(), let hi = all.max(), hi > lo {
                let up = (values.last ?? 0) >= (costs.last ?? 0)
                let color: Color = up ? .green : .red
                let vPts = points(values, lo: lo, hi: hi, size: geo.size)
                let cPts = points(costs, lo: lo, hi: hi, size: geo.size)
                ZStack {
                    Path { p in
                        p.move(to: CGPoint(x: vPts[0].x, y: geo.size.height))
                        for pt in vPts { p.addLine(to: pt) }
                        p.addLine(to: CGPoint(x: vPts.last!.x, y: geo.size.height))
                        p.closeSubpath()
                    }
                    .fill(LinearGradient(colors: [color.opacity(0.18), .clear],
                                         startPoint: .top, endPoint: .bottom))
                    Path { p in
                        p.move(to: cPts[0])
                        for pt in cPts.dropFirst() { p.addLine(to: pt) }
                    }
                    .stroke(Color.secondary.opacity(0.6),
                            style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    Path { p in
                        p.move(to: vPts[0])
                        for pt in vPts.dropFirst() { p.addLine(to: pt) }
                    }
                    .stroke(color.opacity(0.9), lineWidth: 1.6)
                }
            }
        }
    }

    private func points(_ series: [Double], lo: Double, hi: Double, size: CGSize) -> [CGPoint] {
        series.enumerated().map { i, v in
            CGPoint(x: size.width * CGFloat(i) / CGFloat(max(1, series.count - 1)),
                    y: size.height * (1 - CGFloat((v - lo) / (hi - lo))))
        }
    }
}
