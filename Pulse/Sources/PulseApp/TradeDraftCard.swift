import SwiftUI
import AppKit
import PulseKit

/// Draft a buy or sell against the funds actually available — share math,
/// post-trade concentration, cash remaining, realized P/L — and copy the
/// summary for your broker. Pulse NEVER places orders: drafting is the whole
/// feature, execution stays with you, in your brokerage, behind its own
/// confirmations.
struct TradeDraftCard: View {
    @ObservedObject var model: AppModel
    @State private var isBuy = true
    @State private var symbol = ""
    @State private var amountText = ""
    @State private var draft: Draft? = nil
    @State private var status = ""
    @State private var working = false

    struct Draft {
        let side: String
        let symbol: String
        let price: Double        // display currency (what the UI shows)
        let nativePrice: Double  // listing currency (what the paper ledger stores)
        let amount: Double
        let shares: Double
        let notes: [(ok: Bool, text: String)]
        let summary: String
    }

    var body: some View {
        Card(title: "TRADE DRAFT", trailing: "drafts only — orders happen in your broker") {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Picker("", selection: $isBuy) {
                        Text("Buy").tag(true)
                        Text("Sell").tag(false)
                    }
                    .pickerStyle(.segmented).frame(width: 110).labelsHidden()
                    TextField("symbol", text: $symbol)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12, design: .monospaced))
                        .frame(width: 90)
                    TextField("amount USD", text: $amountText)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12, design: .monospaced))
                        .frame(width: 100)
                    Button(working ? "Drafting…" : "Draft") { runDraft() }
                        .disabled(working || symbol.trimmingCharacters(in: .whitespaces).isEmpty
                                  || Double(amountText) == nil)
                    if let cash = model.config.cashAvailable {
                        Text("cash available \(usd(cash))")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    } else {
                        Text("set cashAvailable in config.json for affordability checks")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                }
                if !status.isEmpty {
                    Text(status).font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.orange)
                }
                if let d = draft {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("\(d.side) ~\(String(format: "%.4f", d.shares)) \(d.symbol) ≈ \(usd(d.amount)) @ \(usd(d.price))")
                            .font(.system(size: 12.5, weight: .semibold, design: .monospaced))
                        ForEach(d.notes.indices, id: \.self) { i in
                            HStack(spacing: 7) {
                                Image(systemName: d.notes[i].ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                    .font(.system(size: 11))
                                    .foregroundStyle(d.notes[i].ok ? Color.green : Color.orange)
                                Text(d.notes[i].text).font(.system(size: 11.5)).foregroundStyle(.secondary)
                            }
                        }
                        HStack(spacing: 10) {
                            Button("→ Wealthsimple") {
                                let ticket = AgentService.orderTicket(
                                    side: d.side, yahooSymbol: d.symbol,
                                    shares: d.shares, approxAmount: d.amount,
                                    lastPrice: d.nativePrice,
                                    currency: model.quotes[d.symbol]?.currency ?? "USD",
                                    reasoning: nil)
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(ticket, forType: .string)
                                if let url = URL(string: "https://my.wealthsimple.com/app/trade") {
                                    NSWorkspace.shared.open(url)
                                }
                                status = "order ticket copied — paste the symbol in Wealthsimple; you place and confirm it there"
                            }
                            .help("Copies the ready order ticket and opens Wealthsimple — the final click is yours")
                            Button("Copy order summary") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(d.summary, forType: .string)
                            }
                            Button("Log paper trade") {
                                model.logPaperTrade(PaperTrade(
                                    date: isoDateString(Date()), side: d.side,
                                    symbol: d.symbol, shares: d.shares,
                                    entryPrice: d.nativePrice, amount: d.amount))
                                status = "logged as a paper trade — scored in PAPER TRADES below, no real order placed"
                                draft = nil
                            }
                            Text("quote is delayed — confirm price in the broker before placing")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))
                }
            }
        }
    }

    private func runDraft() {
        let sym = symbol.trimmingCharacters(in: .whitespaces).uppercased()
        guard let amount = Double(amountText), amount > 0 else { return }
        working = true; status = ""; draft = nil
        Task {
            var quote = model.quotes[sym]
            if quote == nil { quote = await QuoteService.fetch(symbol: sym) }
            await MainActor.run {
                working = false
                guard let q = quote else {
                    status = "no quote for \(sym) — check the symbol"
                    return
                }
                draft = buildDraft(symbol: sym, quote: q, amount: amount)
            }
        }
    }

    private func buildDraft(symbol: String, quote: Quote, amount: Double) -> Draft {
        // Amount is entered in the display currency; convert the quote so the
        // share math and the checks all live in the same currency.
        let price = quote.price * model.fx(quote.currency)
        let shares = amount / price
        var notes: [(Bool, String)] = []
        let holding = model.portfolio.holdings.first { $0.symbol == symbol }

        if isBuy {
            if let cash = model.config.cashAvailable {
                let after = cash - amount
                notes.append((after >= 0,
                              after >= 0 ? "cash after: \(usd(after)) of \(usd(cash))"
                                         : "exceeds available cash by \(usd(-after))"))
            }
            let total = model.totalValue
            if total > 0 {
                let current = holding.map { model.holdingValue($0) } ?? 0
                let concAfter = (current + amount) / (total + amount) * 100
                notes.append((concAfter <= 40,
                              "post-trade concentration: \(symbol) would be \(Int(concAfter))% of the portfolio\(concAfter > 40 ? " — heavy" : "")"))
            }
        } else {
            if let h = holding {
                let heldValue = model.holdingValue(h)
                let ok = shares <= h.quantity + 1e-9
                notes.append((ok, ok
                    ? "selling \(String(format: "%.4f", shares)) of \(num(h.quantity)) held (\(usd(heldValue)) position)"
                    : "you hold only \(num(h.quantity)) shares (\(usd(heldValue))) — can't sell \(String(format: "%.4f", shares))"))
                let costPerShare = h.costBasis * model.fx(h.currency)
                let realized = (price - costPerShare) * min(shares, h.quantity)
                notes.append((realized >= 0,
                              "realized P/L vs cost \(usd(costPerShare)): \(usd(realized))"))
            } else {
                // Not held → a SHORT call, first-class on paper: log it and
                // Pulse scores it (right if the price falls). Blunt truth
                // attached: real shorting pays borrow fees and has unlimited
                // downside — paper is where the thesis gets proven.
                notes.append((true, "you don't hold \(symbol) — this is a SHORT call (paper): scored as right if the price falls from \(usd(price))"))
                notes.append((false, "real shorting = borrow fees + unlimited downside + squeeze risk; prove it on paper first"))
            }
        }

        let side = isBuy ? "BUY" : "SELL"
        let stamp = Date().formatted(date: .abbreviated, time: .shortened)
        let summary = """
        DRAFT (not an order) · \(stamp)
        \(side) ~\(String(format: "%.4f", shares)) \(symbol) ≈ \(usd(amount)) @ \(usd(price)) (delayed quote)
        \(notes.map { ($0.0 ? "· " : "! ") + $0.1 }.joined(separator: "\n"))
        Pulse never executes trades — place and confirm this in your broker.
        """
        return Draft(side: side, symbol: symbol, price: price, nativePrice: quote.price,
                     amount: amount, shares: shares, notes: notes, summary: summary)
    }
}
