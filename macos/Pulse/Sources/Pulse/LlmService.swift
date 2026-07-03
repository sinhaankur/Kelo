import Foundation

struct LlmError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// Local LLM bridge — Ollama's chat API on localhost (or any host the user
/// sets). Nothing is sent to a cloud service; the analysis stays on-machine.
enum LlmService {
    private struct ChatResponse: Decodable {
        struct Message: Decodable { let content: String }
        let message: Message?
        let error: String?
    }

    static func analyze(system: String, user: String,
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
}
