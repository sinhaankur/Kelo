import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    @Published var portfolio = Portfolio.load()
    @Published var quotes: [String: Quote] = [:]
    @Published var optionQuotes: [String: OptionsService.OptionQuote] = [:]
    @Published var lastRefresh: Date? = nil
    @Published var refreshing = false

    private var timer: Timer?

    func start() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func refresh() {
        portfolio = Portfolio.load() // re-read so edits to the JSON show up
        let symbols = portfolio.holdings.map(\.symbol) + portfolio.calls.map(\.underlying)
        guard !symbols.isEmpty else { return }
        refreshing = true
        let callUnderlyings = portfolio.calls.map(\.underlying)
        Task {
            async let stocks = QuoteService.fetchAll(symbols: symbols)
            async let chains = OptionsService.fetchAll(underlyings: callUnderlyings)
            let (q, oq) = await (stocks, chains)
            await MainActor.run {
                self.quotes = q
                self.optionQuotes = oq
                self.lastRefresh = Date()
                self.refreshing = false
            }
        }
    }

    /// Market value of a call position: CBOE mark × 100 × contracts; falls
    /// back to intrinsic (from spot) when the chain has no quote.
    func callValue(_ c: CallPosition) -> Double? {
        if let oq = optionQuotes[OptionsService.occSymbol(for: c)], oq.mark > 0 {
            return oq.mark * 100 * Double(c.contracts)
        }
        return (quotes[c.underlying]?.price).map { c.intrinsic(at: $0) }
    }

    // Totals
    var totalValue: Double {
        portfolio.holdings.reduce(0) { acc, h in
            acc + (quotes[h.symbol]?.price ?? 0) * h.quantity
        } + portfolio.calls.reduce(0) { acc, c in
            acc + (callValue(c) ?? 0)
        }
    }
    var totalCost: Double {
        portfolio.holdings.reduce(0) { $0 + $1.costBasis * $1.quantity }
            + portfolio.calls.reduce(0) { $0 + $1.premiumPaid }
    }
}

struct ContentView: View {
    @StateObject private var model = AppModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    holdingsSection
                    if !model.portfolio.calls.isEmpty { callsSection }
                    footer
                }
                .padding(16)
            }
        }
        .frame(minWidth: 680, minHeight: 460)
        .onAppear { model.start() }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Pulse").font(.system(size: 18, weight: .semibold))
                Text("local portfolio · quotes may be delayed")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            let pl = model.totalValue - model.totalCost
            VStack(alignment: .trailing, spacing: 2) {
                Text(usd(model.totalValue)).font(.system(size: 18, weight: .semibold, design: .monospaced))
                Text("\(pl >= 0 ? "▲" : "▼") \(usd(abs(pl))) all-time")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(pl >= 0 ? .green : .red)
            }
            Button {
                model.refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .rotationEffect(.degrees(model.refreshing ? 360 : 0))
                    .animation(model.refreshing ? .linear(duration: 1).repeatForever(autoreverses: false) : .default,
                               value: model.refreshing)
            }
            .help("Refresh quotes")
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }

    private var holdingsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("HOLDINGS")
            Grid(alignment: .trailing, horizontalSpacing: 14, verticalSpacing: 6) {
                GridRow {
                    gridHead("SYMBOL", leading: true); gridHead("QTY"); gridHead("PRICE")
                    gridHead("DAY"); gridHead("VALUE"); gridHead("P/L")
                }
                ForEach(model.portfolio.holdings) { h in
                    let q = model.quotes[h.symbol]
                    let value = (q?.price ?? 0) * h.quantity
                    let pl = value - h.costBasis * h.quantity
                    GridRow {
                        Text(h.symbol).font(.system(.body, design: .monospaced)).gridColumnAlignment(.leading)
                        Text(num(h.quantity)).mono()
                        Text(q.map { usd($0.price) } ?? "…").mono()
                        Text(q.map { pct($0.dayChangePct) } ?? "—").mono()
                            .foregroundStyle((q?.dayChangePct ?? 0) >= 0 ? .green : .red)
                        Text(q != nil ? usd(value) : "—").mono()
                        Text(q != nil ? usd(pl) : "—").mono()
                            .foregroundStyle(pl >= 0 ? .green : .red)
                    }
                }
            }
        }
    }

    private var callsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("CALLS")
            Grid(alignment: .trailing, horizontalSpacing: 14, verticalSpacing: 6) {
                GridRow {
                    gridHead("UNDERLYING", leading: true); gridHead("STRIKE"); gridHead("EXPIRY")
                    gridHead("DTE"); gridHead("SPOT"); gridHead("MARKET"); gridHead("TIME VAL"); gridHead("P/L")
                }
                ForEach(model.portfolio.calls) { c in
                    let q = model.quotes[c.underlying]
                    let intrinsic = q.map { c.intrinsic(at: $0.price) }
                    let market = model.callValue(c)
                    let hasChainQuote = model.optionQuotes[OptionsService.occSymbol(for: c)]?.mark ?? 0 > 0
                    GridRow {
                        Text("\(c.underlying) ×\(c.contracts)").font(.system(.body, design: .monospaced)).gridColumnAlignment(.leading)
                        Text(usd(c.strike)).mono()
                        Text(c.expiry).mono()
                        Text(c.daysToExpiry.map { "\($0)d" } ?? "—").mono()
                            .foregroundStyle((c.daysToExpiry ?? 99) < 14 ? .orange : .secondary)
                        Text(q.map { usd($0.price) } ?? "…").mono()
                        Text(market.map(usd) ?? "—").mono()
                            .foregroundStyle(hasChainQuote ? .primary : .secondary)
                        Text((market != nil && intrinsic != nil && hasChainQuote)
                             ? usd(market! - intrinsic!) : "—").mono()
                            .foregroundStyle(.secondary)
                        Text(market.map { usd($0 - c.premiumPaid) } ?? "—").mono()
                            .foregroundStyle((market ?? 0) - c.premiumPaid >= 0 ? .green : .red)
                    }
                }
            }
            Text("Options: CBOE delayed quotes (mark = bid/ask mid). Grey market value = no chain quote, showing intrinsic.")
                .font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
        }
    }

    private var footer: some View {
        HStack {
            Text("portfolio.json → \(Portfolio.fileURL.path)")
            Spacer()
            if let t = model.lastRefresh {
                Text("updated \(t.formatted(date: .omitted, time: .standard))")
            }
        }
        .font(.system(size: 10, design: .monospaced))
        .foregroundStyle(.secondary)
    }

    private func sectionLabel(_ s: String) -> some View {
        Text(s).font(.system(size: 10, weight: .semibold, design: .monospaced))
            .tracking(2).foregroundStyle(.secondary)
    }
    private func gridHead(_ s: String, leading: Bool = false) -> some View {
        Text(s).font(.system(size: 9, weight: .medium, design: .monospaced))
            .tracking(1).foregroundStyle(.tertiary)
            .gridColumnAlignment(leading ? .leading : .trailing)
    }
}

private extension Text {
    func mono() -> Text { font(.system(.body, design: .monospaced)) }
}

func usd(_ v: Double) -> String {
    let f = NumberFormatter()
    f.numberStyle = .currency; f.currencyCode = "USD"
    f.maximumFractionDigits = v >= 1000 ? 0 : 2
    return f.string(from: v as NSNumber) ?? "$\(v)"
}
func num(_ v: Double) -> String {
    v == v.rounded() ? String(Int(v)) : String(format: "%.4g", v)
}
func pct(_ v: Double) -> String { String(format: "%+.2f%%", v) }
