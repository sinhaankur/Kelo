import Foundation

/// Local, gitignored config at ~/Documents/stock-tracker/config.json —
/// API keys and local-LLM settings live here, never in source or git.
public struct AppConfig: Codable {
    public var finnhubApiKey: String?
    /// "ollama" (default — fully on-device) or "anthropic" (CLOUD: the
    /// analysis context leaves this machine over TLS; the UI says so
    /// whenever it's active). Market data fetches never include positions.
    public var llmProvider: String?
    public var llmEndpoint: String?
    public var llmModel: String?
    public var anthropicApiKey: String?
    /// Currency all totals are shown in (e.g. "CAD"); quotes in other
    /// currencies are converted at the live FX rate. Default USD.
    public var displayCurrency: String?
    /// Cash sitting in the brokerage, for the Trade Draft card's affordability
    /// math. Pulse only reads it — it never places orders anywhere.
    public var cashAvailable: Double?
    /// Launch `ollama serve` automatically when the app starts and it isn't
    /// already running (default true; set false to manage Ollama yourself).
    public var autoStartOllama: Bool?

    public init(finnhubApiKey: String? = nil, llmProvider: String? = nil,
                llmEndpoint: String? = nil, llmModel: String? = nil,
                anthropicApiKey: String? = nil, displayCurrency: String? = nil,
                cashAvailable: Double? = nil, autoStartOllama: Bool? = nil) {
        self.finnhubApiKey = finnhubApiKey
        self.llmProvider = llmProvider
        self.llmEndpoint = llmEndpoint
        self.llmModel = llmModel
        self.anthropicApiKey = anthropicApiKey
        self.displayCurrency = displayCurrency
        self.cashAvailable = cashAvailable
        self.autoStartOllama = autoStartOllama
    }

    public var usesAnthropicCloud: Bool {
        llmProvider?.lowercased() == "anthropic" && !(anthropicApiKey ?? "").isEmpty
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
