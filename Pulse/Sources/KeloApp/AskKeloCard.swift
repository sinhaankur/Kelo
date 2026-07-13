import SwiftUI
import KeloKit

/// "Ask Kelo" on the Mac — the opt-in life assistant. It answers "how am I
/// doing?" from your own real data (day-state, rings, spending, savings, and —
/// on the Mac, where live quotes exist — your portfolio). When a local model
/// is running it interprets the numbers; otherwise Kelo answers from them
/// directly. Honest about the source and whether anything left the device.
///
/// This is distinct from the market AnalysisView (the wealth analyst); this is
/// the unified body+money "you" read.
@MainActor
final class AskKeloCardModel: ObservableObject {
    struct Message: Identifiable {
        let id = UUID()
        let role: AssistantService.Turn.Role
        let text: String
        var source: AssistantService.Source? = nil
        var usedCloud = false
    }

    @Published var question = ""
    @Published var transcript: [Message] = []
    @Published var running = false

    let suggestions = [
        "How am I doing?",
        "Am I over budget?",
        "How are my savings tracking?",
        "How's my portfolio doing today?",
    ]

    func clear() { transcript = [] }

    /// Snapshot from live app + on-device stores, using the SAME shared
    /// valuation the phone uses (PortfolioValuation) — one source of truth,
    /// grounded, never invented. The Mac has real quotes so the portfolio +
    /// top movers are included.
    private func snapshot(_ model: AppModel) -> AssistantService.Snapshot {
        let cur = model.config.displayCurrency ?? "USD"
        let q = model.quotes, fx = model.fxRates
        let total = PortfolioValuation.totalValue(model.portfolio, quotes: q, fxRates: fx)
        let has = total > 0
        return .fromStores(
            currency: cur,
            portfolioValue: has ? total : nil,
            portfolioDayChangePct: PortfolioValuation.dayChangePct(model.portfolio, quotes: q, fxRates: fx),
            currentSaved: has ? total : nil,   // what they actually hold, for the benchmark
            topHoldings: has ? PortfolioValuation.topHoldings(model.portfolio, quotes: q, fxRates: fx) : []
        )
    }

    func ask(_ model: AppModel, _ q: String? = nil) {
        let query = (q ?? question).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !running, !query.isEmpty else { return }
        running = true; question = ""
        let history = transcript.map { AssistantService.Turn(role: $0.role, text: $0.text) }
        transcript.append(Message(role: .user, text: query))
        let snap = snapshot(model)
        let cfg = model.config
        let endpoint = cfg.llmEndpoint ?? "http://localhost:11434"
        let modelName = cfg.llmModel ?? "qwen2.5:7b"
        let cloud = cfg.usesAnthropicCloud

        Task {
            // Prefer the most private engine that works: Apple on-device (unless
            // the user opted into cloud) → Ollama if reachable → local answer.
            // Hoist the async ping out of the boolean (autoclosures can't await).
            let ollamaUp = await LlmService.ping(endpoint: endpoint)
            // Capture the ACTUAL backend so the label reflects reality.
            let backend = BackendBox()
            let llm: ((String, String) async throws -> String)?
            if cloud || AppleFoundationModel.isAvailable || ollamaUp {
                llm = { sys, usr in
                    let r = try await LlmService.routed(system: sys, user: usr, config: cfg,
                                                        ollamaEndpoint: endpoint, ollamaModel: modelName)
                    backend.value = r.backend
                    return r.text
                }
            } else {
                llm = nil
            }
            let result = await AssistantService.answer(question: query, snapshot: snap,
                                                       history: history, llm: llm)
            let leftDevice = backend.value == .anthropicCloud
            await MainActor.run {
                self.transcript.append(Message(role: .assistant, text: result.text,
                                               source: result.source,
                                               usedCloud: result.source == .model && leftDevice))
                self.running = false
            }
        }
    }
}

/// A tiny box so the routing closure can report which backend actually answered.
private final class BackendBox: @unchecked Sendable { var value: LlmService.Backend? = nil }

struct AskKeloCard: View {
    @ObservedObject var model: AppModel
    @StateObject private var vm = AskKeloCardModel()
    // Off by default — strictly opt-in, persisted.
    @AppStorage("assistantEnabled") private var enabled = false

    var body: some View {
        Card(title: "ASK KELO", trailing: enabled ? "how am I doing? · from your own data" : "opt-in") {
            if !enabled {
                VStack(alignment: .leading, spacing: 10) {
                    Text("An opt-in assistant that reads your own Kelo data — day, movement, spending, savings, portfolio — to answer “how am I doing?”. It never acts, and stays on this Mac unless you enable a cloud model.")
                        .font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button { enabled = true } label: {
                        Label("Turn on Ask Kelo", systemImage: "sparkles")
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    engineLabel
                    Spacer()
                    if !vm.transcript.isEmpty {
                        Button("Clear") { vm.clear() }.font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Toggle("", isOn: $enabled).labelsHidden().controlSize(.mini)
                }

                // Suggestions — to start the conversation.
                if vm.transcript.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(vm.suggestions, id: \.self) { s in
                            Button { vm.ask(model, s) } label: {
                                Text(s).font(.system(size: 11, weight: .medium))
                                    .padding(.horizontal, 10).padding(.vertical, 6)
                                    .background(Color.accentColor.opacity(0.12), in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                // Transcript
                ForEach(vm.transcript) { m in messageBubble(m) }

                if vm.running {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Reading your day…").font(.footnote).foregroundStyle(.secondary)
                    }
                }

                // Free-text ask — a follow-up continues the thread.
                HStack(spacing: 8) {
                    TextField(vm.transcript.isEmpty ? "Ask about your day…" : "Ask a follow-up…",
                              text: $vm.question)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { vm.ask(model) }
                    Button { vm.ask(model) } label: {
                        Image(systemName: "arrow.up.circle.fill").font(.system(size: 20))
                    }
                    .buttonStyle(.plain)
                    .disabled(vm.question.isEmpty || vm.running)
                }

                // Notes — the couple of things you've told Kelo to remember.
                AssistantNotesInlineMac()
            }
            }
        }
    }

    /// Which engine will answer.
    @ViewBuilder private var engineLabel: some View {
        let (icon, text): (String, String) = AppleFoundationModel.isAvailable
            ? ("apple.logo", "On-device Apple Intelligence")
            : ("lock.laptopcomputer", "From your data · local model if running")
        Label(text, systemImage: icon).font(.system(size: 10)).foregroundStyle(.secondary)
    }

    @ViewBuilder private func messageBubble(_ m: AskKeloCardModel.Message) -> some View {
        if m.role == .user {
            Text(m.text).font(.callout)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.06)))
                .frame(maxWidth: .infinity, alignment: .trailing)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text(m.text).font(.callout).fixedSize(horizontal: false, vertical: true)
                sourceLabel(m.source, m.usedCloud)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.accentColor.opacity(0.06)))
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder private func sourceLabel(_ source: AssistantService.Source?, _ usedCloud: Bool) -> some View {
        switch source {
        case .model:
            Label(usedCloud ? "Interpreted by a cloud model — this data left your Mac"
                            : "Interpreted by your on-device model",
                  systemImage: usedCloud ? "cloud" : "lock.laptopcomputer")
                .font(.system(size: 10)).foregroundStyle(usedCloud ? .orange : .secondary)
        case .localData:
            Label("Answered from your data — no model, fully on device", systemImage: "lock.fill")
                .font(.system(size: 10)).foregroundStyle(.secondary)
        case .none:
            EmptyView()
        }
    }
}

/// macOS inline notes editor for the Ask Kelo card — persisted via NoteStore.
struct AssistantNotesInlineMac: View {
    @State private var notes: [AssistantNote] = NoteStore.load()
    @State private var draft = ""
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button { expanded.toggle() } label: {
                Label("Notes Kelo remembers (\(notes.count))",
                      systemImage: expanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            if expanded {
                ForEach(notes) { n in
                    HStack {
                        Text("• \(n.text)").font(.footnote)
                        Spacer()
                        Button { notes = NoteStore.remove(id: n.id) } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }.buttonStyle(.plain)
                    }
                }
                HStack(spacing: 8) {
                    TextField("Remember something…", text: $draft)
                        .textFieldStyle(.roundedBorder).font(.footnote).onSubmit(add)
                    Button(action: add) { Image(systemName: "plus.circle.fill") }
                        .buttonStyle(.plain)
                        .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func add() {
        let t = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        notes = NoteStore.add(t); draft = ""
    }
}
