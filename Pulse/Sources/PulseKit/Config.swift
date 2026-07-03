import Foundation

/// Local, gitignored config at ~/Documents/stock-tracker/config.json —
/// API keys and local-LLM settings live here, never in source or git.
public struct AppConfig: Codable {
    public var finnhubApiKey: String?
    public var llmEndpoint: String?
    public var llmModel: String?
    /// Cash sitting in the brokerage, for the Trade Draft card's affordability
    /// math. Pulse only reads it — it never places orders anywhere.
    public var cashAvailable: Double?

    public init(finnhubApiKey: String? = nil, llmEndpoint: String? = nil,
                llmModel: String? = nil, cashAvailable: Double? = nil) {
        self.finnhubApiKey = finnhubApiKey
        self.llmEndpoint = llmEndpoint
        self.llmModel = llmModel
        self.cashAvailable = cashAvailable
    }

    public static var fileURL: URL {
        Portfolio.dirURL.appendingPathComponent("config.json")
    }

    public static func load() -> AppConfig {
        guard let data = try? Data(contentsOf: fileURL),
              let c = try? JSONDecoder().decode(AppConfig.self, from: data)
        else { return AppConfig() }
        return c
    }
}
