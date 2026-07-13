import SwiftUI
import KeloKit

/// "Ask Kelo" — the opt-in assistant surface. It answers questions about YOUR
/// day from your own real data. Off until you open it; when a local model is
/// running it interprets the data, otherwise Kelo answers from the numbers
/// directly. Honest about which happened and whether anything left the device.
@MainActor
final class AskKeloModel: ObservableObject {
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
    @Published var suggestions = [
        "How am I doing?",
        "Am I over budget this month?",
        "How are my savings tracking?",
        "What should I focus on today?",
    ]

    /// Build the live snapshot from the on-device stores. Portfolio value needs
    /// live quotes when the phone has fetched them (KeloModel.refreshQuotes),
    /// otherwise the portfolio is honestly omitted.
    private func snapshot(_ model: KeloModel) -> AssistantService.Snapshot {
        let cfg = AppConfig.load()
        let cur = cfg.displayCurrency ?? "USD"
        let total = PortfolioValuation.totalValue(model.portfolio, quotes: model.quotes, fxRates: model.fxRates)
        let hasQuotes = total > 0
        return .fromStores(
            currency: cur,
            portfolioValue: hasQuotes ? total : nil,
            portfolioDayChangePct: PortfolioValuation.dayChangePct(model.portfolio, quotes: model.quotes, fxRates: model.fxRates),
            currentSaved: hasQuotes ? total : nil,
            topHoldings: hasQuotes ? PortfolioValuation.topHoldings(model.portfolio, quotes: model.quotes, fxRates: model.fxRates) : []
        )
    }

    func clear() { transcript = [] }

    func ask(_ model: KeloModel, _ q: String? = nil) {
        let query = (q ?? question).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !running, !query.isEmpty else { return }
        running = true
        question = ""
        // Prior turns become the follow-up context BEFORE we append this one.
        let history = transcript.map { AssistantService.Turn(role: $0.role, text: $0.text) }
        transcript.append(Message(role: .user, text: query))
        let snap = snapshot(model)
        let cfg = AppConfig.load()
        let endpoint = cfg.llmEndpoint ?? "http://localhost:11434"
        let modelName = cfg.llmModel ?? "qwen2.5:7b"
        let cloud = cfg.usesAnthropicCloud

        Task {
            // Prefer the most private engine that works: Apple on-device (unless
            // the user opted into cloud) → Ollama if reachable → local answer.
            // Hoist the async ping out of the boolean (autoclosures can't await).
            let ollamaUp = await LlmService.ping(endpoint: endpoint)
            let llm: ((String, String) async throws -> String)?
            var reportCloud = false
            if cloud || AppleFoundationModel.isAvailable || ollamaUp {
                reportCloud = cloud
                llm = { sys, usr in
                    try await LlmService.routed(system: sys, user: usr, config: cfg,
                                                ollamaEndpoint: endpoint, ollamaModel: modelName).text
                }
            } else {
                llm = nil   // no model available → honest local answer
            }

            let result = await AssistantService.answer(question: query, snapshot: snap,
                                                       history: history, llm: llm, usedCloud: reportCloud)
            await MainActor.run {
                self.transcript.append(Message(role: .assistant, text: result.text,
                                               source: result.source, usedCloud: result.usedCloud))
                self.running = false
            }
        }
    }
}

struct AskKeloView: View {
    @ObservedObject var model: KeloModel
    @StateObject private var vm = AskKeloModel()
    // Off by default — the assistant is strictly opt-in. Persists across launches.
    @AppStorage("assistantEnabled") private var enabled = false

    var body: some View {
        sectionCard("Ask Kelo") {
          if !enabled {
            enablePrompt
          } else {
          VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                Text("Ask about your day. Kelo answers from your own numbers — nothing leaves this device unless you've turned on a cloud model.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Toggle("", isOn: $enabled).labelsHidden().tint(.keloAccent)
            }

            HStack {
                engineLabel
                Spacer()
                if !vm.transcript.isEmpty {
                    Button("Clear") { vm.clear() }
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }

            // Suggestion chips — shown to start the conversation.
            if vm.transcript.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(vm.suggestions, id: \.self) { s in
                            Button { vm.ask(model, s) } label: {
                                Text(s)
                                    .font(.system(size: 12, weight: .medium))
                                    .padding(.horizontal, 12).padding(.vertical, 7)
                                    .background(Color.keloAccent.opacity(0.12), in: Capsule())
                                    .foregroundStyle(Color.keloAccent)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            // Transcript — the running conversation.
            ForEach(vm.transcript) { m in
                messageBubble(m)
            }

            if vm.running {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Reading your day…").font(.footnote).foregroundStyle(.secondary)
                }
            }

            // Free-text ask — a follow-up continues the thread.
            HStack(spacing: 8) {
                TextField(vm.transcript.isEmpty ? "Ask anything about your day…" : "Ask a follow-up…",
                          text: $vm.question)
                    .textFieldStyle(.roundedBorder)
                    .submitLabel(.send)
                    .onSubmit { vm.ask(model) }
                Button { vm.ask(model) } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(vm.question.isEmpty ? Color.secondary : Color.keloAccent)
                }
                .disabled(vm.question.isEmpty || vm.running)
            }

            // Notes — the couple of things you've told Kelo to remember.
            AssistantNotesInline()
          }
          .animation(.easeInOut(duration: 0.2), value: vm.transcript.count)
          .animation(.easeInOut(duration: 0.2), value: vm.running)
          }
        }
        // Fetch quotes once the assistant is on + there are holdings, so the
        // phone can ground in the portfolio like the Mac. Symbols only leave
        // the device (public market data) — never positions.
        .task(id: enabled) {
            if enabled && model.quotes.isEmpty { await model.refreshQuotes() }
        }
    }

    /// One message in the transcript — your question or Kelo's grounded reply.
    @ViewBuilder private func messageBubble(_ m: AskKeloModel.Message) -> some View {
        if m.role == .user {
            Text(m.text)
                .font(.callout).foregroundStyle(Color.keloInk)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Color.keloInk.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                .frame(maxWidth: .infinity, alignment: .trailing)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text(m.text).font(.callout).foregroundStyle(Color.keloInk)
                    .fixedSize(horizontal: false, vertical: true)
                sourceLabel(m.source, m.usedCloud)
            }
            .padding(12)
            .background(Color.keloAccent.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// The opt-in gate shown when the assistant is off. Explicit, honest,
    /// off by default — nothing runs until you turn it on.
    private var enablePrompt: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("An opt-in assistant that reads your own Kelo data — day, movement, spending, savings — to answer “how am I doing?”. It never acts, and stays on your device unless you enable a cloud model.")
                .font(.footnote).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                enabled = true
            } label: {
                Label("Turn on Ask Kelo", systemImage: "sparkles")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).tint(.keloAccent)
        }
    }

    /// Which engine will answer — set once when the view appears.
    @ViewBuilder private var engineLabel: some View {
        let (icon, text): (String, String) = {
            if AppleFoundationModel.isAvailable {
                return ("apple.logo", "On-device Apple Intelligence")
            }
            return ("lock.laptopcomputer", "Answers from your data · local model if running")
        }()
        Label(text, systemImage: icon)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.secondary)
    }

    /// Honest provenance — where an answer came from, and whether it left the device.
    @ViewBuilder private func sourceLabel(_ source: AssistantService.Source?, _ usedCloud: Bool) -> some View {
        switch source {
        case .model:
            Label(usedCloud
                  ? "Interpreted by a cloud model — this data left your device"
                  : "Interpreted by your on-device model",
                  systemImage: usedCloud ? "cloud" : "lock.laptopcomputer")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(usedCloud ? Color.orange : .secondary)
        case .localData:
            Label("Answered from your data — no model, fully on device",
                  systemImage: "lock.fill")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
        case .none:
            EmptyView()
        }
    }
}

/// A compact notes editor inline in the Ask Kelo card — add/remove the couple
/// of things you want Kelo to remember. Persisted on device via NoteStore.
struct AssistantNotesInline: View {
    @State private var notes: [AssistantNote] = NoteStore.load()
    @State private var draft = ""
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { expanded.toggle() } label: {
                Label(expanded ? "Notes Kelo remembers" : "Notes Kelo remembers (\(notes.count))",
                      systemImage: expanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            if expanded {
                ForEach(notes) { n in
                    HStack(spacing: 8) {
                        Text("• \(n.text)").font(.footnote).foregroundStyle(Color.keloInk)
                        Spacer()
                        Button { notes = NoteStore.remove(id: n.id) } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }.buttonStyle(.plain)
                    }
                }
                HStack(spacing: 8) {
                    TextField("Remember something… (e.g. cutting dining out)", text: $draft)
                        .textFieldStyle(.roundedBorder).font(.footnote)
                        .onSubmit(add)
                    Button(action: add) { Image(systemName: "plus.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(Color.keloAccent)
                        .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func add() {
        let t = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        notes = NoteStore.add(t)
        draft = ""
    }
}
