import SwiftUI
import KeloKit

/// Trade ideas from observable signals in the user's own book — longs from
/// working uptrends, shorts from broken charts. Blunt rule printed on the
/// card: every idea goes to paper first, and the paper score decides whether
/// the read deserves real money.
struct IdeasCard: View {
    @ObservedObject var model: AppModel

    var body: some View {
        let ideas = ReviewService.ideas(holdings: model.portfolio.holdings,
                                        quotes: model.quotes,
                                        timelines: model.timelines,
                                        verdicts: model.verdicts,
                                        fxRates: model.fxRates)
        Card(title: "TRADE IDEAS", trailing: "signal-based candidates · paper first, always") {
            if ideas.longs.isEmpty && ideas.shorts.isEmpty {
                Text("no candidates yet — waiting for quotes + timelines")
                    .font(.system(size: 11, design: .monospaced)).foregroundStyle(.tertiary)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    if !ideas.longs.isEmpty {
                        ideaList("LONG CANDIDATES — uptrends that are working", ideas.longs, .green)
                    }
                    if !ideas.shorts.isEmpty {
                        ideaList("SHORT CANDIDATES — broken charts (paper only)", ideas.shorts, .red)
                    }
                    Text("log any of these in the draft below — Pulse scores every call against reality and the S&P; the score, not the feeling, decides what gets real money")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func ideaList(_ title: String, _ ideas: [TradeIdea], _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .tracking(1).foregroundStyle(.tertiary)
            ForEach(ideas, id: \.symbol) { idea in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Button {
                        model.outlookTarget = AppModel.OutlookTarget(symbol: idea.symbol)
                    } label: {
                        HStack(spacing: 3) {
                            Text(idea.symbol)
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                .foregroundStyle(color)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 7)).foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                    .frame(minWidth: 86, alignment: .leading)
                    Text(idea.thesis)
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                }
            }
        }
    }
}
