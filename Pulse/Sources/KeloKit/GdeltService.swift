import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Live world events from GDELT — a free, keyless global news/event database.
/// Real headlines about conflict and markets, tagged with the country they're
/// about, so the tactical map's CONFLICT layer shows sourced events (with a
/// link to the actual article), never invented markers. GDELT asks for ≤1
/// request / 5s, so this is a periodic background fetch, not real-time.
public struct WorldEvent {
    public let title: String
    public let country: String   // GDELT source country (best-effort location)
    public let url: String
    public let domain: String
    public let seenAt: Date
    /// Approx map coordinate from the country name (nil if unknown).
    public var coord: (lat: Double, lon: Double)? { CountryGeo.center(country) }
}

public enum GdeltService {
    /// Recent conflict-related events. `query` is a GDELT boolean query.
    public static func events(query: String = "(conflict OR war OR sanctions OR strike)",
                              max: Int = 40, days: Int = 2) async -> [WorldEvent] {
        var comps = URLComponents(string: "https://api.gdeltproject.org/api/v2/doc/doc")!
        comps.queryItems = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "mode", value: "ArtList"),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "maxrecords", value: String(max)),
            URLQueryItem(name: "timespan", value: "\(days)d"),
            URLQueryItem(name: "sort", value: "DateDesc"),
        ]
        guard let url = comps.url else { return [] }
        var req = URLRequest(url: url)
        req.setValue("Mozilla/5.0 Pulse", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 15
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200 else { return [] }
        struct Response: Decodable {
            struct Article: Decodable {
                let title: String?
                let url: String?
                let domain: String?
                let sourcecountry: String?
                let seendate: String?
            }
            let articles: [Article]?
        }
        // GDELT returns a rate-limit notice as plain text when throttled;
        // decode defensively.
        guard let parsed = try? JSONDecoder().decode(Response.self, from: data),
              let arts = parsed.articles else { return [] }
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        fmt.timeZone = TimeZone(identifier: "UTC")
        var out: [WorldEvent] = []
        var seenTitles = Set<String>()
        for a in arts {
            guard let t = a.title, !t.isEmpty, let country = a.sourcecountry,
                  !country.isEmpty, !seenTitles.contains(t) else { continue }
            seenTitles.insert(t)
            out.append(WorldEvent(title: t, country: country, url: a.url ?? "",
                                  domain: a.domain ?? "", seenAt: fmt.date(from: a.seendate ?? "") ?? Date()))
        }
        return out
    }
}
