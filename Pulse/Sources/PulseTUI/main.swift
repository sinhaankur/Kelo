import Foundation
import PulseKit

// pulse-tui — the same private tracker, rendered in a terminal so Pulse runs
// on Linux as well as macOS. Everything stays on-device: portfolio.json +
// config.json in ~/Documents/stock-tracker, quotes fetched directly, LLM
// analysis (--analyze) via the local Ollama endpoint.
//
//   pulse-tui                 render the dashboard once
//   pulse-tui --watch         re-render every 60 s
//   pulse-tui --analyze       dashboard + local-LLM read on the numbers
//   pulse-tui --import <csv>  merge a broker CSV into portfolio.json
//   pulse-tui --no-color      plain output

let args = CommandLine.arguments.dropFirst()
if args.contains("--version") {
    print("\(PulseInfo.name) \(PulseInfo.version) — \(PulseInfo.tagline)")
    exit(0)
}
if args.contains("--help") || args.contains("-h") {
    print("""
    pulse-tui — private portfolio dashboard (macOS + Linux, on-device)
      --watch          refresh every 60s
      --analyze        add a local-LLM (Ollama) read, grounded in live data
      --import <csv>   merge broker CSV (symbol/quantity/cost[/date]) into portfolio.json
      --no-color       disable ANSI colors
      --version        print version
    """)
    exit(0)
}

let useColor = !args.contains("--no-color") && ProcessInfo.processInfo.environment["NO_COLOR"] == nil
let watch = args.contains("--watch")
let analyze = args.contains("--analyze")

// Theme follows the clock here too: brighter accents through the day, dimmer
// framing at night. Content colors (gain green / loss red) never change.
let isNight = ThemeMode.auto.isDark()

enum Ansi {
    static var on = true
    static func wrap(_ code: String, _ s: String) -> String { on ? "\u{1B}[\(code)m\(s)\u{1B}[0m" : s }
    static func bold(_ s: String) -> String { wrap("1", s) }
    static func dim(_ s: String) -> String { wrap("2", s) }
    static func green(_ s: String) -> String { wrap("32", s) }
    static func red(_ s: String) -> String { wrap("31", s) }
    static func yellow(_ s: String) -> String { wrap("33", s) }
    static func cyan(_ s: String) -> String { wrap("36", s) }
    static func header(_ s: String) -> String { isNight ? wrap("34;1", s) : wrap("36;1", s) }
}
Ansi.on = useColor

func signed(_ v: Double, _ fmt: String = "%+.2f%%") -> String {
    let s = String(format: fmt, v)
    return v >= 0 ? Ansi.green(s) : Ansi.red(s)
}

func spark(_ closes: [Double], width: Int = 24) -> String {
    guard closes.count >= 2, let lo = closes.min(), let hi = closes.max(), hi > lo else {
        return String(repeating: "·", count: width)
    }
    let blocks = Array("▁▂▃▄▅▆▇█")
    let n = min(width, closes.count)
    let stride = Double(closes.count - 1) / Double(max(1, n - 1))
    var out = ""
    for i in 0..<n {
        let v = closes[Int((Double(i) * stride).rounded())]
        let idx = Int((v - lo) / (hi - lo) * Double(blocks.count - 1))
        out.append(blocks[idx])
    }
    let up = closes.last! >= closes.first!
    return up ? Ansi.green(out) : Ansi.red(out)
}

func pad(_ s: String, _ w: Int, right: Bool = false) -> String {
    // ANSI escapes don't take up columns — pad on visible length.
    let visible = s.replacingOccurrences(of: "\u{1B}\\[[0-9;]*m", with: "", options: .regularExpression).count
    let fill = String(repeating: " ", count: max(0, w - visible))
    return right ? fill + s : s + fill
}

// --import: one-shot CSV merge, then continue to the dashboard.
if let i = args.firstIndex(of: "--import") {
    let rest = args[args.index(after: i)...]
    guard let path = rest.first else {
        print("usage: pulse-tui --import <file.csv>"); exit(1)
    }
    do {
        let result = try CsvImporter.importFile(at: URL(fileURLWithPath: path))
        print("imported \(result.imported.count) positions (\(result.skippedRows) rows skipped) → portfolio.json")
    } catch {
        print("import failed: \(error.localizedDescription)"); exit(1)
    }
}

let config = AppConfig.load()
Money.displayCode = config.displayCurrency ?? "USD"
Security.hardenDataFiles()

@MainActor
func render() async {
    let portfolio = Portfolio.load()
    guard !(portfolio.holdings.isEmpty && portfolio.calls.isEmpty) else {
        print("portfolio.json is empty — add holdings at \(Portfolio.fileURL.path)")
        return
    }
    let paperTrades = PaperLedger.load()
    let symbols = portfolio.holdings.map(\.symbol) + portfolio.calls.map(\.underlying)
        + paperTrades.map(\.symbol)

    async let quotesTask = QuoteService.fetchAll(symbols: symbols)
    async let chainsTask = OptionsService.fetchAll(underlyings: portfolio.calls.map(\.underlying))
    async let sentimentTask = SentimentService.fetch(finnhubKey: config.finnhubApiKey)
    async let newsTask = SentimentService.holdingsNews(
        symbols: portfolio.holdings.map(\.symbol), key: config.finnhubApiKey)
    let quotes = await quotesTask
    let chains = await chainsTask
    let sentiment = await sentimentTask
    let holdingsNews = await newsTask
    // FX: convert every quote currency into the display currency.
    let fxRates = await QuoteService.fxRates(for: Set(quotes.values.map(\.currency)),
                                             display: Money.displayCode)
    func fx(_ currency: String?) -> Double { fxRates[currency ?? "USD"] ?? 1 }
    let analysis = await TimelineService.analyze(holdings: portfolio.holdings,
                                                 quotes: quotes, fxRates: fxRates)
    let timelines = analysis.timelines

    func callValue(_ c: CallPosition) -> Double? {
        if let oq = chains[OptionsService.occSymbol(for: c)], oq.mark > 0 {
            return oq.mark * 100 * Double(c.contracts) * fx("USD")
        }
        return (quotes[c.underlying]?.price).map { c.intrinsic(at: $0) * fx("USD") }
    }
    func holdingValue(_ h: Holding) -> Double {
        (quotes[h.symbol].map { $0.price * fx($0.currency) } ?? 0) * h.quantity
    }
    func holdingCost(_ h: Holding) -> Double { h.costBasis * h.quantity * fx(h.currency) }

    let holdingsValue = portfolio.holdings.reduce(0.0) { $0 + holdingValue($1) }
    let callsValue = portfolio.calls.reduce(0.0) { $0 + (callValue($1) ?? 0) }
    let totalValue = holdingsValue + callsValue
    let totalCost = portfolio.holdings.reduce(0.0) { $0 + holdingCost($1) }
        + portfolio.calls.reduce(0.0) { $0 + $1.premiumPaid * fx("USD") }
    let dayPL = portfolio.holdings.reduce(0.0) { acc, h in
        acc + (quotes[h.symbol].map { $0.dayChange * fx($0.currency) * h.quantity } ?? 0)
    }
    let allTime = totalValue - totalCost
    let allTimePct = totalCost > 0 ? allTime / totalCost * 100 : 0

    // Record today's real marks (incl. options) — only when every holding
    // actually got a quote, so a partial fetch never poisons the record.
    if !portfolio.holdings.isEmpty,
       portfolio.holdings.allSatisfy({ quotes[$0.symbol] != nil }) {
        SnapshotStore.record(holdings: holdingsValue, options: callsValue, cost: totalCost)
    }

    var out: [String] = []
    let stamp = Date().formatted(date: .abbreviated, time: .shortened)
    out.append(Ansi.header("PULSE") + Ansi.dim("  v\(PulseInfo.version) · \(stamp) · on-device · quotes delayed"))
    let holdingSyms = Set(portfolio.holdings.map(\.symbol))
    let quoted = holdingSyms.filter { quotes[$0] != nil }.count
    if quoted < holdingSyms.count {
        out.append(Ansi.yellow("⚠ quotes \(quoted)/\(holdingSyms.count) holdings — unquoted (likely delisted/invalid) count as $0"))
    }
    out.append("\(Ansi.bold(usd(totalValue)))  today \(signed(dayPL, "%+.0f"))\(Ansi.dim(" (holdings)"))  all-time \(signed(allTime, "%+.0f")) \(signed(allTimePct, "(%+.1f%%)"))")
    if let g = analysis.history, g.values.count >= 2,
       let first = g.dates.first, let lastValue = g.values.last, let lastCost = g.costs.last {
        let gain = lastValue - lastCost
        let coverage = g.covered < g.total ? " · covers \(g.covered)/\(g.total) positions" : ""
        out.append(Ansi.dim("growth since \(isoDateString(first)) (holdings): ")
            + spark(g.values, width: 48)
            + "  " + signed(gain, "%+.0f") + Ansi.dim(" vs cost deployed\(coverage)"))
    }
    out.append("")

    // Global sentiment — sourced numbers only.
    out.append(Ansi.header("GLOBAL SENTIMENT") + Ansi.dim("  " + sentiment.summary))
    if !sentiment.indices.isEmpty {
        out.append("  " + sentiment.indices.map { "\(Ansi.dim($0.name)) \(signed($0.dayPct, "%+.1f%%"))" }
            .joined(separator: "   "))
    }
    if !sentiment.macro.isEmpty {
        out.append("  " + Ansi.dim("world: ") + sentiment.macro
            .map { "\(Ansi.dim($0.name)) \($0.levelLabel) \(signed($0.dayPct, "%+.1f%%"))" }
            .joined(separator: "   "))
    }
    for h in sentiment.headlines.prefix(4) {
        out.append("  " + Ansi.dim("· \(h.title)  [\(h.source)]"))
    }
    if sentiment.headlines.isEmpty && config.finnhubApiKey == nil {
        out.append("  " + Ansi.dim("(add finnhubApiKey to config.json for headlines)"))
    }
    for sym in holdingsNews.keys.sorted() {
        for h in holdingsNews[sym] ?? [] {
            out.append("  " + Ansi.dim("· [\(sym)] \(h.title)  [\(h.source)]"))
        }
    }
    out.append("")

    // Holdings with invested-date timelines.
    out.append(Ansi.header("HOLDINGS") + Ansi.dim("  ~date = estimated from cost basis"))
    out.append(Ansi.dim(pad("SYMBOL", 9) + pad("QTY", 8, right: true) + pad("PRICE", 11, right: true)
        + pad("DAY", 9, right: true) + pad("VALUE", 11, right: true) + pad("P/L", 10, right: true)
        + "  " + pad("INVESTED", 12) + pad("HELD", 6) + pad("ANN.", 10, right: true) + "  SINCE BUY"))
    for h in portfolio.holdings {
        let q = quotes[h.symbol]
        let value = holdingValue(h)
        let pl = value - holdingCost(h)
        let t = timelines[h.symbol]
        var line = pad(Ansi.bold(h.symbol), 9)
        line += pad(num(h.quantity), 8, right: true)
        line += pad(q.map { usd($0.price * fx($0.currency)) } ?? "…", 11, right: true)
        line += pad(q.map { signed($0.dayChangePct) } ?? "—", 9, right: true)
        line += pad(q != nil ? usd(value) : "—", 11, right: true)
        line += pad(q != nil ? signed(pl, "%+.0f") : "—", 10, right: true)
        line += "  "
        line += pad(t.map { $0.acquiredLabel } ?? "—", 12)
        line += pad(t.map { $0.heldLabel } ?? "—", 6)
        line += pad(t?.annualizedPct.map { signed($0, "%+.1f%%/y") } ?? Ansi.dim("—"), 10, right: true)
        line += "  " + spark(t?.closesSince ?? q?.closes ?? [])
        out.append(line)
    }
    out.append("")

    if !portfolio.calls.isEmpty {
        out.append(Ansi.header("CALLS") + Ansi.dim("  CBOE delayed · mark = bid/ask mid"))
        for c in portfolio.calls {
            let market = callValue(c)
            let pl = market.map { $0 - c.premiumPaid }
            var line = pad(Ansi.bold("\(c.underlying) \(Int(c.strike))C ×\(c.contracts)"), 20)
            line += pad("exp \(c.expiry)", 16)
            line += pad(c.daysToExpiry.map { "\($0)d" } ?? "—", 6, right: true)
            line += pad(market.map(usd) ?? "—", 11, right: true)
            line += pad(pl.map { signed($0, "%+.0f") } ?? "—", 10, right: true)
            out.append(line)
        }
        out.append("")
    }

    // Deterministic right/wrong flags with their numbers.
    var flags: [(Bool, String)] = []
    var positions: [(String, Double, Double)] = [] // label, plPct, value
    for h in portfolio.holdings {
        let cost = holdingCost(h)
        guard cost > 0, quotes[h.symbol] != nil else { continue }
        let v = holdingValue(h)
        positions.append((h.symbol, (v - cost) / cost * 100, v))
    }
    for c in portfolio.calls {
        guard c.premiumPaid > 0, let v = callValue(c) else { continue }
        positions.append(("\(c.underlying) \(Int(c.strike))C", (v - c.premiumPaid) / c.premiumPaid * 100, v))
    }
    if !positions.isEmpty {
        let winners = positions.filter { $0.1 >= 0 }.count
        flags.append((winners * 2 >= positions.count, "win rate \(winners)/\(positions.count) positions in profit"))
        let totalPos = positions.reduce(0.0) { $0 + $1.2 }
        if let top = positions.max(by: { $0.2 < $1.2 }), totalPos > 0 {
            let p = top.2 / totalPos * 100
            flags.append((p <= 40, "concentration: \(top.0) is \(Int(p))% of the portfolio"))
        }
    }
    for c in portfolio.calls {
        if let dte = c.daysToExpiry, dte < 14 {
            flags.append((false, "\(c.underlying) \(Int(c.strike))C expires in \(dte)d — theta decay is steepest now"))
        }
    }
    for h in portfolio.holdings {
        guard let t = timelines[h.symbol], t.holdingDays >= 180,
              let ann = t.annualizedPct, let bench = t.benchmarkPct else { continue }
        let benchAnn = (pow(1 + bench / 100, 365.25 / Double(t.holdingDays)) - 1) * 100
        if ann >= benchAnn + 5 {
            flags.append((true, "\(h.symbol) held \(t.heldLabel): \(String(format: "%+.1f", ann))%/y vs S&P \(String(format: "%+.1f", benchAnn))%/y — beating the index"))
        } else if ann <= benchAnn - 5 {
            flags.append((false, "\(h.symbol) held \(t.heldLabel): \(String(format: "%+.1f", ann))%/y vs S&P \(String(format: "%+.1f", benchAnn))%/y — lagging the index"))
        }
    }
    if !flags.isEmpty {
        out.append(Ansi.header("RIGHT / WRONG"))
        for (ok, text) in flags {
            out.append("  " + (ok ? Ansi.green("✓") : Ansi.yellow("⚠")) + " " + text)
        }
        out.append("")
    }

    // Verdicts — a committed, condition-based call per position.
    let verdicts = ReviewService.verdicts(holdings: portfolio.holdings, quotes: quotes,
                                          timelines: timelines, fxRates: fxRates)
    let exits = verdicts.filter { $0.call == .exit }
    let reviewsV = verdicts.filter { $0.call == .review }
    if !verdicts.isEmpty {
        out.append(Ansi.header("VERDICTS")
            + Ansi.dim("  \(Ansi.red("\(exits.count) exit candidates"))\(Ansi.dim(" (\(usd(exits.reduce(0) { $0 + $1.valueAtStake })))")) · \(reviewsV.count) review · \(verdicts.count - exits.count - reviewsV.count) hold"))
        for v in exits.prefix(8) {
            out.append("  " + Ansi.red("EXIT? ") + pad(Ansi.bold(v.symbol), 12)
                + Ansi.dim(v.reasons.joined(separator: " · "))
                + "  " + Ansi.dim(usd(v.valueAtStake)))
        }
        if exits.count > 8 { out.append("  " + Ansi.dim("… and \(exits.count - 8) more exit candidates (see the app)")) }
        out.append("")
    }

    // Structural review — dollars-at-stake findings.
    let reviewItems = ReviewService.review(holdings: portfolio.holdings, quotes: quotes,
                                           timelines: timelines, fxRates: fxRates)
    if !reviewItems.isEmpty {
        out.append(Ansi.header("REVIEW") + Ansi.dim("  structural findings, ranked by dollars at stake"))
        for item in reviewItems.prefix(5) {
            out.append("  " + Ansi.yellow("▸ ") + item.headline + Ansi.dim("  (\(usd(item.dollarImpact)))"))
        }
        out.append("")
    }

    // Paper trades — the calls, scored so far. No real orders, ever.
    if !paperTrades.isEmpty {
        let reviews = PaperLedger.review(paperTrades, quotes: quotes,
                                         benchmark: analysis.benchmark)
        out.append(Ansi.header("PAPER TRADES") + Ansi.dim("  calls scored against reality"))
        for r in reviews {
            var line = "  " + pad("\(r.trade.side) \(r.trade.symbol)", 15)
            line += pad(r.trade.date, 12)
            line += pad("in " + usd(r.trade.entryPrice), 13, right: true)
            line += pad(r.currentPrice.map { "now " + usd($0) } ?? "now …", 14, right: true)
            line += pad(r.movePct.map { signed($0) } ?? "—", 10, right: true)
            line += pad(r.benchmarkPct.map { Ansi.dim("S&P " + String(format: "%+.2f%%", $0)) } ?? "", 14, right: true)
            if let right = r.callRightSoFar {
                line += "  " + (right ? Ansi.green("✓ right so far") : Ansi.red("✗ wrong so far"))
            }
            out.append(line)
        }
        let scored = reviews.compactMap(\.callRightSoFar)
        if !scored.isEmpty {
            out.append("  " + Ansi.dim("direction right: \(scored.filter { $0 }.count)/\(scored.count) — small sample, not an edge"))
        }
        out.append("")
    }

    out.append(Ansi.dim("sources: Yahoo (delayed) · CBOE delayed · alternative.me · Finnhub — data stays on this machine"))
    print(out.joined(separator: "\n"))

    if analyze {
        print("")
        print(Ansi.header("ANALYZE") + (config.usesAnthropicCloud
            ? Ansi.yellow("  ⚠ Anthropic cloud — context leaves this machine")
            : Ansi.dim("  local model via \(config.llmEndpoint ?? "http://localhost:11434")")))
        let timelineLines = portfolio.holdings.compactMap { h -> String? in
            guard let t = timelines[h.symbol] else { return nil }
            return "\(h.symbol): invested \(t.acquiredLabel)\(t.estimated ? " (est.)" : ""), held \(t.heldLabel), return \(String(format: "%+.1f%%", t.totalReturnPct))"
        }.joined(separator: "\n")
        let holdingLines = portfolio.holdings.map { h -> String in
            let q = quotes[h.symbol]
            return "\(h.symbol): qty \(num(h.quantity)), cost \(usd(h.costBasis)), now \(q.map { usd($0.price) } ?? "?")"
        }.joined(separator: "\n")
        let system = """
        You are a careful market analysis assistant running fully locally on the user's machine. \
        Use ONLY the data provided. Structure: 1) MARKET CONTEXT 2) RIGHT / WRONG in the portfolio \
        3) WORTH CONSIDERING (2–3 observations, never directives to buy or sell). \
        End with exactly: "Not financial advice."
        """
        let user = """
        === GLOBAL SENTIMENT (sourced) ===
        \(sentiment.summary)
        \(sentiment.headlines.prefix(5).map { "headline [\($0.source)]: \($0.title)" }.joined(separator: "\n"))

        === MY PORTFOLIO (live) ===
        \(holdingLines)

        === POSITION TIMELINES (est. = detected, not stated) ===
        \(timelineLines)
        """
        do {
            let text = try await LlmService.analyzeRouted(
                system: system, user: user, config: config,
                ollamaEndpoint: config.llmEndpoint ?? "http://localhost:11434",
                ollamaModel: config.llmModel ?? "qwen2.5:7b")
            print(text)
        } catch {
            print(Ansi.yellow("⚠ \(error.localizedDescription)"))
        }
    }
}

if watch {
    while true {
        print("\u{1B}[2J\u{1B}[H", terminator: "") // clear screen, home cursor
        await render()
        try? await Task.sleep(nanoseconds: 60_000_000_000)
    }
} else {
    await render()
}
