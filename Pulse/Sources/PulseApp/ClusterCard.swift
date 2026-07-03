import SwiftUI
import PulseKit

/// The hidden-concentration warning. 439 tickers can still be one bet — this
/// surfaces the correlated cluster (the option-income ETF complex) as the
/// single risk it actually is, in plain words, on the Overview where it
/// can't be missed.
struct ClusterCard: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Card(title: "CONCENTRATION — HIDDEN", trailing: "many tickers, one bet") {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(model.clusters.indices, id: \.self) { i in
                    let c = model.clusters[i]
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(c.name)
                                .font(.system(size: 13, weight: .semibold))
                            Spacer()
                            Text("\(Int(c.pct))% of the portfolio")
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .foregroundStyle(c.pct > 25 ? Color.red : Color.orange)
                        }
                        // The bar: this cluster vs everything else.
                        GeometryReader { geo in
                            HStack(spacing: 2) {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color.red.opacity(0.8))
                                    .frame(width: max(4, geo.size.width * c.pct / 100))
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color.primary.opacity(0.12))
                            }
                        }
                        .frame(height: 10)
                        Text("\(c.symbols.count) tickers · \(usd(c.value)) · \(c.note)")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Text("diversification is about what your holdings DO, not how many there are. Treat this cluster as one line item when you size and when you cut.")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
