import SwiftUI
import PulseKit

/// The honest "what should I buy or sell": rule-based structural findings,
/// ranked by the dollars at stake, each with its arithmetic shown. Framed as
/// questions to answer, never orders to follow — and any of them can be
/// tested as a paper trade before a cent moves.
struct ReviewCard: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Card(title: "PORTFOLIO REVIEW", trailing: "rule-based · ranked by dollars at stake · not directives") {
            if model.reviewItems.isEmpty {
                Text(model.quotes.isEmpty
                     ? "waiting for quotes…"
                     : "no structural findings — concentration, laggards, dust and dead symbols all clear")
                    .font(.system(size: 11, design: .monospaced)).foregroundStyle(.tertiary)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(model.reviewItems.indices, id: \.self) { i in
                        let item = model.reviewItems[i]
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: icon(item.kind))
                                .font(.system(size: 12))
                                .foregroundStyle(color(item.kind))
                                .frame(width: 16)
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    if let s = item.symbol {
                                        Button {
                                            model.outlookTarget = AppModel.OutlookTarget(symbol: s)
                                        } label: {
                                            HStack(spacing: 3) {
                                                Text(item.headline)
                                                    .font(.system(size: 12, weight: .semibold))
                                                Image(systemName: "chevron.right")
                                                    .font(.system(size: 7, weight: .semibold))
                                                    .foregroundStyle(.tertiary)
                                            }
                                        }
                                        .buttonStyle(.plain)
                                    } else {
                                        Text(item.headline)
                                            .font(.system(size: 12, weight: .semibold))
                                    }
                                    Spacer()
                                    Text(usd(item.dollarImpact))
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundStyle(color(item.kind))
                                }
                                Text(item.detail)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    Text("test any of these as a paper trade in Trade — Pulse scores the call over time before real money moves")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private func icon(_ k: ReviewItem.Kind) -> String {
        switch k {
        case .concentration: return "scalemass"
        case .laggard: return "tortoise"
        case .dust: return "circle.dotted"
        case .dead: return "questionmark.circle"
        }
    }

    private func color(_ k: ReviewItem.Kind) -> Color {
        switch k {
        case .concentration: return .orange
        case .laggard: return .red
        case .dust: return .yellow
        case .dead: return .secondary
        }
    }
}
