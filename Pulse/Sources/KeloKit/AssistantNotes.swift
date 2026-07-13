import Foundation

/// A user-authored note / thesis the assistant should remember — the OpenAlice
/// "tracked entities" idea, kept small and personal. You write these ("cutting
/// dining out", "bullish on AAPL — new iPhone cycle"); the assistant reads them
/// as context. They're YOUR words, never facts the model invented, and they
/// stay on the device with everything else.
public struct AssistantNote: Codable, Identifiable, Equatable {
    public let id: String
    public var text: String
    public let createdAt: String   // ISO date

    public init(id: String = UUID().uuidString, text: String, createdAt: String = isoDateString(Date())) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
    }
}

public enum NoteStore {
    /// How many notes the assistant carries into context (keeps the brief tight).
    public static let contextLimit = 5

    public static var fileURL: URL {
        Portfolio.dirURL.appendingPathComponent("assistant-notes.json")
    }

    public static func load(from url: URL = fileURL) -> [AssistantNote] {
        guard let data = try? Data(contentsOf: url),
              let list = try? JSONDecoder().decode([AssistantNote].self, from: data)
        else { return [] }
        return list
    }

    public static func save(_ notes: [AssistantNote], to url: URL = fileURL) {
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let out = try? enc.encode(notes) { try? out.write(to: url, options: .atomic) }
    }

    /// Add a note (trimmed, non-empty). Newest first.
    @discardableResult
    public static func add(_ text: String, to url: URL = fileURL) -> [AssistantNote] {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return load(from: url) }
        var all = load(from: url)
        all.insert(AssistantNote(text: t), at: 0)
        save(all, to: url)
        return all
    }

    public static func remove(id: String, from url: URL = fileURL) -> [AssistantNote] {
        let all = load(from: url).filter { $0.id != id }
        save(all, to: url)
        return all
    }

    /// The note lines the assistant reads (newest few), for Snapshot.notes.
    public static func contextLines(from url: URL = fileURL) -> [String] {
        Array(load(from: url).prefix(contextLimit)).map(\.text)
    }
}
