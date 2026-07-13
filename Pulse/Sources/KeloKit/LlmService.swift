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

    /// Quick health check — is a model server answering at this endpoint?
    public static func ping(endpoint: String) async -> Bool {
        guard let url = URL(string: "\(endpoint.trimmingCharacters(in: .whitespaces))/api/tags") else { return false }
        var req = URLRequest(url: url)
        req.timeoutInterval = 2
        guard let (_, resp) = try? await URLSession.shared.data(for: req) else { return false }
        return (resp as? HTTPURLResponse)?.statusCode == 200
    }

    /// Which model actually answered — so the UI can be honest about it.
    public enum Backend: String { case appleOnDevice, ollama, anthropicCloud }

    /// Route by config, preferring the MOST PRIVATE option that works:
    ///   1. Apple's on-device Foundation Model (nothing leaves the device) —
    ///      unless the user has explicitly opted into the cloud provider.
    ///   2. Ollama on localhost (on-device, user-run).
    ///   3. Anthropic cloud — only when explicitly configured.
    /// Returns the reply AND which backend produced it.
    public static func routed(system: String, user: String, config: AppConfig,
                              ollamaEndpoint: String, ollamaModel: String) async throws -> (text: String, backend: Backend) {
        // Explicit cloud opt-in wins (the user chose it), and is clearly flagged.
        if config.usesAnthropicCloud {
            let t = try await analyzeAnthropic(system: system, user: user,
                                               apiKey: config.anthropicApiKey ?? "",
                                               model: config.llmModel ?? "claude-sonnet-4-6")
            return (t, .anthropicCloud)
        }
        // Otherwise prefer Apple's on-device model when it can run.
        if AppleFoundationModel.isAvailable {
            let t = try await AppleFoundationModel.analyze(system: system, user: user)
            return (t, .appleOnDevice)
        }
        // Fall back to Ollama.
        let t = try await analyze(system: system, user: user,
                                  endpoint: ollamaEndpoint, model: ollamaModel)
        return (t, .ollama)
    }

    /// Back-compat text-only wrapper.
    public static func analyzeRouted(system: String, user: String, config: AppConfig,
                                     ollamaEndpoint: String, ollamaModel: String) async throws -> String {
        try await routed(system: system, user: user, config: config,
                         ollamaEndpoint: ollamaEndpoint, ollamaModel: ollamaModel).text
    }
}
