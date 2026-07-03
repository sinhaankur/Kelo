import SwiftUI
import PulseKit

/// Tap a holding → its outlook: real momentum, 52-week position, volatility,
/// drawdown, current analyst counts, recent news — and an optional local-LLM
/// read framed as scenarios. Deliberately titled "sourced signals, not a
/// forecast": nobody reliably predicts prices, and Pulse won't pretend to.
struct OutlookSheet: View {
    @ObservedObject var model: AppModel
    let symbol: String
    @Environment(\.dismiss) private var dismiss

    @State private var outlook: StockOutlook? = nil
    @State private var lifecycle: [QuoteService.HistoryPoint] = []
    @State private var loading = true
    @State private var llmOutput = ""
    @State private var llmStatus = ""
    @State private var llmRunning = false
    @AppStorage("llmEndpoint") private var endpoint = "http://localhost:11434"
    @AppStorage("llmModel") private var llmModel = "qwen2.5:7b"

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(symbol)
                    .font(.system(size: 20, weight: .semibold, design: .monospaced))
                if let o = outlook {
                    Text(usd(o.price * model.fx(o.currency)))
                        .font(.system(size: 14, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("OUTLOOK — sourced signals, not a forecast")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .tracking(1.5).foregroundStyle(.secondary)
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 15))
                }
                .buttonStyle(.plain).foregroundStyle(.tertiary)
                .keyboardShortcut(.cancelAction)
            }

            if loading {
                Text("fetching real history + analyst data…")
                    .font(.system(size: 11, design: .monospaced)).foregroundStyle(.tertiary)
            } else if let o = outlook {
                // The whole lifecycle — every close since Yahoo has data for
                // the listing, with the user's buy point marked when held.
                if lifecycle.count >= 2, let first = lifecycle.first {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text("LIFECYCLE since \(isoDateString(first.date))")
                                .font(.system(size: 9, weight: .medium, design: .monospaced))
                                .tracking(1).foregroundStyle(.tertiary)
                            Spacer()
                            if model.timelines[symbol] != nil {
                                Text("┊ marks your invested date")
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        LifecycleChart(points: lifecycle,
                                       acquired: model.timelines[symbol]?.acquired)
                            .frame(height: 84)
                    }
                }
                HStack(spacing: 10) {
                    if let r = o.ret30dPct { tile("30-DAY", pctLabel(r), r >= 0 ? .green : .red) }
                    if let r = o.ret1yPct { tile("1-YEAR", pctLabel(r), r >= 0 ? .green : .red) }
                    if let b = o.benchRet1yPct { tile("S&P 1-YEAR", pctLabel(b), .secondary) }
                    if let f = o.pctFromHigh { tile("VS 52W HIGH", pctLabel(f), f > -5 ? .green : .orange) }
                    if let v = o.annualVolPct { tile("VOLATILITY", String(format: "%.0f%%/y", v), v > 60 ? .orange : .secondary) }
                    if let d = o.maxDrawdown1yPct { tile("MAX FALL 1Y", pctLabel(d), .orange) }
                    Spacer()
                }
                HStack(spacing: 10) {
                    if let m = o.vsMa50Pct { tile("VS 50-DAY AVG", pctLabel(m), m >= 0 ? .green : .orange) }
                    if let m = o.vsMa200Pct { tile("VS 200-DAY AVG", pctLabel(m), m >= 0 ? .green : .orange) }
                    if let r = o.rsi14 {
                        tile("RSI 14", String(format: "%.0f", r),
                             r > 70 ? .orange : r < 30 ? .cyan : .secondary)
                    }
                    if let dy = o.ttmDividendYieldPct {
                        // High yield + big drawdown = yield trap territory.
                        tile("DIV YIELD TTM", String(format: "%.2f%%", dy),
                             dy > 6 ? .orange : .green)
                    }
                    Spacer()
                }
                // Why the company itself is doing badly (or well) — the
                // business facts a price chart can't show.
                if let f = o.fundamentals, !f.healthNotes.isEmpty {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("WHY THE BUSINESS \(businessDirection(f)) — fundamentals (Finnhub)")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .tracking(1).foregroundStyle(.tertiary)
                        ForEach(f.healthNotes.indices, id: \.self) { i in
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Image(systemName: noteIsBad(f.healthNotes[i]) ? "arrow.down.right.circle" : "arrow.up.right.circle")
                                    .font(.system(size: 10))
                                    .foregroundStyle(noteIsBad(f.healthNotes[i]) ? Color.red : Color.green)
                                Text(f.healthNotes[i])
                                    .font(.system(size: 11)).foregroundStyle(.secondary)
                            }
                        }
                        if let industry = f.industry {
                            Text("industry: \(industry)")
                                .font(.system(size: 10, design: .monospaced)).foregroundStyle(.tertiary)
                        }
                    }
                } else if o.fundamentals == nil, model.config.finnhubApiKey != nil {
                    Text("no company fundamentals for this ticker (ETFs, crypto and some listings have none) — the chart signals above are the read")
                        .font(.system(size: 10, design: .monospaced)).foregroundStyle(.tertiary)
                }
                if let r = o.recommendations, r.total > 0 {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("ANALYSTS (\(r.period) · Finnhub · \(r.total) covering)")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .tracking(1).foregroundStyle(.tertiary)
                        GeometryReader { geo in
                            HStack(spacing: 2) {
                                seg(r.bullish, r.total, .green, geo)
                                seg(r.hold, r.total, .gray, geo)
                                seg(r.bearish, r.total, .red, geo)
                            }
                        }
                        .frame(height: 10)
                        Text("\(r.bullish) buy · \(r.hold) hold · \(r.bearish) sell — counts of opinions, not truth")
                            .font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                    }
                }
                if !o.news.isEmpty {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(o.news.indices, id: \.self) { i in
                            Text("· \(o.news[i].title)  [\(o.news[i].source)]")
                                .font(.system(size: 10.5)).foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                HStack(spacing: 8) {
                    Button(llmRunning ? "Reading…"
                           : model.config.usesAnthropicCloud ? "Model read (Anthropic cloud)"
                           : "Local model read") { runLlm(o) }
                        .disabled(llmRunning)
                    Text(model.config.usesAnthropicCloud
                         ? "⚠ cloud model configured — this context leaves the machine"
                         : "scenarios from the numbers above — the future is not knowable; test your read as a paper trade in Trade")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(model.config.usesAnthropicCloud
                                         ? AnyShapeStyle(.orange) : AnyShapeStyle(.tertiary))
                }
                if !llmStatus.isEmpty {
                    Text(llmStatus).font(.system(size: 10, design: .monospaced)).foregroundStyle(.orange)
                }
                if !llmOutput.isEmpty {
                    ScrollView {
                        Text(llmOutput).font(.system(size: 12)).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 240)
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06)))
                }
            } else {
                Text("couldn't fetch history for \(symbol) — possibly delisted or an invalid ticker")
                    .font(.system(size: 11, design: .monospaced)).foregroundStyle(.orange)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(width: 720, height: 580)
        .task {
            async let outlookTask = OutlookService.fetch(symbol: symbol,
                                                         finnhubKey: model.config.finnhubApiKey)
            async let lifeTask = QuoteService.fetchHistory(symbol: symbol, range: "max")
            outlook = await outlookTask
            var life = await lifeTask
            if life.count > 300 {
                let stride = Double(life.count - 1) / 299.0
                life = (0..<300).map { life[Int((Double($0) * stride).rounded())] }
            }
            lifecycle = life
            loading = false
        }
    }

    private func runLlm(_ o: StockOutlook) {
        llmRunning = true; llmOutput = ""; llmStatus = ""
        let sentiment = model.sentiment?.summary ?? "(not fetched)"
        let holding = model.portfolio.holdings.first { $0.symbol == symbol }
        let position = holding.map {
            "user holds \(num($0.quantity)) at cost \(usd($0.costBasis))"
        } ?? "user does not hold this"
        let recs = o.recommendations.map {
            "analysts (\($0.period)): \($0.bullish) buy, \($0.hold) hold, \($0.bearish) sell of \($0.total)"
        } ?? "no analyst data"
        let fundamentals = o.fundamentals?.healthNotes.joined(separator: "; ") ?? "no company fundamentals"
        let system = """
        You are a careful market analysis assistant running fully locally. You CANNOT predict \
        prices and must say so if asked. Using ONLY the provided real numbers, write: \
        1) MOMENTUM — what the 30d/1y/52-week/volatility numbers say happened. \
        2) THE STREET — what the analyst counts currently are (opinions, not truth). \
        3) SCENARIOS — what would need to be true for a bull case and a bear case over 6–12 months, \
        grounded in the numbers and headlines given. No price targets of your own. \
        4) RISKS — including volatility and drawdown shown. \
        End with exactly: "The future is not knowable. Not financial advice."
        """
        let user = """
        SYMBOL: \(o.symbol) at \(usd(o.price * model.fx(o.currency))) — \(position)
        30d \(o.ret30dPct.map(pctLabel) ?? "?") · 1y \(o.ret1yPct.map(pctLabel) ?? "?") · S&P 1y \(o.benchRet1yPct.map(pctLabel) ?? "?")
        vs 52w high \(o.pctFromHigh.map(pctLabel) ?? "?") · vs 50dma \(o.vsMa50Pct.map(pctLabel) ?? "?") · vs 200dma \(o.vsMa200Pct.map(pctLabel) ?? "?") · RSI14 \(o.rsi14.map { String(format: "%.0f", $0) } ?? "?")
        realized vol \(o.annualVolPct.map { String(format: "%.0f%%/y", $0) } ?? "?") · max fall 1y \(o.maxDrawdown1yPct.map(pctLabel) ?? "?") · TTM dividend yield \(o.ttmDividendYieldPct.map { String(format: "%.2f%%", $0) } ?? "none paid")
        \(recs)
        COMPANY FUNDAMENTALS: \(fundamentals)
        GLOBAL SENTIMENT: \(sentiment)
        NEWS:
        \(o.news.map { "- [\($0.source)] \($0.title)" }.joined(separator: "\n"))
        """
        Task {
            do {
                let text = try await LlmService.analyzeRouted(system: system, user: user,
                                                              config: model.config,
                                                              ollamaEndpoint: endpoint,
                                                              ollamaModel: llmModel)
                await MainActor.run { llmOutput = text; llmRunning = false }
            } catch {
                await MainActor.run {
                    llmStatus = "⚠ \(error.localizedDescription)"
                    llmRunning = false
                }
            }
        }
    }

    private func pctLabel(_ v: Double) -> String { String(format: "%+.1f%%", v) }

    private func businessDirection(_ f: StockOutlook.Fundamentals) -> String {
        let bad = f.healthNotes.filter(noteIsBad).count
        return bad > f.healthNotes.count - bad ? "IS STRUGGLING" : "LOOKS"
    }

    private func noteIsBad(_ note: String) -> Bool {
        ["unprofitable", "shrinking", "heavy debt", "priced for perfection"]
            .contains { note.hasPrefix($0) }
    }

    private func tile(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 8.5, weight: .medium, design: .monospaced))
                .tracking(1).foregroundStyle(.tertiary)
            Text(value).font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(color)
        }
        .padding(.horizontal, 9).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
    }

    private func seg(_ count: Int, _ total: Int, _ color: Color, _ geo: GeometryProxy) -> some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(color.opacity(0.8))
            .frame(width: max(0, geo.size.width * CGFloat(count) / CGFloat(max(1, total))))
    }
}

/// Full listed history, log-friendly single line with the user's invested
/// date as a dashed vertical marker.
private struct LifecycleChart: View {
    let points: [QuoteService.HistoryPoint]
    let acquired: Date?

    var body: some View {
        GeometryReader { geo in
            let closes = points.map(\.close)
            if let lo = closes.min(), let hi = closes.max(), hi > lo,
               let firstDate = points.first?.date, let lastDate = points.last?.date,
               lastDate > firstDate {
                let up = closes.last! >= closes.first!
                let color: Color = up ? .green : .red
                let span = lastDate.timeIntervalSince(firstDate)
                let pts: [CGPoint] = points.map { p in
                    CGPoint(x: geo.size.width * CGFloat(p.date.timeIntervalSince(firstDate) / span),
                            y: geo.size.height * (1 - CGFloat((p.close - lo) / (hi - lo))))
                }
                ZStack {
                    Path { p in
                        p.move(to: CGPoint(x: pts[0].x, y: geo.size.height))
                        for pt in pts { p.addLine(to: pt) }
                        p.addLine(to: CGPoint(x: pts.last!.x, y: geo.size.height))
                        p.closeSubpath()
                    }
                    .fill(LinearGradient(colors: [color.opacity(0.16), .clear],
                                         startPoint: .top, endPoint: .bottom))
                    Path { p in
                        p.move(to: pts[0])
                        for pt in pts.dropFirst() { p.addLine(to: pt) }
                    }
                    .stroke(color.opacity(0.9), lineWidth: 1.4)
                    if let acquired, acquired >= firstDate, acquired <= lastDate {
                        let x = geo.size.width * CGFloat(acquired.timeIntervalSince(firstDate) / span)
                        Path { p in
                            p.move(to: CGPoint(x: x, y: 0))
                            p.addLine(to: CGPoint(x: x, y: geo.size.height))
                        }
                        .stroke(Color.secondary.opacity(0.7),
                                style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    }
                }
            }
        }
    }
}
