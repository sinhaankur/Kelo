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
    @Published var watchlist: [String] = []
    @Published var reviewItems: [ReviewItem] = []
    @Published var verdicts: [PositionVerdict] = []
    @Published var incomeReport: IncomeReport? = nil
    @Published var clusters: [HoldingCluster] = []
    @Published var sectors: [ClusterService.SectorSlice] = []
    /// symbol → industry (Finnhub), built up as fundamentals are fetched.
    @Published var industryBySymbol: [String: String] = [:]
    @Published var macroData: MacroData? = nil
    @Published var worldMarkets: WorldMarkets? = nil
    @Published var worldEvents: [WorldEvent] = []
    private var lastGdeltFetch: Date? = nil

    private var ollamaProcess: Process? = nil
    @Published var snapshots: [DailySnapshot] = []
    @Published var lastRefresh: Date? = nil
    @Published var refreshing = false
    /// Progressive-load progress: (quotes landed, total symbols). Large
    /// portfolios take a while — the UI must fill as data arrives, never
    /// sit on zeros looking dead.
    @Published var quoteProgress: (done: Int, total: Int)? = nil
    /// Minute tick — re-evaluates the auto theme even when nothing else moves.
    @Published var tick = Date()
    /// Symbol whose outlook sheet is open (tap a holding to set).
    @Published var outlookTarget: OutlookTarget? = nil

    struct OutlookTarget: Identifiable {
        let symbol: String
        var id: String { symbol }
    }

    let config = AppConfig.load()
    /// Multipliers into the display currency per quote currency (live FX).
    @Published var fxRates: [String: Double] = [:]
    private var timer: Timer?
    private var timelineSignature = ""
    private var lastSentimentFetch: Date? = nil
    private var benchmarkHistory: [QuoteService.HistoryPoint] = []

    init() {
        Money.displayCode = config.displayCurrency ?? "USD"
        Security.hardenDataFiles() // 0600 on portfolio/config/ledgers
    }

    func fx(_ currency: String?) -> Double { fxRates[currency ?? "USD"] ?? 1 }
    func displayPrice(_ q: Quote) -> Double { q.price * fx(q.currency) }
    func holdingCost(_ h: Holding) -> Double { h.costBasis * h.quantity * fx(h.currency) }

    func start() {
        guard timer == nil else { return }
        refresh()
        startOllamaIfNeeded()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick = Date()
                self?.refresh()
            }
        }
    }

    /// Ollama runs by default: if the endpoint isn't answering and the user
    /// hasn't opted out (autoStartOllama: false) or switched provider,
    /// launch `ollama serve` and stop it again when Pulse quits.
    private func startOllamaIfNeeded() {
        guard config.autoStartOllama ?? true, !config.usesAnthropicCloud else { return }
        let endpoint = config.llmEndpoint ?? "http://localhost:11434"
        Task {
            guard await !LlmService.ping(endpoint: endpoint) else { return }
            let candidates = ["/opt/homebrew/bin/ollama", "/usr/local/bin/ollama"]
            guard let bin = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) })
            else { return } // not installed — the analyze card will say so
            await MainActor.run {
                let proc = Process()
                proc.executableURL = URL(fileURLWithPath: bin)
                proc.arguments = ["serve"]
                proc.standardOutput = FileHandle.nullDevice
                proc.standardError = FileHandle.nullDevice
                try? proc.run()
                self.ollamaProcess = proc
                NotificationCenter.default.addObserver(
                    forName: NSApplication.willTerminateNotification,
                    object: nil, queue: .main) { [weak self] _ in
                    // Only stop what we started — never someone's own server.
                    MainActor.assumeIsolated { self?.ollamaProcess?.terminate() }
                }
            }
        }
    }

    func refresh() {
        portfolio = Portfolio.load() // re-read so edits to the JSON show up
        paperTrades = PaperLedger.load()
        snapshots = SnapshotStore.load()
        watchlist = Watchlist.load()
        // Paper-trade + watchlist symbols get quotes too, even when not held.
        let symbols = portfolio.holdings.map(\.symbol) + portfolio.calls.map(\.underlying)
            + paperTrades.map(\.symbol) + watchlist
        guard !symbols.isEmpty else { return }
        refreshing = true
        let callUnderlyings = portfolio.calls.map(\.underlying)
        Task {
            async let chainsTask = OptionsService.fetchAll(underlyings: callUnderlyings)
            // Chunked fetch, published as each chunk lands: a 434-symbol
            // portfolio fills the UI within seconds instead of sitting on
            // zeros for a minute.
            let all = Array(Set(symbols))
            var merged: [String: Quote] = [:]
            let chunkSize = 40
            for start in stride(from: 0, to: all.count, by: chunkSize) {
                let chunk = Array(all[start..<min(start + chunkSize, all.count)])
                let part = await QuoteService.fetchAll(symbols: chunk)
                merged.merge(part) { _, new in new }
                let progress = (done: merged.count, total: all.count)
                let snapshotSoFar = merged
                await MainActor.run {
                    self.quotes = snapshotSoFar
                    self.quoteProgress = start + chunkSize < all.count ? progress : nil
                }
            }
            let oq = await chainsTask
            let q = merged
            // FX after quotes: convert every quote currency into the display
            // currency (CAD accounts hold USD listings and vice versa).
            let fx = await QuoteService.fxRates(for: Set(q.values.map(\.currency)),
                                                display: Money.displayCode)
            await MainActor.run {
                self.optionQuotes = oq
                self.fxRates = fx
                self.lastRefresh = Date()
                self.refreshing = false
                self.quoteProgress = nil
                self.recordSnapshot()
                self.recomputePaperReviews()
            }
            await self.refreshTimelines(quotes: q, fxRates: fx)
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
        reviewItems = ReviewService.review(holdings: portfolio.holdings, quotes: quotes,
                                           timelines: timelines, fxRates: fxRates)
        verdicts = ReviewService.verdicts(holdings: portfolio.holdings, quotes: quotes,
                                          timelines: timelines, fxRates: fxRates)
        clusters = ClusterService.clusters(holdings: portfolio.holdings, quotes: quotes,
                                           fxRates: fxRates)
        sectors = ClusterService.sectors(holdings: portfolio.holdings, quotes: quotes,
                                         fxRates: fxRates, industryBySymbol: industryBySymbol)
        runAgentIfEnabled()
        fetchIndustriesIfNeeded()
    }

    /// Pull industry labels for the top holdings (Finnhub), cached — so the
    /// sector breakdown fills in without hammering the API on every refresh.
    private func fetchIndustriesIfNeeded() {
        let key = config.finnhubApiKey
        guard key != nil else { return }
        let missing = sortedHoldings.prefix(30)
            .map(\.symbol)
            .filter { industryBySymbol[$0] == nil && ClusterService.isEquitySymbolPublic($0) }
        guard !missing.isEmpty else { return }
        Task {
            for sym in missing.prefix(10) { // rate-limit friendly
                if let f = await OutlookService.fundamentals(symbol: sym, key: key),
                   let ind = f.industry, !ind.isEmpty {
                    await MainActor.run { self.industryBySymbol[sym] = ind }
                }
            }
            await MainActor.run {
                self.sectors = ClusterService.sectors(holdings: self.portfolio.holdings,
                                                      quotes: self.quotes, fxRates: self.fxRates,
                                                      industryBySymbol: self.industryBySymbol)
            }
        }
    }

    /// The Pulse Agent: paper-only, once a day at most, scorecard in the
    /// open. Toggleable from the Agent section.
    private func runAgentIfEnabled() {
        let enabled = UserDefaults.standard.object(forKey: "agentEnabled") as? Bool ?? true
        guard enabled, !timelines.isEmpty, !verdicts.isEmpty else { return }
        let ideas = ReviewService.ideas(holdings: portfolio.holdings, quotes: quotes,
                                        timelines: timelines, verdicts: verdicts,
                                        fxRates: fxRates)
        if let action = AgentService.runCycle(ideas: ideas, quotes: quotes,
                                              fxRates: fxRates, openCalls: paperTrades) {
            PaperLedger.append(action.trade)
            paperTrades = PaperLedger.load()
            paperReviews = PaperLedger.review(paperTrades, quotes: quotes,
                                              benchmark: benchmarkHistory)
        }
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

    func addToWatchlist(_ symbol: String) {
        watchlist = Watchlist.add(symbol)
        refresh() // pick up the new symbol's quote
    }

    func removeFromWatchlist(_ symbol: String) {
        watchlist = Watchlist.remove(symbol)
    }

    /// Timelines need 10y of history per symbol — fetch only when the
    /// positions themselves change, not on every 60 s quote tick.
    private func refreshTimelines(quotes: [String: Quote], fxRates: [String: Double]) async {
        let sig = portfolio.holdings
            .map { "\($0.symbol)|\($0.costBasis)|\($0.acquired ?? "")" }
            .joined(separator: ",")
        guard sig != timelineSignature else { return }
        let analysis = await TimelineService.analyze(holdings: portfolio.holdings,
                                                     quotes: quotes, fxRates: fxRates)
        self.timelines = analysis.timelines
        self.portfolioHistory = analysis.history
        self.benchmarkHistory = analysis.benchmark
        self.timelineSignature = sig
        self.recomputePaperReviews()
        let income = await IncomeService.report(holdings: portfolio.holdings,
                                                quotes: quotes, fxRates: fxRates)
        self.incomeReport = income
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
            async let macro = MacroDataService.fetch()
            async let world = WorldMarketsService.fetch()
            let (sentiment, holdingsNews, macroData, worldMarkets) = await (s, news, macro, world)
            await MainActor.run {
                self.sentiment = sentiment
                self.holdingsNews = holdingsNews
                self.macroData = macroData
                self.worldMarkets = worldMarkets
            }
        }
        refreshWorldEvents()
    }

    /// GDELT asks for ≤1 request / 5s — fetch conflict events at most every
    /// 10 minutes, in the background.
    func refreshWorldEvents() {
        if let t = lastGdeltFetch, Date().timeIntervalSince(t) < 600 { return }
        lastGdeltFetch = Date()
        Task {
            let events = await GdeltService.events()
            await MainActor.run { self.worldEvents = events }
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
            let verb = result.isFullAccountReport ? "synced" : "imported"
            return "\(verb) \(result.imported.count) positions\(skipped)"
        } catch {
            return "import failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Editing (the portfolio is yours to change)

    /// Remove a position — mirrors selling it in the broker. Writes back to
    /// portfolio.json so every card recomputes.
    func removeHolding(_ symbol: String) {
        var p = Portfolio.load()
        p.holdings.removeAll { $0.symbol == symbol }
        try? p.save()
        timelineSignature = ""
        refresh()
    }

    /// Edit quantity / cost / date of a position (a partial sell, an add, a
    /// correction). Persists and recomputes.
    func updateHolding(_ symbol: String, quantity: Double, costBasis: Double,
                       acquired: String?) {
        var p = Portfolio.load()
        if let i = p.holdings.firstIndex(where: { $0.symbol == symbol }) {
            let old = p.holdings[i]
            p.holdings[i] = Holding(symbol: old.symbol, quantity: quantity,
                                    costBasis: costBasis, acquired: acquired ?? old.acquired,
                                    currency: old.currency, assetClass: old.assetClass)
            try? p.save()
            timelineSignature = ""
            refresh()
        }
    }

    /// Add a position by hand (a buy Pulse should track before the next
    /// broker export). The acquired date, when given, makes the timeline
    /// exact instead of estimated.
    func addHolding(symbol: String, quantity: Double, costBasis: Double,
                    currency: String, acquired: String?) {
        var p = Portfolio.load()
        let s = symbol.trimmingCharacters(in: .whitespaces).uppercased()
        guard !s.isEmpty else { return }
        if let i = p.holdings.firstIndex(where: { $0.symbol == s }) {
            let old = p.holdings[i]
            p.holdings[i] = Holding(symbol: s, quantity: quantity, costBasis: costBasis,
                                    acquired: acquired, currency: currency,
                                    assetClass: old.assetClass)
        } else {
            p.holdings.append(Holding(symbol: s, quantity: quantity, costBasis: costBasis,
                                      acquired: acquired, currency: currency))
        }
        try? p.save()
        timelineSignature = ""
        refresh()
    }

    /// Market value of a call position (US options are USD → converted to
    /// display): CBOE mark × 100 × contracts; falls back to intrinsic.
    func callValue(_ c: CallPosition) -> Double? {
        if let oq = optionQuotes[OptionsService.occSymbol(for: c)], oq.mark > 0 {
            return oq.mark * 100 * Double(c.contracts) * fx("USD")
        }
        return (quotes[c.underlying]?.price).map { c.intrinsic(at: $0) * fx("USD") }
    }

    func holdingValue(_ h: Holding) -> Double {
        (quotes[h.symbol].map { displayPrice($0) } ?? 0) * h.quantity
    }

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
        portfolio.holdings.reduce(0) { $0 + holdingCost($1) }
            + portfolio.calls.reduce(0) { $0 + $1.premiumPaid * fx("USD") }
    }
    /// Today's move across stock/crypto holdings (options excluded — no
    /// previous-day option marks yet; labeled in the UI).
    var dayPL: Double {
        portfolio.holdings.reduce(0) { acc, h in
            acc + (quotes[h.symbol].map { $0.dayChange * fx($0.currency) * h.quantity } ?? 0)
        }
    }
}

// MARK: - Root

// IA: one subject per section. Overview = my account at a glance;
// Market = everything external (sentiment, world gauges, news);
// Positions = per-holding depth; Analysis = all judgment (deterministic
// flags first, local model second); Trade = drafting + paper scoring.
enum AppSection: String, CaseIterable, Identifiable {
    case overview, market, positions, analysis, trade, options, agent
    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: return "Overview"
        case .market: return "Market"
        case .positions: return "Positions"
        case .analysis: return "Analysis"
        case .trade: return "Trade"
        case .options: return "Options"
        case .agent: return "Agent"
        }
    }
    var icon: String {
        switch self {
        case .overview: return "waveform.path.ecg"
        case .market: return "globe"
        case .positions: return "chart.bar.xaxis"
        case .analysis: return "text.magnifyingglass"
        case .trade: return "arrow.left.arrow.right"
        case .options: return "book"
        case .agent: return "sparkles"
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
                        Text(PulseInfo.author)
                            .font(.system(size: 8.5, weight: .medium))
                            .foregroundStyle(.tertiary)
                            .padding(.top, 1)
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
                            // Command center, top to bottom: how am I doing,
                            // what should I do, then the supporting picture.
                            // The full world map lives in Market.
                            AccountStatsCard(model: model)
                            HealthBanner(model: model)
                            DailyBriefCard(model: model)
                            if !model.clusters.isEmpty { ClusterCard(model: model) }
                            GrowthCard(model: model)
                            AllocationCard(model: model)
                            MarketStrip(model: model)
                        case .market:
                            TacticalMapView(model: model)
                            SentimentCard(model: model)
                            MacroCard(model: model)
                            WatchlistCard(model: model)
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
                            SectorCard(model: model)
                            IncomeCard(model: model)
                            TimelineCard(model: model)
                            if !model.portfolio.calls.isEmpty { CallsCard(model: model) }
                        case .analysis:
                            VerdictsCard(model: model)
                            ReviewCard(model: model)
                            LookupCard(model: model)
                            StatsCard(model: model)
                            AnalysisCard(app: model)
                        case .options:
                            OptionsLearnCard(model: model)
                            OptionsCalculatorCard(model: model)
                        case .agent:
                            AgentCard(model: model)
                            IdeasCard(model: model)
                        case .trade:
                            IdeasCard(model: model)
                            TradeDraftCard(model: model)
                            IBKRCard(model: model)
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
        .sheet(item: $model.outlookTarget) { target in
            OutlookSheet(model: model, symbol: target.symbol)
        }
        .onAppear { model.start() }
    }

    private var footer: some View {
        let holdingSymbols = Set(model.portfolio.holdings.map(\.symbol))
        let quoted = holdingSymbols.filter { model.quotes[$0] != nil }.count
        let domains = "query1.finance.yahoo.com · cdn.cboe.com · api.alternative.me · finnhub.io"
            + (model.config.usesAnthropicCloud ? " · api.anthropic.com (cloud LLM, opt-in)" : "")
        return HStack {
            Text("educational, not financial advice · data stays on-device · talks only to: \(domains)")
            Spacer()
            if let p = model.quoteProgress {
                Text("loading quotes \(p.done)/\(p.total)…")
                    .foregroundStyle(.secondary)
            } else if quoted < holdingSymbols.count {
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

/// Understand ANY stock — search a ticker, get the outlook sheet (sourced
/// signals, never a forecast). The engine behind it is the same one the
/// holdings rows open.
private struct LookupCard: View {
    @ObservedObject var model: AppModel
    @State private var symbol = ""
    var body: some View {
        Card(title: "UNDERSTAND A STOCK", trailing: "sourced signals, not a forecast") {
            HStack(spacing: 8) {
                TextField("any ticker — NVDA, SHOP.TO, BTC-CAD…", text: $symbol)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(width: 260)
                    .onSubmit(open)
                Button("Open outlook", action: open)
                    .disabled(symbol.trimmingCharacters(in: .whitespaces).isEmpty)
                Text("momentum · 52-week range · volatility · analyst counts · news · local-model read")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
                Spacer()
            }
        }
    }
    private func open() {
        let s = symbol.trimmingCharacters(in: .whitespaces).uppercased()
        guard !s.isEmpty else { return }
        model.outlookTarget = AppModel.OutlookTarget(symbol: s)
    }
}

/// Symbols watched without being owned — click through to the outlook, log
/// a paper call, only then think about real money.
private struct WatchlistCard: View {
    @ObservedObject var model: AppModel
    @State private var newSymbol = ""
    var body: some View {
        Card(title: "WATCHLIST", trailing: "click a symbol for its outlook") {
            VStack(alignment: .leading, spacing: 8) {
                if model.watchlist.isEmpty {
                    Text("nothing watched yet — add a ticker to track it without owning it")
                        .font(.system(size: 11, design: .monospaced)).foregroundStyle(.tertiary)
                } else {
                    Grid(alignment: .trailing, horizontalSpacing: 16, verticalSpacing: 8) {
                        ForEach(model.watchlist, id: \.self) { s in
                            let q = model.quotes[s]
                            GridRow {
                                Button {
                                    model.outlookTarget = AppModel.OutlookTarget(symbol: s)
                                } label: {
                                    HStack(spacing: 4) {
                                        Text(s).font(.system(size: 12.5, weight: .semibold, design: .monospaced))
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 8)).foregroundStyle(.tertiary)
                                    }
                                }
                                .buttonStyle(.plain)
                                .gridColumnAlignment(.leading)
                                Text(q.map { usd(model.displayPrice($0)) } ?? "…").cell()
                                DayPill(pct: q?.dayChangePct)
                                Button {
                                    model.removeFromWatchlist(s)
                                } label: {
                                    Image(systemName: "xmark.circle").font(.system(size: 11))
                                }
                                .buttonStyle(.plain).foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
                HStack(spacing: 8) {
                    TextField("add ticker…", text: $newSymbol)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11, design: .monospaced))
                        .frame(width: 140)
                        .onSubmit(add)
                    Button("Watch", action: add)
                        .disabled(newSymbol.trimmingCharacters(in: .whitespaces).isEmpty)
                    Spacer()
                }
            }
        }
    }
    private func add() {
        model.addToWatchlist(newSymbol)
        newSymbol = ""
    }
}

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
    @State private var editing: Holding? = nil
    @State private var adding = false
    var body: some View {
        Card(title: "HOLDINGS", trailing: "grouped by asset class · tap a symbol for its outlook") {
            // Always-visible manage toolbar — add and edit are first-class,
            // not buried in a right-click.
            HStack(spacing: 8) {
                Button { adding = true } label: {
                    Label("Add position", systemImage: "plus.circle.fill")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.borderedProminent).controlSize(.small)
                Button { importCsv() } label: {
                    Label("Import / sync CSV", systemImage: "square.and.arrow.down")
                        .font(.system(size: 11))
                }
                .controlSize(.small)
                if !importStatus.isEmpty {
                    Text(importStatus)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                Text("\(model.portfolio.holdings.count) positions")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
            .padding(.bottom, 4)

            // Stocks / ETFs / Crypto sections, each sorted by size.
            let groups: [(String, [Holding])] = {
                let sorted = model.sortedHoldings
                let order = ["Stock", "ETF", "Crypto"]
                var out: [(String, [Holding])] = []
                for cls in order {
                    let members = sorted.filter { ($0.assetClass ?? "Stock") == cls }
                    if !members.isEmpty { out.append((cls, members)) }
                }
                let known = Set(order)
                let rest = sorted.filter { !known.contains($0.assetClass ?? "Stock") }
                if !rest.isEmpty { out.append(("Other", rest)) }
                return out
            }()
            Grid(alignment: .trailing, horizontalSpacing: 16, verticalSpacing: 10) {
                GridRow {
                    head("SYMBOL", leading: true); head(""); head("QTY"); head("PRICE")
                    head("DAY"); head("VALUE"); head("P/L"); head("")
                }
                ForEach(groups, id: \.0) { cls, members in
                GridRow {
                    Text("\(cls.uppercased())S — \(members.count)")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .tracking(1.5)
                        .foregroundStyle(.secondary)
                        .gridColumnAlignment(.leading)
                        .gridCellColumns(3)
                    Text(usd(members.reduce(0) { $0 + model.holdingValue($1) }))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .gridCellColumns(5)
                }
                .padding(.top, 4)
                ForEach(members) { h in
                    let q = model.quotes[h.symbol]
                    let value = model.holdingValue(h)
                    let pl = value - model.holdingCost(h)
                    GridRow {
                        Button {
                            model.outlookTarget = AppModel.OutlookTarget(symbol: h.symbol)
                        } label: {
                            HStack(spacing: 4) {
                                Text(h.symbol)
                                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 8, weight: .semibold))
                                    .foregroundStyle(.tertiary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help("Outlook + lifecycle for \(h.symbol) — sourced signals, not a forecast")
                        .gridColumnAlignment(.leading)
                        Sparkline(closes: q?.closes ?? [])
                            .frame(width: 72, height: 20)
                        Text(num(h.quantity)).cell()
                        Text(q.map { usd(model.displayPrice($0)) } ?? "…").cell()
                        DayPill(pct: q?.dayChangePct)
                        Text(q != nil ? usd(value) : "—").cell()
                        PLCell(pl: q != nil ? pl : nil,
                               pct: q != nil && model.holdingCost(h) > 0
                                    ? pl / model.holdingCost(h) * 100 : nil)
                        // Always-visible edit / sell buttons per row.
                        HStack(spacing: 6) {
                            Button { editing = h } label: {
                                Image(systemName: "pencil").font(.system(size: 10))
                            }
                            .buttonStyle(.plain).foregroundStyle(.secondary)
                            .help("Edit \(h.symbol) — quantity, cost, date")
                            Button { confirmSell(h) } label: {
                                Image(systemName: "trash").font(.system(size: 10))
                            }
                            .buttonStyle(.plain).foregroundStyle(.tertiary)
                            .help("Mark \(h.symbol) sold / remove")
                        }
                        .gridColumnAlignment(.center)
                    }
                    .contextMenu {
                        Button("Edit \(h.symbol)…") { editing = h }
                        Button("Sold / remove \(h.symbol)", role: .destructive) {
                            confirmSell(h)
                        }
                        Divider()
                        Button("Open outlook") {
                            model.outlookTarget = AppModel.OutlookTarget(symbol: h.symbol)
                        }
                    }
                }
                }
            }
        }
        .sheet(item: $editing) { h in EditHoldingSheet(model: model, holding: h) }
        .sheet(isPresented: $adding) { EditHoldingSheet(model: model, holding: nil) }
    }

    private func confirmSell(_ h: Holding) {
        let alert = NSAlert()
        alert.messageText = "Mark \(h.symbol) as sold?"
        alert.informativeText = "Removes it from your tracked portfolio (mirror the actual sale in your broker). You can re-import anytime."
        alert.addButton(withTitle: "Remove \(h.symbol)")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            model.removeHolding(h.symbol)
            importStatus = "removed \(h.symbol) — do the actual sale in your broker"
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

/// Trader-grade P/L cell: dollar figure, percent, and a magnitude bar that
/// fills green (up) or red (down) so the eye scans winners and losers
/// instantly without reading numbers.
struct PLCell: View {
    let pl: Double?
    let pct: Double?
    var body: some View {
        guard let pl, let pct else {
            return AnyView(Text("—").cell().foregroundStyle(.secondary))
        }
        let color: Color = pl >= 0 ? .green : .red
        let fill = min(1.0, abs(pct) / 50.0) // 50%+ move = full bar
        return AnyView(
            VStack(alignment: .trailing, spacing: 2) {
                HStack(spacing: 5) {
                    Text(usd(pl)).font(.system(size: 12.5, design: .monospaced))
                    Text(String(format: "%+.0f%%", pct))
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .opacity(0.85)
                }
                .foregroundStyle(color)
                GeometryReader { geo in
                    ZStack(alignment: pl >= 0 ? .leading : .trailing) {
                        Capsule().fill(Color.primary.opacity(0.06))
                        Capsule().fill(color.opacity(0.55))
                            .frame(width: max(3, geo.size.width * fill))
                    }
                }
                .frame(height: 3)
            }
            .frame(width: 96)
        )
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
