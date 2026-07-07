import SwiftUI
import KeloKit

/// Last-7-day company headlines for each equity holding (Finnhub, the user's
/// key). Crypto pairs and indices have no company news and are skipped.
struct HoldingsNewsCard: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Card(title: "HOLDINGS NEWS", trailing: "Finnhub · last 7 days") {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(model.portfolio.holdings.map(\.symbol).filter { model.holdingsNews[$0] != nil },
                        id: \.self) { symbol in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(symbol)
                            .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                        ForEach((model.holdingsNews[symbol] ?? []).indices, id: \.self) { i in
                            let h = model.holdingsNews[symbol]![i]
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text("·").foregroundStyle(.tertiary)
                                Text(h.title)
                                    .font(.system(size: 11)).foregroundStyle(.secondary)
                                    .lineLimit(1)
                                Text("\(h.source) · \(relative(h.date))")
                                    .font(.system(size: 9.5, design: .monospaced))
                                    .foregroundStyle(.tertiary)
                                    .layoutPriority(1)
                            }
                        }
                    }
                }
            }
        }
    }

    private func relative(_ d: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f.localizedString(for: d, relativeTo: Date())
    }
}
