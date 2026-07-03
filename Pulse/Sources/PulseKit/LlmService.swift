import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct LlmError: LocalizedError {
    public let message: String
    public var errorDescription: String? { message }
}

/// Local LLM bridge — Ollama's chat API on localhost (or any host the user
/// sets). Nothing is sent to a cloud service; the analysis stays on-machine.
public enum LlmService {
    private struct ChatResponse: Decodable {
        struct Message: Decodable { let content: String }
        let message: Message?
        let error: String?
    }

    public static func analyze(system: String, user: String,
                               endpoint: String, model: String) async throws -> String {
        guard let url = URL(string: "\(endpoint.trimmingCharacters(in: .whitespaces))/api/chat") else {
            throw LlmError(message: "Bad endpoint URL")
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 180
        let body: [String: Any] = [
            "model": model,
            "stream": false,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": user],
            ],
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        guard let (data, _) = try? await URLSession.shared.data(for: req) else {
            throw LlmError(message: "Couldn't reach \(endpoint) — is Ollama running? (ollama serve)")
        }
        guard let parsed = try? JSONDecoder().decode(ChatResponse.self, from: data) else {
            throw LlmError(message: "Unexpected response from the model server")
        }
        if let err = parsed.error { throw LlmError(message: err) }
        return parsed.message?.content ?? ""
    }

    /// Anthropic Messages API — CLOUD, opt-in only via config.json
    /// (llmProvider: "anthropic"). Unlike Ollama, the analysis context
    /// LEAVES the machine; callers must surface that in the UI.
    public static func analyzeAnthropic(system: String, user: String,
                                        apiKey: String, model: String) async throws -> String {
        struct Response: Decodable {
            struct Block: Decodable { let text: String? }
            struct APIError: Decodable { let message: String }
            let content: [Block]?
            let error: APIError?
        }
        var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.timeoutInterval = 120
        let body: [String: Any] = [
            "model": model,
            "max_tokens": 1500,
            "system": system,
            "messages": [["role": "user", "content": user]],
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        guard let (data, _) = try? await URLSession.shared.data(for: req) else {
            throw LlmError(message: "Couldn't reach api.anthropic.com")
        }
        guard let parsed = try? JSONDecoder().decode(Response.self, from: data) else {
            throw LlmError(message: "Unexpected response from Anthropic")
        }
        if let err = parsed.error { throw LlmError(message: err.message) }
        return parsed.content?.compactMap(\.text).joined() ?? ""
    }

    /// Route by config: Ollama by default (on-device), Anthropic only when
    /// explicitly configured.
    public static func analyzeRouted(system: String, user: String, config: AppConfig,
                                     ollamaEndpoint: String, ollamaModel: String) async throws -> String {
        if config.usesAnthropicCloud {
            return try await analyzeAnthropic(system: system, user: user,
                                              apiKey: config.anthropicApiKey ?? "",
                                              model: config.llmModel ?? "claude-sonnet-4-6")
        }
        return try await analyze(system: system, user: user,
                                 endpoint: ollamaEndpoint, model: ollamaModel)
    }
}
