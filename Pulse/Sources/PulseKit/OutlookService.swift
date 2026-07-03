import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Per-stock outlook — sourced signals, NOT a forecast. Everything here is
/// either computed from real price history (momentum, 52-week position,
/// volatility, drawdown) or reported from real analyst recommendation counts
/// (Finnhub). Markets are near-efficient: Pulse never invents a price target
/// or presents a guess as the future.
public struct StockOutlook {
    public struct AnalystRecs {
        public let strongBuy: Int
        public let buy: Int
        public let hold: Int
        public let sell: Int
        public let strongSell: Int
        public let period: String

        public var total: Int { strongBuy + buy + hold + sell + strongSell }
        public var bullish: Int { strongBuy + buy }
        public var bearish: Int { sell + strongSell }
    }

    /// Company fundamentals — the "why is it doing badly" layer that a price
    /// chart can't answer: is the business shrinking, unprofitable, or in
    /// debt? Reported as facts, not judgment.
    public struct Fundamentals {
        public let name: String?
        public let industry: String?
        public let peRatio: Double?
        public let profitMarginPct: Double?
        public let revenueGrowthPct: Double?     // TTM YoY
        public let debtToEquity: Double?
        public let week52HighGapPct: Double?

        /// Plain-language read of the health signals present.
        public var healthNotes: [String] {
            var n: [String] = []
            if let m = profitMarginPct {
                n.append(m < 0 ? "unprofitable: net margin \(String(format: "%.1f", m))% — it loses money on every dollar of sales"
                               : "profitable: net margin \(String(format: "%.1f", m))%")
            }
            if let g = revenueGrowthPct {
                n.append(g < 0 ? "shrinking: revenue \(String(format: "%.1f", g))% year-over-year — the business is contracting"
                               : "growing: revenue +\(String(format: "%.1f", g))% year-over-year")
            }
            if let d = debtToEquity, d > 2 {
                n.append("heavy debt: debt-to-equity \(String(format: "%.1f", d)) — leveraged, fragile if rates or sales turn")
            }
            if let pe = peRatio, pe > 40 {
                n.append("priced for perfection: P/E \(String(format: "%.0f", pe)) — the market expects big growth; any miss gets punished")
            }
            return n
        }
    }

    public let symbol: String
    public let price: Double
    /// Quote currency of `price` (from Yahoo meta).
    public let currency: String
    public let ret30dPct: Double?
    public let ret1yPct: Double?
    public let benchRet1yPct: Double?
    /// Price vs the 50/200-day simple moving averages (% above/below).
    public let vsMa50Pct: Double?
    public let vsMa200Pct: Double?
    /// 14-day RSI (Wilder) — classic momentum bands: >70 hot, <30 washed out.
    public let rsi14: Double?
    public let high52w: Double?
    public let low52w: Double?
    /// Distance from the 52-week high (≤ 0; −20 means 20% below the high).
    public let pctFromHigh: Double?
    /// Annualized realized volatility from daily returns — how violently
    /// this thing actually moves.
    public let annualVolPct: Double?
    /// Worst peak-to-trough fall inside the last year.
    public let maxDrawdown1yPct: Double?
    /// Trailing-12-month dividend yield from real paid distributions.
    /// Caveat baked into the UI: a soaring yield is often a falling price.
    public let ttmDividendYieldPct: Double?
    public let recommendations: AnalystRecs?
    public let fundamentals: Fundamentals?
    public let news: [GlobalSentiment.Headline]
}

public enum OutlookService {
    public static func fetch(symbol: String, finnhubKey: String?) async -> StockOutlook? {
        async let histTask = QuoteService.fetchHistory(symbol: symbol, range: "1y")
        async let benchTask = QuoteService.fetchHistory(symbol: "^GSPC", range: "1y")
        async let quoteTask = QuoteService.fetch(symbol: symbol)
        async let recsTask = fetchRecommendations(symbol: symbol, key: finnhubKey)
        async let newsTask = SentimentService.companyNews(symbol: symbol, key: finnhubKey, limit: 3)
        async let divTask = QuoteService.trailingDividendYieldPct(symbol: symbol)
        async let fundTask = fundamentals(symbol: symbol, key: finnhubKey)

        let hist = await histTask
        guard let quote = await quoteTask, hist.count >= 2 else { return nil }
        let closes = hist.map(\.close)
        let s = stats(closes: closes, price: quote.price)
        let bench = await benchTask.map(\.close)
        var benchRet: Double? = nil
        if let b0 = bench.first, let bN = bench.last, b0 > 0 {
            benchRet = (bN - b0) / b0 * 100
        }
        return StockOutlook(symbol: symbol, price: quote.price,
                            currency: quote.currency,
                            ret30dPct: s.ret30d, ret1yPct: s.ret1y,
                            benchRet1yPct: benchRet,
                            vsMa50Pct: movingAverageGap(closes: closes, price: quote.price, window: 50),
                            vsMa200Pct: movingAverageGap(closes: closes, price: quote.price, window: 200),
                            rsi14: rsi(closes: closes, price: quote.price),
                            high52w: s.high, low52w: s.low,
                            pctFromHigh: s.fromHigh,
                            annualVolPct: s.vol,
                            maxDrawdown1yPct: s.drawdown,
                            ttmDividendYieldPct: await divTask,
                            recommendations: await recsTask,
                            fundamentals: await fundTask,
                            news: await newsTask)
    }

    /// Price vs an N-day simple moving average, % — nil when there isn't a
    /// full window of data (never a padded guess).
    static func movingAverageGap(closes: [Double], price: Double, window: Int) -> Double? {
        guard closes.count >= window else { return nil }
        var series = closes
        series[series.count - 1] = price
        let ma = series.suffix(window).reduce(0, +) / Double(window)
        return ma > 0 ? (price - ma) / ma * 100 : nil
    }

    /// 14-day RSI with Wilder smoothing.
    static func rsi(closes: [Double], price: Double, period: Int = 14) -> Double? {
        guard closes.count > period + 1 else { return nil }
        var series = closes
        series[series.count - 1] = price
        var gains = 0.0, losses = 0.0
        for i in 1...period {
            let d = series[i] - series[i - 1]
            if d >= 0 { gains += d } else { losses -= d }
        }
        var avgGain = gains / Double(period)
        var avgLoss = losses / Double(period)
        for i in (period + 1)..<series.count {
            let d = series[i] - series[i - 1]
            avgGain = (avgGain * Double(period - 1) + max(0, d)) / Double(period)
            avgLoss = (avgLoss * Double(period - 1) + max(0, -d)) / Double(period)
        }
        if avgLoss == 0 { return 100 }
        let rs = avgGain / avgLoss
        return 100 - 100 / (1 + rs)
    }

    /// Pure stats from ~1y of daily closes — fully testable.
    static func stats(closes: [Double], price: Double)
        -> (ret30d: Double?, ret1y: Double?, high: Double?, low: Double?,
            fromHigh: Double?, vol: Double?, drawdown: Double?) {
        guard closes.count >= 2 else { return (nil, nil, nil, nil, nil, nil, nil) }
        var series = closes
        series[series.count - 1] = price // live tail

        let ret1y = series.first.flatMap { $0 > 0 ? (price - $0) / $0 * 100 : nil }
        let idx30 = max(0, series.count - 22) // ~30 calendar days of trading bars
        let ret30d = series[idx30] > 0 ? (price - series[idx30]) / series[idx30] * 100 : nil

        let high = series.max()
        let low = series.min()
        let fromHigh = high.flatMap { $0 > 0 ? (price - $0) / $0 * 100 : nil }

        var dailyReturns: [Double] = []
        for i in 1..<series.count where series[i - 1] > 0 {
            dailyReturns.append(series[i] / series[i - 1] - 1)
        }
        var vol: Double? = nil
        if dailyReturns.count >= 20 {
            let mean = dailyReturns.reduce(0, +) / Double(dailyReturns.count)
            let variance = dailyReturns.reduce(0) { $0 + ($1 - mean) * ($1 - mean) }
                / Double(dailyReturns.count - 1)
            vol = variance.squareRoot() * Double(252).squareRoot() * 100
        }

        var peak = series[0]
        var drawdown = 0.0
        for v in series {
            peak = max(peak, v)
            if peak > 0 { drawdown = min(drawdown, (v - peak) / peak * 100) }
        }
        return (ret30d, ret1y, high, low, fromHigh, vol, drawdown)
    }

    public static func fundamentals(symbol: String, key: String?) async -> StockOutlook.Fundamentals? {
        guard let key, !key.isEmpty, SentimentService.isEquitySymbol(symbol) else { return nil }
        // Profile + metrics are two Finnhub calls.
        struct Profile: Decodable { let name: String?; let finnhubIndustry: String? }
        struct Metrics: Decodable {
            struct M: Decodable {
                let peBasicExclExtraTTM: Double?
                let netProfitMarginTTM: Double?
                let revenueGrowthTTMYoy: Double?
                let totalDebtToEquityQuarterly: Double?
            }
            let metric: M?
        }
        func url(_ path: String) -> URL? {
            URL(string: "https://finnhub.io/api/v1/\(path)&token=\(key)")
        }
        async let profileData = fetchJSON(Profile.self, url("stock/profile2?symbol=\(symbol)"))
        async let metricsData = fetchJSON(Metrics.self, url("stock/metric?symbol=\(symbol)&metric=all"))
        let p = await profileData
        let m = await metricsData?.metric
        guard p != nil || m != nil else { return nil }
        return StockOutlook.Fundamentals(
            name: p?.name, industry: p?.finnhubIndustry,
            peRatio: m?.peBasicExclExtraTTM,
            profitMarginPct: m?.netProfitMarginTTM,
            revenueGrowthPct: m?.revenueGrowthTTMYoy,
            debtToEquity: m?.totalDebtToEquityQuarterly,
            week52HighGapPct: nil)
    }

    private static func fetchJSON<T: Decodable>(_ type: T.Type, _ url: URL?) async -> T? {
        guard let url else { return nil }
        var req = URLRequest(url: url)
        req.timeoutInterval = 10
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    /// Real analyst recommendation counts (Finnhub, free tier) — what the
    /// street currently says, reported as counts, never as advice.
    static func fetchRecommendations(symbol: String, key: String?) async -> StockOutlook.AnalystRecs? {
        guard let key, !key.isEmpty, SentimentService.isEquitySymbol(symbol) else { return nil }
        var comps = URLComponents(string: "https://finnhub.io/api/v1/stock/recommendation")!
        comps.queryItems = [
            URLQueryItem(name: "symbol", value: symbol),
            URLQueryItem(name: "token", value: key),
        ]
        struct Item: Decodable {
            let strongBuy: Int
            let buy: Int
            let hold: Int
            let sell: Int
            let strongSell: Int
            let period: String
        }
        var req = URLRequest(url: comps.url!)
        req.timeoutInterval = 10
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let items = try? JSONDecoder().decode([Item].self, from: data),
              let latest = items.first
        else { return nil }
        return StockOutlook.AnalystRecs(strongBuy: latest.strongBuy, buy: latest.buy,
                                        hold: latest.hold, sell: latest.sell,
                                        strongSell: latest.strongSell, period: latest.period)
    }
}
