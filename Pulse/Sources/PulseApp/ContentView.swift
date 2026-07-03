import SwiftUI
import UniformTypeIdentifiers
import PulseKit

@MainActor
final class AppModel: ObservableObject {
    @Published var portfolio = Portfolio.load()
    @Published var quotes: [String: Quote] = [:]
    @Published var optionQuotes: [String: OptionsService.OptionQuote] = [:]
    @Published var timelines: [String: PositionTimeline] = [:]
    @Published var portfolioHistory: PortfolioHistory? = nil
    @Published var sentiment: GlobalSentiment? = nil
    @Published var holdingsNews: [String: [GlobalSentiment.Headline]] = [:]
    @Published var paperTrades: [PaperTrade] = []
    @Published var paperReviews: [PaperReview] = []
    @Published var snapshots: [DailySnapshot] = []
    @Published var lastRefresh: Date? = nil
    @Published var refreshing = false
    /// Minute tick — re-evaluates the auto theme even when nothing else moves.
    @Published var tick = Date()

    let config = AppConfig.load()
    private var timer: Timer?
    private var timelineSignature = ""
    private var lastSentimentFetch: Date? = nil
    private var benchmarkHistory: [QuoteService.HistoryPoint] = []

    func start() {
        guard timer == nil else { return }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick = Date()
                self?.refresh()
            }
        }
    }

    func refresh() {
        portfolio = Portfolio.load() // re-read so edits to the JSON show up
        paperTrades = PaperLedger.load()
        snapshots = SnapshotStore.load()
        // Paper-trade symbols get quotes too, even when not held for real.
        let symbols = portfolio.holdings.map(\.symbol) + portfolio.calls.map(\.underlying)
            + paperTrades.map(\.symbol)
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
                self.recordSnapshot()
                self.recomputePaperReviews()
            }
            await self.refreshTimelines(quotes: q)
        }
        refreshSentiment()
    }

    /// One recorded value per day — only when every holding actually has a
    /// quote, so a partial fetch never poisons the record.
    private func recordSnapshot() {
        guard !portfolio.holdings.isEmpty,
              portfolio.holdings.allSatisfy({ quotes[$0.symbol] != nil }) else { return }
        let holdingsValue = portfolio.holdings.reduce(0.0) { $0 + holdingValue($1) }
        let optionsValue = portfolio.calls.reduce(0.0) { $0 + (callValue($1) ?? 0) }
        snapshots = SnapshotStore.record(holdings: holdingsValue, options: optionsValue,
                                         cost: totalCost)
    }

    private func recomputePaperReviews() {
        paperReviews = PaperLedger.review(paperTrades, quotes: quotes,
                                          benchmark: benchmarkHistory)
    }

    func logPaperTrade(_ trade: PaperTrade) {
        PaperLedger.append(trade)
        refresh() // pick up the new symbol's quote + rescore
    }

    func deletePaperTrade(id: UUID) {
        PaperLedger.remove(id: id)
        paperTrades = PaperLedger.load()
        recomputePaperReviews()
    }

    /// Timelines need 10y of history per symbol — fetch only when the
    /// positions themselves change, not on every 60 s quote tick.
    private func refreshTimelines(quotes: [String: Quote]) async {
        let sig = portfolio.holdings
            .map { "\($0.symbol)|\($0.costBasis)|\($0.acquired ?? "")" }
            .joined(separator: ",")
        guard sig != timelineSignature else { return }
        let analysis = await TimelineService.analyze(holdings: portfolio.holdings, quotes: quotes)
        self.timelines = analysis.timelines
        self.portfolioHistory = analysis.history
        self.benchmarkHistory = analysis.benchmark
        self.timelineSignature = sig
        self.recomputePaperReviews()
    }

    /// Sentiment + per-holding news move slowly — refetch at most every 5 min.
    func refreshSentiment() {
        if let t = lastSentimentFetch, Date().timeIntervalSince(t) < 300 { return }
        lastSentimentFetch = Date()
        let key = config.finnhubApiKey
        // Top positions only — a 60-holding import must not fire 60 news
        // calls per cycle into Finnhub's 60/min free tier.
        let holdingSymbols = Array(sortedHoldings.prefix(8).map(\.symbol))
        Task {
            async let s = SentimentService.fetch(finnhubKey: key)
            async let news = SentimentService.holdingsNews(symbols: holdingSymbols, key: key)
            let (sentiment, holdingsNews) = await (s, news)
            await MainActor.run {
                self.sentiment = sentiment
                self.holdingsNews = holdingsNews
            }
        }
    }

    func importCsv(from url: URL) -> String {
        do {
            let result = try CsvImporter.importFile(at: url)
            if result.imported.isEmpty {
                return "no positions found — need symbol + quantity + cost columns"
            }
            timelineSignature = "" // positions changed; re-detect timelines
            refresh()
            let skipped = result.skippedRows > 0 ? " (\(result.skippedRows) rows skipped)" : ""
            return "imported \(result.imported.count) positions\(skipped)"
        } catch {
            return "import failed: \(error.localizedDescription)"
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

    func holdingValue(_ h: Holding) -> Double { (quotes[h.symbol]?.price ?? 0) * h.quantity }

    /// Display order: biggest position first (cost basis until quotes land).
    var sortedHoldings: [Holding] {
        portfolio.holdings.sorted {
            let a = quotes[$0.symbol] != nil ? holdingValue($0) : $0.costBasis * $0.quantity
            let b = quotes[$1.symbol] != nil ? holdingValue($1) : $1.costBasis * $1.quantity
            return a > b
        }
    }

    var totalValue: Double {
        portfolio.holdings.reduce(0) { $0 + holdingValue($1) }
            + portfolio.calls.reduce(0) { $0 + (callValue($1) ?? 0) }
    }
    var totalCost: Double {
        portfolio.holdings.reduce(0) { $0 + $1.costBasis * $1.quantity }
            + portfolio.calls.reduce(0) { $0 + $1.premiumPaid }
    }
    /// Today's move across stock/crypto holdings (options excluded — no
    /// previous-day option marks yet; labeled in the UI).
    var dayPL: Double {
        portfolio.holdings.reduce(0) { acc, h in
            acc + (quotes[h.symbol].map { $0.dayChange * h.quantity } ?? 0)
        }
    }
}

// MARK: - Root

// IA: one subject per section. Overview = my account at a glance;
// Market = everything external (sentiment, world gauges, news);
// Positions = per-holding depth; Analysis = all judgment (deterministic
// flags first, local model second); Trade = drafting + paper scoring.
enum AppSection: String, CaseIterable, Identifiable {
    case overview, market, positions, analysis, trade
    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: return "Overview"
        case .market: return "Market"
        case .positions: return "Positions"
        case .analysis: return "Analysis"
        case .trade: return "Trade"
        }
    }
    var icon: String {
        switch self {
        case .overview: return "waveform.path.ecg"
        case .market: return "globe"
        case .positions: return "chart.bar.xaxis"
        case .analysis: return "text.magnifyingglass"
        case .trade: return "arrow.left.arrow.right"
        }
    }
}

struct ContentView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var lock: LockModel
    @AppStorage("themeMode") private var themeModeRaw = ThemeMode.auto.rawValue
    @State private var section: AppSection? = .overview

    var body: some View {
        let isDark = (ThemeMode(rawValue: themeModeRaw) ?? .auto).isDark(at: model.tick)
        LockGate(lock: lock) { lock in
            NavigationSplitView {
                List(selection: $section) {
                    ForEach(AppSection.allCases) { s in
                        Label(s.title, systemImage: s.icon).tag(s)
                    }
                }
                .listStyle(.sidebar)
                .navigationSplitViewColumnWidth(min: 150, ideal: 170, max: 210)
                .safeAreaInset(edge: .bottom) {
                    VStack(spacing: 1) {
                        Text("Pulse v\(PulseInfo.version)")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Text(PulseInfo.tagline)
                            .font(.system(size: 8.5))
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
            } detail: {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        HeaderCard(model: model, lock: lock)
                        switch section ?? .overview {
                        case .overview:
                            // My account in 5 seconds; market detail lives in
                            // Market — only its one-line summary appears here.
                            MarketStrip(model: model)
                            GrowthCard(model: model)
                            AllocationCard(model: model)
                        case .market:
                            SentimentCard(model: model)
                            if model.holdingsNews.isEmpty {
                                Card(title: "HOLDINGS NEWS") {
                                    Text(model.config.finnhubApiKey == nil
                                         ? "add finnhubApiKey to config.json to see company news for your holdings"
                                         : "fetching company news for your top holdings…")
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundStyle(.tertiary)
                                }
                            } else {
                                HoldingsNewsCard(model: model)
                            }
                        case .positions:
                            HoldingsCard(model: model)
                            TimelineCard(model: model)
                            if !model.portfolio.calls.isEmpty { CallsCard(model: model) }
                        case .analysis:
                            StatsCard(model: model)
                            AnalysisCard(app: model)
                        case .trade:
                            TradeDraftCard(model: model)
                            if model.paperTrades.isEmpty {
                                Card(title: "PAPER TRADES") {
                                    Text("no paper trades yet — draft above and press \"Log paper trade\" to start scoring your calls against reality")
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundStyle(.tertiary)
                                }
                            } else {
                                PaperLedgerCard(model: model)
                            }
                        }
                        footer
                    }
                    .padding(14)
                    .frame(maxWidth: 1100, alignment: .leading)
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .preferredColorScheme(isDark ? .dark : .light)
        .frame(minWidth: 900, minHeight: 640)
        .onAppear { model.start() }
    }

    private var footer: some View {
        let holdingSymbols = Set(model.portfolio.holdings.map(\.symbol))
        let quoted = holdingSymbols.filter { model.quotes[$0] != nil }.count
        return HStack {
            Text("portfolio.json · quotes: Yahoo (delayed) · options: CBOE delayed · sentiment: VIX/alternative.me/Finnhub")
            Spacer()
            if quoted < holdingSymbols.count {
                Text("⚠ quotes \(quoted)/\(holdingSymbols.count) — unquoted positions count as $0")
                    .foregroundStyle(.orange)
            }
            if let t = model.lastRefresh {
                Text("updated \(t.formatted(date: .omitted, time: .shortened))")
            }
        }
        .font(.system(size: 10, design: .monospaced))
        .foregroundStyle(.tertiary)
        .padding(.horizontal, 4)
    }
}

// MARK: - Cards

/// One-line market pulse on the Overview — the detail lives in Market.
private struct MarketStrip: View {
    @ObservedObject var model: AppModel
    var body: some View {
        Card(title: "MARKET", trailing: "detail in the Market section") {
            if let s = model.sentiment {
                Text(s.summary)
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(.secondary)
            } else {
                Text("fetching market context…")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

struct Card<Content: View>: View {
    let title: String
    var trailing: String? = nil
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .tracking(2).foregroundStyle(.secondary)
                Spacer()
                if let trailing {
                    Text(trailing)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
            }
            content
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.08)))
    }
}

private struct HeaderCard: View {
    @ObservedObject var model: AppModel
    @ObservedObject var lock: LockModel
    @AppStorage("themeMode") private var themeModeRaw = ThemeMode.auto.rawValue
    var body: some View {
        let allTime = model.totalValue - model.totalCost
        let allTimePct = model.totalCost > 0 ? allTime / model.totalCost * 100 : 0
        let isDark = (ThemeMode(rawValue: themeModeRaw) ?? .auto).isDark(at: model.tick)
        HStack(alignment: .firstTextBaseline, spacing: 24) {
            VStack(alignment: .leading, spacing: 3) {
                Text("PORTFOLIO")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .tracking(2).foregroundStyle(.secondary)
                Text(usd(model.totalValue))
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .contentTransition(.numericText())
            }
            Spacer()
            DeltaStat(label: "TODAY · HOLDINGS", value: model.dayPL)
            DeltaStat(label: "ALL-TIME", value: allTime, pct: allTimePct)
            Button { model.refresh() } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 13, weight: .semibold))
                    .rotationEffect(.degrees(model.refreshing ? 360 : 0))
                    .animation(model.refreshing
                               ? .linear(duration: 1).repeatForever(autoreverses: false)
                               : .default, value: model.refreshing)
            }
            .buttonStyle(.plain)
            .padding(8)
            .background(Circle().fill(Color.primary.opacity(0.07)))
            .help("Refresh quotes")
            Menu {
                Picker("Appearance", selection: $themeModeRaw) {
                    ForEach(ThemeMode.allCases, id: \.rawValue) { m in
                        Text(m.label).tag(m.rawValue)
                    }
                }
            } label: {
                Image(systemName: isDark ? "moon.fill" : "sun.max.fill")
                    .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .padding(8)
            .background(Circle().fill(Color.primary.opacity(0.07)))
            .help("Appearance — auto follows the time of day")
            Button { lock.lock() } label: {
                Image(systemName: "lock.fill").font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.plain)
            .padding(8)
            .background(Circle().fill(Color.primary.opacity(0.07)))
            .help("Lock Pulse (Touch ID to reopen)")
            .contextMenu {
                Toggle("Require unlock on launch", isOn: lock.$lockEnabled)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.08)))
    }
}

private struct DeltaStat: View {
    let label: String
    let value: Double
    var pct: Double? = nil
    var body: some View {
        VStack(alignment: .trailing, spacing: 3) {
            Text(label)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .tracking(1.5).foregroundStyle(.tertiary)
            HStack(spacing: 5) {
                Image(systemName: value >= 0 ? "arrow.up.right" : "arrow.down.right")
                    .font(.system(size: 10, weight: .bold))
                Text(usd(abs(value)))
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                if let pct {
                    Text(String(format: "%+.1f%%", pct))
                        .font(.system(size: 11, design: .monospaced))
                        .opacity(0.75)
                }
            }
            .foregroundStyle(value >= 0 ? Color.green : Color.red)
        }
    }
}

// Palette for allocation + legend — stable per symbol.
private func symbolColor(_ symbol: String, index: Int) -> Color {
    let palette: [Color] = [.cyan, .orange, .purple, .green, .pink, .yellow, .blue, .mint]
    return palette[index % palette.count]
}

private struct AllocationCard: View {
    @ObservedObject var model: AppModel

    /// Top positions by value; everything past 10 groups into OTHER so a
    /// 60-position import stays readable instead of becoming 60 slivers.
    private var entries: [(String, Double, Color)] {
        var out: [(String, Double, Color)] = []
        for (i, h) in model.sortedHoldings.enumerated() {
            out.append((h.symbol, model.holdingValue(h), symbolColor(h.symbol, index: i)))
        }
        let base = model.portfolio.holdings.count
        for (i, c) in model.portfolio.calls.enumerated() {
            out.append(("\(c.underlying) C", model.callValue(c) ?? 0, symbolColor(c.underlying, index: base + i)))
        }
        out = out.filter { $0.1 > 0 }.sorted { $0.1 > $1.1 }
        if out.count > 11 {
            let rest = out[10...]
            out = Array(out.prefix(10))
            out.append(("OTHER ×\(rest.count)", rest.reduce(0) { $0 + $1.1 }, .gray))
        }
        return out
    }

    var body: some View {
        let entries = self.entries
        let total = entries.reduce(0) { $0 + $1.1 }

        Card(title: "ALLOCATION", trailing: entries.contains(where: { $0.0.hasPrefix("OTHER") })
             ? "top 10 shown · rest grouped" : nil) {
            if total <= 0 {
                Text("waiting for quotes…")
                    .font(.system(size: 11, design: .monospaced)).foregroundStyle(.tertiary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    GeometryReader { geo in
                        HStack(spacing: 2) {
                            ForEach(entries.indices, id: \.self) { i in
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(entries[i].2.opacity(0.85))
                                    .frame(width: max(3, geo.size.width * entries[i].1 / total))
                            }
                        }
                    }
                    .frame(height: 14)
                    // Wrapping grid — the legend must never widen the window.
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 118), spacing: 8, alignment: .leading)],
                              alignment: .leading, spacing: 5) {
                        ForEach(entries.indices, id: \.self) { i in
                            HStack(spacing: 5) {
                                Circle().fill(entries[i].2).frame(width: 6, height: 6)
                                Text("\(entries[i].0) \(Int((entries[i].1 / total * 100).rounded()))%")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct HoldingsCard: View {
    @ObservedObject var model: AppModel
    @State private var importStatus = ""
    var body: some View {
        Card(title: "HOLDINGS", trailing: "30-day trend") {
            Grid(alignment: .trailing, horizontalSpacing: 16, verticalSpacing: 10) {
                GridRow {
                    head("SYMBOL", leading: true); head(""); head("QTY"); head("PRICE")
                    head("DAY"); head("VALUE"); head("P/L")
                }
                ForEach(model.sortedHoldings) { h in
                    let q = model.quotes[h.symbol]
                    let value = model.holdingValue(h)
                    let pl = value - h.costBasis * h.quantity
                    GridRow {
                        Text(h.symbol)
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                            .gridColumnAlignment(.leading)
                        Sparkline(closes: q?.closes ?? [])
                            .frame(width: 72, height: 20)
                        Text(num(h.quantity)).cell()
                        Text(q.map { usd($0.price) } ?? "…").cell()
                        DayPill(pct: q?.dayChangePct)
                        Text(q != nil ? usd(value) : "—").cell()
                        Text(q != nil ? usd(pl) : "—").cell()
                            .foregroundStyle(pl >= 0 ? Color.green : Color.red)
                    }
                }
            }
            HStack(spacing: 8) {
                Button("Import CSV…") { importCsv() }
                    .font(.system(size: 11))
                Text(importStatus.isEmpty
                     ? "broker export with symbol / quantity / cost columns — merges into portfolio.json"
                     : importStatus)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
                Spacer()
            }
        }
    }

    private func importCsv() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.commaSeparatedText, .plainText]
        panel.allowsMultipleSelection = false
        panel.message = "Choose a CSV of positions (symbol, quantity, cost, optional date)"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        importStatus = model.importCsv(from: url)
    }

    private func head(_ s: String, leading: Bool = false) -> some View {
        Text(s).font(.system(size: 9, weight: .medium, design: .monospaced))
            .tracking(1).foregroundStyle(.tertiary)
            .gridColumnAlignment(leading ? .leading : .trailing)
    }
}

private struct CallsCard: View {
    @ObservedObject var model: AppModel
    var body: some View {
        Card(title: "CALLS", trailing: "CBOE delayed · mark = bid/ask mid") {
            Grid(alignment: .trailing, horizontalSpacing: 16, verticalSpacing: 10) {
                GridRow {
                    head("POSITION", leading: true); head("STRIKE"); head("EXPIRY"); head("DTE")
                    head("SPOT"); head("MARKET"); head("TIME VAL"); head("P/L")
                }
                ForEach(model.portfolio.calls) { c in
                    let q = model.quotes[c.underlying]
                    let intrinsic = q.map { c.intrinsic(at: $0.price) }
                    let market = model.callValue(c)
                    let hasChainQuote = (model.optionQuotes[OptionsService.occSymbol(for: c)]?.mark ?? 0) > 0
                    GridRow {
                        Text("\(c.underlying) ×\(c.contracts)")
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                            .gridColumnAlignment(.leading)
                        Text(usd(c.strike)).cell()
                        Text(c.expiry).cell()
                        DTEPill(days: c.daysToExpiry)
                        Text(q.map { usd($0.price) } ?? "…").cell()
                        Text(market.map(usd) ?? "—").cell()
                            .foregroundStyle(hasChainQuote ? Color.primary : Color.secondary)
                        Text((market != nil && intrinsic != nil && hasChainQuote)
                             ? usd(market! - intrinsic!) : "—").cell()
                            .foregroundStyle(.secondary)
                        Text(market.map { usd($0 - c.premiumPaid) } ?? "—").cell()
                            .foregroundStyle((market ?? 0) - c.premiumPaid >= 0 ? Color.green : Color.red)
                    }
                }
            }
        }
    }
    private func head(_ s: String, leading: Bool = false) -> some View {
        Text(s).font(.system(size: 9, weight: .medium, design: .monospaced))
            .tracking(1).foregroundStyle(.tertiary)
            .gridColumnAlignment(leading ? .leading : .trailing)
    }
}

// MARK: - Widgets

/// Mini price line: green/red by trend, soft gradient underfill.
struct Sparkline: View {
    let closes: [Double]
    var body: some View {
        GeometryReader { geo in
            if closes.count >= 2,
               let lo = closes.min(), let hi = closes.max(), hi > lo {
                let up = closes.last! >= closes.first!
                let color: Color = up ? .green : .red
                let pts: [CGPoint] = closes.enumerated().map { i, v in
                    CGPoint(
                        x: geo.size.width * CGFloat(i) / CGFloat(closes.count - 1),
                        y: geo.size.height * (1 - CGFloat((v - lo) / (hi - lo)))
                    )
                }
                ZStack {
                    Path { p in
                        p.move(to: CGPoint(x: pts[0].x, y: geo.size.height))
                        for pt in pts { p.addLine(to: pt) }
                        p.addLine(to: CGPoint(x: pts.last!.x, y: geo.size.height))
                        p.closeSubpath()
                    }
                    .fill(LinearGradient(colors: [color.opacity(0.22), .clear],
                                         startPoint: .top, endPoint: .bottom))
                    Path { p in
                        p.move(to: pts[0])
                        for pt in pts.dropFirst() { p.addLine(to: pt) }
                    }
                    .stroke(color.opacity(0.9), lineWidth: 1.4)
                }
            } else {
                RoundedRectangle(cornerRadius: 2).fill(Color.primary.opacity(0.06))
            }
        }
    }
}

struct DayPill: View {
    let pct: Double?
    var body: some View {
        let v = pct ?? 0
        Text(pct.map { String(format: "%+.2f%%", $0) } ?? "—")
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .padding(.horizontal, 7).padding(.vertical, 2.5)
            .background(Capsule().fill((v >= 0 ? Color.green : Color.red).opacity(pct == nil ? 0.06 : 0.14)))
            .foregroundStyle(pct == nil ? Color.secondary : (v >= 0 ? Color.green : Color.red))
    }
}

private struct DTEPill: View {
    let days: Int?
    var body: some View {
        let d = days ?? 999
        Text(days.map { "\($0)d" } ?? "—")
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .padding(.horizontal, 7).padding(.vertical, 2.5)
            .background(Capsule().fill(
                d < 14 ? Color.orange.opacity(0.18) :
                d < 45 ? Color.yellow.opacity(0.10) : Color.primary.opacity(0.07)))
            .foregroundStyle(d < 14 ? Color.orange : Color.secondary)
    }
}

extension Text {
    func cell() -> Text { font(.system(size: 12.5, design: .monospaced)) }
}
