import Foundation

/// Symbols tracked without being owned — the "thinking about it" list that
/// feeds the paper-trade loop: watch → outlook → paper call → only then real.
/// Local file, gitignored, like everything else personal.
public enum Watchlist {
    public static var fileURL: URL {
        Portfolio.dirURL.appendingPathComponent("watchlist.json")
    }

    public static func load(from url: URL = fileURL) -> [String] {
        guard let data = try? Data(contentsOf: url),
              let list = try? JSONDecoder().decode([String].self, from: data)
        else { return [] }
        return list
    }

    static func save(_ symbols: [String], to url: URL) {
        if let data = try? JSONEncoder().encode(symbols) {
            try? data.write(to: url, options: .atomic)
        }
    }

    @discardableResult
    public static func add(_ symbol: String, to url: URL = fileURL) -> [String] {
        let s = symbol.trimmingCharacters(in: .whitespaces).uppercased()
        var list = load(from: url)
        guard !s.isEmpty, !list.contains(s) else { return list }
        list.append(s)
        save(list, to: url)
        return list
    }

    @discardableResult
    public static func remove(_ symbol: String, from url: URL = fileURL) -> [String] {
        var list = load(from: url)
        list.removeAll { $0 == symbol }
        save(list, to: url)
        return list
    }
}
