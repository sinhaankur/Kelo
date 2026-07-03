import Foundation

/// Import holdings from a broker CSV export. Header names are matched
/// loosely (symbol/ticker, quantity/qty/shares, costBasis/cost/avg price,
/// acquired/date/purchased) so most broker exports work unedited. Imported
/// rows replace same-symbol holdings and append new ones; calls are untouched.
public enum CsvImporter {
    public struct ImportResult {
        public let imported: [Holding]
        public let skippedRows: Int
    }

    public static func parseHoldings(_ text: String) -> ImportResult {
        let lines = text.split(whereSeparator: \.isNewline).map(String.init)
        guard lines.count >= 2 else { return ImportResult(imported: [], skippedRows: 0) }

        let header = splitCsvRow(lines[0]).map {
            $0.lowercased().replacingOccurrences(of: " ", with: "")
                .replacingOccurrences(of: "_", with: "")
        }
        func col(_ names: [String]) -> Int? {
            header.firstIndex { h in names.contains { h.contains($0) } }
        }
        guard let symCol = col(["symbol", "ticker"]) else {
            return ImportResult(imported: [], skippedRows: lines.count - 1)
        }
        let qtyCol = col(["quantity", "qty", "shares", "units"])
        let costCol = col(["costbasis", "avgcost", "averagecost", "avgprice", "averageprice", "cost", "price"])
        let dateCol = col(["acquired", "purchasedate", "purchased", "opendate", "date"])

        var out: [Holding] = []
        var skipped = 0
        for line in lines.dropFirst() {
            let cells = splitCsvRow(line)
            guard symCol < cells.count else { skipped += 1; continue }
            let symbol = cells[symCol].trimmingCharacters(in: .whitespaces).uppercased()
            let qty = qtyCol.flatMap { $0 < cells.count ? parseNumber(cells[$0]) : nil }
            let cost = costCol.flatMap { $0 < cells.count ? parseNumber(cells[$0]) : nil }
            guard !symbol.isEmpty, let qty, qty > 0, let cost, cost > 0 else { skipped += 1; continue }
            let acquired = dateCol.flatMap { idx -> String? in
                guard idx < cells.count else { return nil }
                return normalizeDate(cells[idx])
            }
            out.append(Holding(symbol: symbol, quantity: qty, costBasis: cost, acquired: acquired))
        }
        return ImportResult(imported: out, skippedRows: skipped)
    }

    /// Parse a CSV file, merge into the live portfolio, and save it.
    @discardableResult
    public static func importFile(at url: URL) throws -> ImportResult {
        let text = try String(contentsOf: url, encoding: .utf8)
        let result = parseHoldings(text)
        guard !result.imported.isEmpty else { return result }
        var p = Portfolio.load()
        for h in result.imported {
            if let i = p.holdings.firstIndex(where: { $0.symbol == h.symbol }) {
                p.holdings[i] = h
            } else {
                p.holdings.append(h)
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
