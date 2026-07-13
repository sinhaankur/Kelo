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
    @Published var question = ""
    @Published var answer = ""
    @Published var source: AssistantService.Source? = nil
    @Published var usedCloud = false
    @Published var running = false

    let suggestions = [
        "How am I doing?",
        "Am I over budget?",
        "How are my savings tracking?",
        "How's my portfolio doing today?",
    ]

    /// Snapshot from live app + on-device stores. The Mac has real quotes, so
    /// the portfolio value + top movers are included (grounded, not invented).
    private func snapshot(_ model: AppModel) -> AssistantService.Snapshot {
        let cur = model.config.displayCurrency ?? "USD"
        let total = model.totalValue
        // Top holdings by value, with today's move — real numbers only.
        let top = model.portfolio.holdings
            .sorted { model.holdingValue($0) > model.holdingValue($1) }
            .prefix(4)
            .map { h -> String in
                let pct = model.quotes[h.symbol]?.dayChangePct
                return pct.map { "\(h.symbol) \(String(format: "%+.1f%%", $0))" } ?? h.symbol
            }
        // Portfolio day change: value-weighted from the holdings we have quotes for.
        let dayPct = portfolioDayChangePct(model)
        let saved = total   // what they actually hold, for the savings benchmark

        return .fromStores(
            currency: cur,
            portfolioValue: total > 0 ? total : nil,
            portfolioDayChangePct: dayPct,
            currentSaved: total > 0 ? saved : nil,
            topHoldings: Array(top)
        )
    }

    private func portfolioDayChangePct(_ model: AppModel) -> Double? {
        var weighted = 0.0, base = 0.0
        for h in model.portfolio.holdings {
            guard let q = model.quotes[h.symbol] else { continue }
            let val = model.holdingValue(h)
            weighted += val * q.dayChangePct
            base += val
        }
        return base > 0 ? weighted / base : nil
    }

    func ask(_ model: AppModel, _ q: String? = nil) {
        let query = (q ?? question).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !running else { return }
        running = true; answer = ""; source = nil
        let snap = snapshot(model)
        let cfg = model.config
        let endpoint = cfg.llmEndpoint ?? "http://localhost:11434"
        let modelName = cfg.llmModel ?? "qwen2.5:7b"
        let cloud = cfg.usesAnthropicCloud
        usedCloud = cloud

        Task {
            // Prefer the most private engine that works: Apple on-device (unless
            // the user opted into cloud) → Ollama if reachable → local answer.
            // Hoist the async ping out of the boolean (autoclosures can't await).
            let ollamaUp = await LlmService.ping(endpoint: endpoint)
            let llm: ((String, String) async throws -> String)?
            if cloud || AppleFoundationModel.isAvailable || ollamaUp {
                llm = { sys, usr in
                    try await LlmService.routed(system: sys, user: usr, config: cfg,
                                                ollamaEndpoint: endpoint, ollamaModel: modelName).text
                }
            } else {
                llm = nil
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
                    Toggle("", isOn: $enabled).labelsHidden().controlSize(.mini)
                }
                // Suggestions
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

                // Free-text ask
                HStack(spacing: 8) {
                    TextField("Ask about your day…", text: $vm.question)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { vm.ask(model) }
                    Button { vm.ask(model) } label: {
                        Image(systemName: "arrow.up.circle.fill").font(.system(size: 20))
                    }
                    .buttonStyle(.plain)
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
                        Text(vm.answer).font(.callout).fixedSize(horizontal: false, vertical: true)
                        sourceLabel
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.accentColor.opacity(0.06)))
                }
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

    @ViewBuilder private var sourceLabel: some View {
        switch vm.source {
        case .model:
            Label(vm.usedCloud ? "Interpreted by a cloud model — this data left your Mac"
                               : "Interpreted by your on-device model",
                  systemImage: vm.usedCloud ? "cloud" : "lock.laptopcomputer")
                .font(.system(size: 10)).foregroundStyle(vm.usedCloud ? .orange : .secondary)
        case .localData:
            Label("Answered from your data — no model, fully on device", systemImage: "lock.fill")
                .font(.system(size: 10)).foregroundStyle(.secondary)
        case .none:
            EmptyView()
        }
    }
}
