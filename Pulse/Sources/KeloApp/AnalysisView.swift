import SwiftUI
import AppKit
import UniformTypeIdentifiers
import KeloKit

/// Screenshot → on-device OCR → local LLM analysis, grounded in REAL fetched
/// market data (indices + the user's portfolio) so the model interprets
/// numbers instead of inventing them. Private end to end.
@MainActor
final class AnalysisModel: ObservableObject {
    @Published var image: NSImage? = nil
    @Published var status: String = ""
    @Published var running = false
    @Published var output: String = ""
    @AppStorage("llmEndpoint") var endpoint = "http://localhost:11434"
    @AppStorage("llmModel") var model = "qwen2.5:7b"

    func run(portfolio: AppModel) {
        guard !running else { return }
        running = true
        output = ""
        // A screenshot is optional context, not a gate — analysis of the
        // live portfolio + market numbers must work on its own.
        status = image != nil ? "reading screenshot (on-device OCR)…" : "fetching real market context…"
        Task {
            let ocr: String
            if let image {
                ocr = await OcrService.recognizeText(in: image)
            } else {
                ocr = ""
            }
            await MainActor.run { self.status = "fetching real market context…" }

            // Ground truth: index stats (30d) + the user's live portfolio.
            let indexQuotes = await QuoteService.fetchAll(symbols: ["^GSPC", "^IXIC", "^DJI"])
            let names = ["^GSPC": "S&P 500", "^IXIC": "Nasdaq", "^DJI": "Dow"]
            let indexContext = indexQuotes.values
                .sorted { $0.symbol < $1.symbol }
                .map { q -> String in
                    let lo = q.closes.min() ?? q.price
                    let hi = q.closes.max() ?? q.price
                    let mo = q.closes.first.map { f in (q.price - f) / f * 100 } ?? 0
                    return "\(names[q.symbol] ?? q.symbol): \(Int(q.price)) (today \(String(format: "%+.2f", q.dayChangePct))%, 30d \(String(format: "%+.1f", mo))%, 30d range \(Int(lo))–\(Int(hi)))"
                }
                .joined(separator: "\n")

            let holdings = await MainActor.run {
                portfolio.portfolio.holdings.map { h -> String in
                    let q = portfolio.quotes[h.symbol]
                    let pl = portfolio.holdingValue(h) - portfolio.holdingCost(h)
                    return "\(h.symbol): qty \(num(h.quantity)), cost \(usd(h.costBasis * portfolio.fx(h.currency))), now \(q.map { usd(portfolio.displayPrice($0)) } ?? "?"), P/L \(usd(pl))"
                }.joined(separator: "\n")
            }

            // Since-invested timelines (dates marked "est." were detected
            // from price history, not stated by the user).
            let timelines = await MainActor.run {
                portfolio.portfolio.holdings.compactMap { h -> String? in
                    guard let t = portfolio.timelines[h.symbol] else { return nil }
                    let ann = t.annualizedPct.map { String(format: "%+.1f%%/y", $0) } ?? "n/a"
                    let bench = t.benchmarkPct.map { String(format: "%+.1f%%", $0) } ?? "n/a"
                    return "\(h.symbol): invested \(t.acquiredLabel)\(t.estimated ? " (est.)" : ""), held \(t.heldLabel), return \(String(format: "%+.1f%%", t.totalReturnPct)), annualized \(ann), S&P same window \(bench)"
                }.joined(separator: "\n")
            }

            // Global sentiment — sourced gauges + recent headlines when a
            // Finnhub key is configured.
            let sentimentContext = await MainActor.run { () -> String in
                guard let s = portfolio.sentiment else { return "(not fetched)" }
                var lines = [s.summary]
                if !s.indices.isEmpty {
                    lines.append(s.indices.map { "\($0.name) \(String(format: "%+.1f%%", $0.dayPct))" }
                        .joined(separator: ", "))
                }
                if !s.macro.isEmpty {
                    lines.append("world dynamics: " + s.macro
                        .map { "\($0.name) \($0.levelLabel) (\(String(format: "%+.1f%%", $0.dayPct)) today)" }
                        .joined(separator: ", "))
                }
                for h in s.headlines.prefix(5) {
                    lines.append("headline [\(h.source)]: \(h.title)")
                }
                for sym in portfolio.holdingsNews.keys.sorted() {
                    for h in portfolio.holdingsNews[sym] ?? [] {
                        lines.append("holding news [\(sym), \(h.source)]: \(h.title)")
                    }
                }
                return lines.joined(separator: "\n")
            }

            let system = """
            You are a careful market analysis assistant running fully locally on the user's Mac. \
            Use ONLY the data provided — real index statistics, global sentiment, position timelines, \
            the user's portfolio, and (when present) OCR text of a screenshot. Structure your answer as: \
            1) WHAT THE SCREENSHOT SHOWS (only if screenshot text was provided; otherwise skip this section). \
            2) MARKET CONTEXT (interpret the provided index/sentiment/world numbers; do not invent history you weren't given). \
            3) RIGHT / WRONG (what looks healthy vs concerning in their portfolio, referencing the numbers). \
            4) WORTH CONSIDERING (2–3 observations framed as things to look into — never directives to buy or sell). \
            If the OCR text is too garbled to identify anything, say so plainly. \
            End with exactly: "Not financial advice."
            """
            let user = """
            === SCREENSHOT OCR ===
            \(ocr.isEmpty ? "(no screenshot provided)" : ocr)

            === REAL INDEX DATA (fetched now) ===
            \(indexContext)

            === MY PORTFOLIO (live) ===
            \(holdings)

            === POSITION TIMELINES (est. = detected, not stated) ===
            \(timelines.isEmpty ? "(none)" : timelines)

            === GLOBAL SENTIMENT (sourced: VIX, index breadth, alternative.me, Finnhub) ===
            \(sentimentContext)
            """

            let cloud = portfolio.config.usesAnthropicCloud
            await MainActor.run {
                self.status = cloud ? "analyzing with Anthropic (cloud — context leaves this machine)…"
                                    : "analyzing with \(self.model) (local)…"
            }
            do {
                let text = try await LlmService.analyzeRouted(system: system, user: user,
                                                              config: portfolio.config,
                                                              ollamaEndpoint: endpoint,
                                                              ollamaModel: model)
                await MainActor.run { self.output = text; self.status = ""; self.running = false }
            } catch {
                await MainActor.run {
                    self.output = ""
                    self.status = "⚠ \(error.localizedDescription)"
                    self.running = false
                }
            }
        }
    }
}

struct AnalysisCard: View {
    @ObservedObject var app: AppModel
    @StateObject private var model = AnalysisModel()
    @State private var dropActive = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("ANALYZE")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .tracking(2).foregroundStyle(.secondary)
                Spacer()
                TextField("endpoint", text: model.$endpoint)
                    .textFieldStyle(.plain).font(.system(size: 10, design: .monospaced))
                    .frame(width: 150).multilineTextAlignment(.trailing)
                    .foregroundStyle(.tertiary)
                TextField("model", text: model.$model)
                    .textFieldStyle(.plain).font(.system(size: 10, design: .monospaced))
                    .frame(width: 90).multilineTextAlignment(.trailing)
                    .foregroundStyle(.tertiary)
            }

            HStack(spacing: 12) {
                dropZone
                VStack(alignment: .leading, spacing: 6) {
                    Text("Analyze your live numbers as-is — or add context: scan the screen (⇧⌘S over stocks in your browser) or drop/paste a screenshot.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                    Text(app.config.usesAnthropicCloud
                         ? "⚠ Cloud model configured (Anthropic): the analysis context — including your positions — leaves this machine over TLS. Switch llmProvider to \"ollama\" in config.json for fully on-device."
                         : "OCR runs on this Mac (Vision). Analysis runs on your local model, grounded in live portfolio, sentiment, world gauges and timelines. Nothing leaves the machine.")
                        .font(.system(size: 10))
                        .foregroundStyle(app.config.usesAnthropicCloud ? AnyShapeStyle(.orange) : AnyShapeStyle(.tertiary))
                    HStack(spacing: 8) {
                        Button("Scan screen") { scanScreen() }
                            .keyboardShortcut("s", modifiers: [.command, .shift])
                            .disabled(model.running)
                        Button("Paste") { pasteImage() }
                        Button(model.running ? "Analyzing…" : "Analyze") { model.run(portfolio: app) }
                            .keyboardShortcut(.return, modifiers: .command)
                            .disabled(model.running)
                    }
                    if !model.status.isEmpty {
                        Text(model.status).font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.orange)
                    }
                }
                Spacer()
            }

            if !model.output.isEmpty {
                ScrollView {
                    Text(model.output)
                        .font(.system(size: 12))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 260)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06)))
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.08)))
    }

    private var dropZone: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(dropActive ? Color.accentColor : Color.primary.opacity(0.2),
                              style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))
            if let img = model.image {
                Image(nsImage: img).resizable().scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 6)).padding(4)
            } else {
                VStack(spacing: 4) {
                    Image(systemName: "photo.badge.plus").font(.system(size: 18))
                    Text("drop image").font(.system(size: 9, design: .monospaced))
                }
                .foregroundStyle(.tertiary)
            }
        }
        .frame(width: 130, height: 84)
        .onDrop(of: [UTType.image, UTType.fileURL], isTargeted: $dropActive) { providers in
            loadDrop(providers); return true
        }
    }

    private func loadDrop(_ providers: [NSItemProvider]) {
        for p in providers {
            if p.canLoadObject(ofClass: NSImage.self) {
                _ = p.loadObject(ofClass: NSImage.self) { obj, _ in
                    if let img = obj as? NSImage {
                        Task { @MainActor in model.image = img }
                    }
                }
                return
            }
            p.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, _ in
                if let data = item as? Data,
                   let url = URL(dataRepresentation: data, relativeTo: nil),
                   let img = NSImage(contentsOf: url) {
                    Task { @MainActor in model.image = img }
                }
            }
        }
    }

    private func pasteImage() {
        if let img = NSImage(pasteboard: .general) { model.image = img }
    }

    /// Scan the screen directly: the system's interactive region selector
    /// (crosshair — drag over the stocks in your browser), then the captured
    /// region flows straight into OCR → analysis. First use may require
    /// granting Pulse Screen Recording permission (System Settings → Privacy).
    private func scanScreen() {
        let path = NSTemporaryDirectory() + "pulse-scan-\(UUID().uuidString).png"
        model.status = "drag a region over your stocks (Esc to cancel)…"
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        proc.arguments = ["-i", "-x", path] // interactive region select, silent
        Task.detached {
            try? proc.run()
            proc.waitUntilExit()
            let data = try? Data(contentsOf: URL(fileURLWithPath: path))
            try? FileManager.default.removeItem(atPath: path)
            await MainActor.run {
                if let data, let img = NSImage(data: data) {
                    model.image = img
                    model.status = ""
                    model.run(portfolio: app) // scan → read, no extra click
                } else {
                    model.status = "scan cancelled — or grant Pulse Screen Recording in System Settings → Privacy & Security"
                }
            }
        }
    }
}
