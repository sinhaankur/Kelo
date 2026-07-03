import Foundation

/// Import holdings from a broker CSV export. Header names are matched
/// loosely (symbol/ticker, quantity/qty/shares, costBasis/cost/avg price,
/// acquired/date/purchased) so most broker exports work unedited. Imported
/// rows replace same-symbol holdings and append new ones; calls are untouched.
public enum CsvImporter {
    public struct ImportResult {
        public let imported: [Holding]
        public let skippedRows: Int
        /// True when the CSV was a full-account brokerage report — those
        /// REPLACE the holdings wholesale (sold positions must not linger).
        public let isFullAccountReport: Bool

        init(imported: [Holding], skippedRows: Int, isFullAccountReport: Bool = false) {
            self.imported = imported
            self.skippedRows = skippedRows
            self.isFullAccountReport = isFullAccountReport
        }
    }

    public static func parseHoldings(_ text: String) -> ImportResult {
        let lines = text.split(whereSeparator: \.isNewline).map(String.init)
        guard lines.count >= 2 else { return ImportResult(imported: [], skippedRows: 0) }

        let header = splitCsvRow(lines[0]).map {
            $0.lowercased().replacingOccurrences(of: " ", with: "")
                .replacingOccurrences(of: "_", with: "")
        }
        // Brokerage full-account reports (Wealthsimple et al.) carry exchange,
        // security type, book value and currencies — parse those exactly.
        if header.contains("bookvalue(market)") && header.contains("securitytype") {
            return parseBrokerageReport(lines: lines, header: header)
        }
        func col(_ names: [String]) -> Int? {
            header.firstIndex { h in names.contains { h.contains($0) } }
        }
        guard let symCol = col(["symbol", "ticker"]) else {
            return ImportResult(imported: [], skippedRows: lines.count - 1)
        }
        let qtyCol = col(["quantity", "qty", "shares", "units"])
        // NOTE: no bare "price" substring — it would match "Market Price"
        // (the CURRENT price) and silently corrupt every cost basis.
        let costCol = col(["costbasis", "avgcost", "averagecost", "avgprice", "averageprice", "unitcost", "bookvalue", "bookcost", "totalcost", "cost"])
            ?? header.firstIndex(of: "price")
        // Total-cost columns are per POSITION — divide by quantity below.
        let costIsTotal: Bool = {
            guard let c = costCol else { return false }
            return ["bookvalue", "bookcost", "totalcost"].contains { header[c].contains($0) }
        }()
        let dateCol = col(["acquired", "purchasedate", "purchased", "opendate", "date"])

        var out: [Holding] = []
        var skipped = 0
        for line in lines.dropFirst() {
            let cells = splitCsvRow(line)
            guard symCol < cells.count else { skipped += 1; continue }
            let symbol = cells[symCol].trimmingCharacters(in: .whitespaces).uppercased()
            let qty = qtyCol.flatMap { $0 < cells.count ? parseNumber(cells[$0]) : nil }
            let rawCost = costCol.flatMap { $0 < cells.count ? parseNumber(cells[$0]) : nil }
            guard !symbol.isEmpty, let qty, qty > 0, let rawCost, rawCost > 0 else { skipped += 1; continue }
            let cost = costIsTotal ? rawCost / qty : rawCost
            let acquired = dateCol.flatMap { idx -> String? in
                guard idx < cells.count else { return nil }
                return normalizeDate(cells[idx])
            }
            out.append(Holding(symbol: symbol, quantity: qty, costBasis: cost, acquired: acquired))
        }
        return ImportResult(imported: out, skippedRows: skipped)
    }

    // MARK: - Brokerage full-account report (Wealthsimple format)

    /// Yahoo needs exchange-qualified symbols — a bare TSX-V ticker would
    /// silently resolve to some unrelated US stock and invent money.
    /// Class shares use dots on the exchanges, dashes on Yahoo (TECK.B →
    /// TECK-B.TO).
    static func yahooSymbol(raw: String, exchange: String, securityType: String,
                            bookCurrency: String) -> String {
        if securityType == "CRYPTOCURRENCY" {
            return "\(raw)-\(bookCurrency.isEmpty ? "USD" : bookCurrency)"
        }
        let base = raw.replacingOccurrences(of: ".", with: "-")
        switch exchange {
        case "TSX": return "\(base).TO"
        case "TSX-V": return "\(base).V"
        case "CSE": return "\(base).CN"
        case "CBOE CANADA": return "\(base).NE" // formerly NEO
        default: return base // NYSE / NASDAQ / BATS / FINRA — bare on Yahoo
        }
    }

    /// Cost = Book Value (Market) ÷ quantity, in the LISTING's own currency —
    /// each position's return stays a pure ratio and FX only enters at the
    /// display-total layer.
    static func parseBrokerageReport(lines: [String], header: [String]) -> ImportResult {
        func idx(_ name: String) -> Int? { header.firstIndex(of: name) }
        guard let symCol = idx("symbol"),
              let qtyCol = idx("quantity"),
              let bookCol = idx("bookvalue(market)"),
              let typeCol = idx("securitytype")
        else { return ImportResult(imported: [], skippedRows: lines.count - 1) }
        let exchCol = idx("exchange")
        let bookCurCol = idx("bookvaluecurrency(market)")

        var out: [Holding] = []
        var skipped = 0
        for line in lines.dropFirst() {
            let cells = splitCsvRow(line)
            guard symCol < cells.count, typeCol < cells.count,
                  qtyCol < cells.count, bookCol < cells.count else { skipped += 1; continue }
            let raw = cells[symCol].trimmingCharacters(in: .whitespaces).uppercased()
            let qty = parseNumber(cells[qtyCol])
            let book = parseNumber(cells[bookCol])
            guard !raw.isEmpty, let qty, qty > 0, let book, book > 0 else { skipped += 1; continue }
            let exchange = exchCol.flatMap { $0 < cells.count ? cells[$0].uppercased() : nil } ?? ""
            let currency = bookCurCol.flatMap { $0 < cells.count ? cells[$0].uppercased() : nil } ?? "USD"
            let symbol = yahooSymbol(raw: raw, exchange: exchange,
                                     securityType: cells[typeCol].uppercased(),
                                     bookCurrency: currency)
            out.append(Holding(symbol: symbol, quantity: qty, costBasis: book / qty,
                               acquired: nil, currency: currency))
        }
        // Same asset across accounts (TFSA + RRSP + …) AGGREGATES: total
        // quantity, book-weighted average cost — replacing would drop shares.
        var bySymbol: [String: Holding] = [:]
        var order: [String] = []
        for h in out {
            if let existing = bySymbol[h.symbol] {
                let qty = existing.quantity + h.quantity
                let book = existing.costBasis * existing.quantity + h.costBasis * h.quantity
                bySymbol[h.symbol] = Holding(symbol: h.symbol, quantity: qty,
                                             costBasis: book / qty,
                                             acquired: existing.acquired,
                                             currency: existing.currency)
            } else {
                bySymbol[h.symbol] = h
                order.append(h.symbol)
            }
        }
        return ImportResult(imported: order.compactMap { bySymbol[$0] },
                            skippedRows: skipped, isFullAccountReport: true)
    }

    /// Parse a CSV file, merge into the live portfolio, and save it. Full
    /// account reports replace the holdings wholesale; partial CSVs merge.
    @discardableResult
    public static func importFile(at url: URL) throws -> ImportResult {
        let text = try String(contentsOf: url, encoding: .utf8)
        let result = parseHoldings(text)
        guard !result.imported.isEmpty else { return result }
        var p = Portfolio.load()
        if result.isFullAccountReport {
            p.holdings = result.imported
        } else {
            for h in result.imported {
                if let i = p.holdings.firstIndex(where: { $0.symbol == h.symbol }) {
                    p.holdings[i] = h
                } else {
                    p.holdings.append(h)
                }
            }
        }
        try p.save()
        return result
    }

    // Minimal quoted-field CSV splitting — handles commas inside quotes.
    static func splitCsvRow(_ row: String) -> [String] {
        var cells: [String] = []
        var current = ""
        var inQuotes = false
        for ch in row {
            switch ch {
            case "\"": inQuotes.toggle()
            case "," where !inQuotes:
                cells.append(current); current = ""
            default: current.append(ch)
            }
        }
        cells.append(current)
        return cells.map { $0.trimmingCharacters(in: .whitespaces) }
    }

    static func parseNumber(_ s: String) -> Double? {
        let cleaned = s.replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespaces)
        return Double(cleaned)
    }

    /// Accept "YYYY-MM-DD" or "MM/DD/YYYY"; return canonical ISO or nil.
    static func normalizeDate(_ s: String) -> String? {
        let t = s.trimmingCharacters(in: .whitespaces)
        if parseISODate(t) != nil { return t }
        let f = DateFormatter()
        f.timeZone = TimeZone(identifier: "America/New_York")
        for fmt in ["MM/dd/yyyy", "M/d/yyyy", "MM/dd/yy"] {
            f.dateFormat = fmt
            if let d = f.date(from: t) { return isoDateString(d) }
        }
        return nil
    }
}
