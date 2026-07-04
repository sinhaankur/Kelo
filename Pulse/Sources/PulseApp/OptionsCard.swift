import SwiftUI
import PulseKit

/// Learn options from zero, then test-run one risk-free. Left: the lessons,
/// plain-language, expandable. Right: an honest calculator — pick a stock,
/// a strike, a premium, and see exactly what it costs, breaks even at, and
/// loses, then log it as a paper trade scored over time. No real money, no
/// pressure to trade.
struct OptionsLearnCard: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Card(title: "OPTIONS — LEARN FIRST", trailing: "you've never done this — start here, no money involved") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Read these in order. Options can be a tool or a trap; the difference is understanding them before you touch one.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(OptionsEducation.lessons.indices, id: \.self) { i in
                    let lesson = OptionsEducation.lessons[i]
                    DisclosureGroup {
                        Text(lesson.body)
                            .font(.system(size: 11.5)).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 4).padding(.leading, 2)
                    } label: {
                        HStack(spacing: 7) {
                            Text("\(i + 1)")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(.tertiary).frame(width: 14)
                            Text(lesson.title)
                                .font(.system(size: 12, weight: .medium))
                        }
                    }
                    .font(.system(size: 12))
                }
            }
        }
    }
}

/// The honest options calculator + risk-free test run.
struct OptionsCalculatorCard: View {
    @ObservedObject var model: AppModel
    @State private var symbol = ""
    @State private var kind: OptionScenario.Kind = .call
    @State private var strikeText = ""
    @State private var premiumText = "2.00"
    @State private var daysText = "30"
    @State private var spot: Double? = nil
    @State private var currency = "USD"
    @State private var loading = false
    @State private var status = ""

    private var scenario: OptionScenario? {
        guard let spot, let strike = Double(strikeText), let premium = Double(premiumText),
              let days = Int(daysText), strike > 0, premium > 0 else { return nil }
        return OptionScenario(kind: kind, spot: spot, strike: strike, premium: premium,
                              daysToExpiry: days, contracts: 1)
    }

    var body: some View {
        Card(title: "OPTIONS CALCULATOR — RISK-FREE TEST RUN", trailing: "see the real math before you ever risk a cent") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Picker("", selection: $kind) {
                        Text("Call (bet up)").tag(OptionScenario.Kind.call)
                        Text("Put (bet down)").tag(OptionScenario.Kind.put)
                    }.pickerStyle(.segmented).frame(width: 200).labelsHidden()
                    TextField("stock symbol", text: $symbol)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12, design: .monospaced)).frame(width: 120)
                        .onSubmit(fetchSpot)
                    Button(loading ? "…" : "Load price") { fetchSpot() }
                        .disabled(loading || symbol.trimmingCharacters(in: .whitespaces).isEmpty)
                    if let spot { Text("at \(usd(spot)) \(currency)")
                        .font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary) }
                    Spacer()
                }
                if spot != nil {
                    HStack(spacing: 8) {
                        labeledField("Strike", $strikeText, "the price you lock in")
                        labeledField("Premium", $premiumText, "cost per share")
                        labeledField("Days to expiry", $daysText, "the deadline")
                    }
                }

                if let s = scenario {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 14) {
                            metric("YOU PAY", usd(s.costTotal), .primary)
                            metric("BREAKEVEN", usd(s.breakeven), .orange)
                            metric("NEEDS TO MOVE", String(format: "%+.1f%%", s.moveToBreakevenPct),
                                   abs(s.moveToBreakevenPct) > 10 ? .red : .orange)
                            metric("MAX LOSS", usd(s.maxLoss), .red)
                            Spacer()
                        }
                        Text(s.honestRead)
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 8) {
                            Button("Log as paper trade") { logPaper(s) }
                            Text("scored over time in Trade — find out if your options instinct works, risk-free")
                                .font(.system(size: 10, design: .monospaced)).foregroundStyle(.tertiary)
                        }
                    }
                    .padding(11)
                    .background(RoundedRectangle(cornerRadius: 9).fill(Color.primary.opacity(0.04)))
                }
                if !status.isEmpty {
                    Text(status).font(.system(size: 10.5, design: .monospaced)).foregroundStyle(.green)
                }
            }
        }
    }

    private func fetchSpot() {
        let sym = symbol.trimmingCharacters(in: .whitespaces).uppercased()
        guard !sym.isEmpty else { return }
        loading = true; status = ""
        Task {
            var q = model.quotes[sym]
            if q == nil { q = await QuoteService.fetch(symbol: sym) }
            await MainActor.run {
                loading = false
                if let q {
                    spot = q.price; currency = q.currency
                    if strikeText.isEmpty { strikeText = String(format: "%.2f", q.price) }
                } else {
                    status = "no quote for \(sym)"
                }
            }
        }
    }

    private func logPaper(_ s: OptionScenario) {
        // Record the option as a paper trade on the underlying (BUY call ≈
        // bullish, PUT ≈ bearish) so the direction gets scored. The premium
        // math above already taught the real cost.
        let side = s.kind == .call ? "BUY" : "SELL"
        model.logPaperTrade(PaperTrade(
            date: isoDateString(Date()), side: side,
            symbol: symbol.trimmingCharacters(in: .whitespaces).uppercased(),
            shares: 0, entryPrice: s.spot, amount: s.costTotal,
            source: "options-lesson"))
        status = "logged — see it scored in Trade. (This tracks the direction; the premium/theta lesson above is the real cost of a live option.)"
    }

    private func labeledField(_ label: String, _ text: Binding<String>, _ hint: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 8.5, weight: .medium, design: .monospaced))
                .tracking(1).foregroundStyle(.tertiary)
            TextField(hint, text: text)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12, design: .monospaced)).frame(width: 110)
        }
    }

    private func metric(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 8.5, weight: .medium, design: .monospaced))
                .tracking(1).foregroundStyle(.tertiary)
            Text(value).font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundStyle(color)
        }
    }
}
