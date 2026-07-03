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
    public let recommendations: AnalystRecs?
    public let news: [GlobalSentiment.Headline]
}

public enum OutlookService {
    public static func fetch(symbol: String, finnhubKey: String?) async -> StockOutlook? {
        async let histTask = QuoteService.fetchHistory(symbol: symbol, range: "1y")
        async let benchTask = QuoteService.fetchHistory(symbol: "^GSPC", range: "1y")
        async let quoteTask = QuoteService.fetch(symbol: symbol)
        async let recsTask = fetchRecommendations(symbol: symbol, key: finnhubKey)
        async let newsTask = SentimentService.companyNews(symbol: symbol, key: finnhubKey, limit: 3)

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
                            recommendations: await recsTask,
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
