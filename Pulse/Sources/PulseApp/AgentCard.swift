import SwiftUI
import PulseKit

/// The Pulse Agent's home: what it's doing, the calls it has made, and —
/// front and center — its own hit rate. An agent that claims to know what
/// makes money must keep score in the open; this one does, on paper, before
/// any suggestion deserves a real dollar.
struct AgentCard: View {
    @ObservedObject var model: AppModel
    @AppStorage("agentEnabled") private var agentEnabled = true

    var body: some View {
        let agentReviews = model.paperReviews.filter { $0.trade.source == "agent" }
        let score = AgentService.scorecard(reviews: model.paperReviews)
        let state = AgentService.loadState()

        Card(title: "PULSE AGENT", trailing: agentEnabled ? "working — scans every refresh, calls at most once a day" : "paused") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    Toggle("Agent on", isOn: $agentEnabled)
                        .toggleStyle(.switch)
                        .font(.system(size: 11))
                        .fixedSize()
                    if score.scored > 0 {
                        Text("record: \(score.right)/\(score.scored) right so far")
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                            .foregroundStyle(score.right * 2 >= score.scored ? Color.green : Color.red)
                        if let m = score.avgMove {
                            Text("avg move \(String(format: "%+.2f%%", m))\(score.avgBench.map { " vs S&P \(String(format: "%+.2f%%", $0))" } ?? "")")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text("no scored calls yet — the record starts with its first call")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                }

                if agentReviews.isEmpty {
                    Text(agentEnabled
                         ? "the agent makes its first call when a candidate clears the signal bar (uptrend intact + beating the index, or a confirmed broken chart) — discipline over activity"
                         : "paused — flip the switch and it resumes scanning")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(agentReviews, id: \.trade.id) { r in
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 8) {
                                    Button {
                                        model.outlookTarget = AppModel.OutlookTarget(symbol: r.trade.symbol)
                                    } label: {
                                        HStack(spacing: 3) {
                                            Text("\(r.trade.side) \(r.trade.symbol)")
                                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                                .foregroundStyle(r.trade.side == "BUY" ? Color.green : Color.orange)
                                            Image(systemName: "chevron.right")
                                                .font(.system(size: 7)).foregroundStyle(.tertiary)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                    Text(r.trade.date)
                                        .font(.system(size: 10.5, design: .monospaced))
                                        .foregroundStyle(.tertiary)
                                    Text(r.movePct.map { String(format: "%+.2f%%", $0) } ?? "…")
                                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                                        .foregroundStyle((r.movePct ?? 0) >= 0 ? Color.green : Color.red)
                                    if let right = r.callRightSoFar {
                                        Image(systemName: right ? "checkmark.circle.fill" : "xmark.circle.fill")
                                            .font(.system(size: 11))
                                            .foregroundStyle(right ? Color.green : Color.red)
                                    }
                                    Spacer()
                                    Button {
                                        model.deletePaperTrade(id: r.trade.id)
                                    } label: {
                                        Image(systemName: "xmark.circle").font(.system(size: 10))
                                    }
                                    .buttonStyle(.plain).foregroundStyle(.tertiary)
                                }
                                if let why = state.reasonings[r.trade.id.uuidString] {
                                    Text(why)
                                        .font(.system(size: 10.5)).foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                }

                Text("the agent cannot know the future — nothing can. It makes disciplined, signal-based calls on paper and keeps this scorecard. Trust the record when it earns it, in months not days; it never touches real money.")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
