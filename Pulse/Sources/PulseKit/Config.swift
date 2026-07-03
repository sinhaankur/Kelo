import Foundation

/// Local, gitignored config at ~/Documents/stock-tracker/config.json —
/// API keys and local-LLM settings live here, never in source or git.
public struct AppConfig: Codable {
    public var finnhubApiKey: String?
    public var llmEndpoint: String?
    public var llmModel: String?

    public init(finnhubApiKey: String? = nil, llmEndpoint: String? = nil, llmModel: String? = nil) {
        self.finnhubApiKey = finnhubApiKey
        self.llmEndpoint = llmEndpoint
        self.llmModel = llmModel
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
