import SwiftUI
import KeloKit

/// "Ask Kelo" — the opt-in assistant surface. It answers questions about YOUR
/// day from your own real data. Off until you open it; when a local model is
/// running it interprets the data, otherwise Kelo answers from the numbers
/// directly. Honest about which happened and whether anything left the device.
@MainActor
final class AskKeloModel: ObservableObject {
    @Published var question = ""
    @Published var answer: String = ""
    @Published var source: AssistantService.Source? = nil
    @Published var usedCloud = false
    @Published var running = false
    @Published var suggestions = [
        "How am I doing?",
        "Am I over budget this month?",
        "How are my savings tracking?",
        "What should I focus on today?",
    ]

    /// Build the live snapshot from the on-device stores. Portfolio value needs
    /// live quotes (not on the phone yet), so it's omitted — the assistant just
    /// won't mention it, which is the honest behaviour.
    private func snapshot() -> AssistantService.Snapshot {
        let cfg = AppConfig.load()
        return .fromStores(currency: cfg.displayCurrency ?? "USD")
    }

    func ask(_ q: String? = nil) {
        let query = (q ?? question).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !running else { return }
        running = true
        answer = ""
        source = nil
        let snap = snapshot()
        let cfg = AppConfig.load()
        let endpoint = cfg.llmEndpoint ?? "http://localhost:11434"
        let model = cfg.llmModel ?? "qwen2.5:7b"
        let cloud = cfg.usesAnthropicCloud
        usedCloud = cloud

        Task {
            // Decide the LLM closure: a real routed call if a provider is set up,
            // otherwise nil → AssistantService answers deterministically.
            let llm: ((String, String) async throws -> String)?
            if cloud {
                llm = { sys, usr in
                    try await LlmService.analyzeRouted(system: sys, user: usr, config: cfg,
                                                       ollamaEndpoint: endpoint, ollamaModel: model)
                }
            } else if await LlmService.ping(endpoint: endpoint) {
                llm = { sys, usr in
                    try await LlmService.analyze(system: sys, user: usr, endpoint: endpoint, model: model)
                }
            } else {
                llm = nil   // no model reachable → honest local answer
            }

            let result = await AssistantService.answer(question: query, snapshot: snap,
                                                       llm: llm, usedCloud: cloud)
            await MainActor.run {
                self.answer = result.text
                self.source = result.source
                self.usedCloud = result.usedCloud
                self.running = false
            }
        }
    }
}

struct AskKeloView: View {
    @StateObject private var vm = AskKeloModel()

    var body: some View {
        sectionCard("Ask Kelo") {
          VStack(alignment: .leading, spacing: 14) {
            Text("Ask about your day. Kelo answers from your own numbers — nothing leaves this device unless you've turned on a cloud model.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            // Suggestion chips — one tap to a grounded answer.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(vm.suggestions, id: \.self) { s in
                        Button { vm.ask(s) } label: {
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

            // Free-text ask.
            HStack(spacing: 8) {
                TextField("Ask anything about your day…", text: $vm.question)
                    .textFieldStyle(.roundedBorder)
                    .submitLabel(.send)
                    .onSubmit { vm.ask() }
                Button { vm.ask() } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(vm.question.isEmpty ? Color.secondary : Color.keloAccent)
                }
                .disabled(vm.question.isEmpty || vm.running)
            }

            if vm.running {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Reading your day…").font(.footnote).foregroundStyle(.secondary)
                }
            }

            if !vm.answer.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(vm.answer)
                        .font(.callout)
                        .foregroundStyle(Color.keloInk)
                        .fixedSize(horizontal: false, vertical: true)
                    sourceLabel
                }
                .padding(12)
                .background(Color.keloAccent.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                .transition(.opacity)
            }
          }
          .animation(.easeInOut(duration: 0.2), value: vm.answer)
          .animation(.easeInOut(duration: 0.2), value: vm.running)
        }
    }

    /// Honest provenance — where the answer came from, and whether it left the device.
    @ViewBuilder private var sourceLabel: some View {
        switch vm.source {
        case .model:
            Label(vm.usedCloud
                  ? "Interpreted by a cloud model — this data left your device"
                  : "Interpreted by your on-device model",
                  systemImage: vm.usedCloud ? "cloud" : "lock.laptopcomputer")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(vm.usedCloud ? Color.orange : .secondary)
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
