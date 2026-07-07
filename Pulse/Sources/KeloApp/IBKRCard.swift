import SwiftUI
import KeloKit

/// The execution rails, connected to IBKR's official Client Portal Gateway —
/// hard-locked to the PAPER account (IDs starting DU). Real fills, real
/// spreads, zero real dollars. This is where the agent's calls and your
/// drafts become actual orders in the sandbox, with an in-app confirm and a
/// per-order ceiling. Going live later is a deliberate unlock, not a toggle.
struct IBKRCard: View {
    @ObservedObject var model: AppModel
    @State private var status: IBKRService.GatewayStatus? = nil
    @State private var checking = false
    @State private var placing = false
    @State private var lastResult = ""
    @State private var symbol = ""
    @State private var isBuy = true
    @State private var amountText = "250"

    private var gateway: String { model.config.ibkrGateway ?? "https://localhost:5000" }

    var body: some View {
        Card(title: "IBKR — PAPER EXECUTION", trailing: "official API · paper account only, enforced in code") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    statusChip
                    Button(checking ? "Checking…" : "Check connection") { check() }
                        .disabled(checking)
                    Spacer()
                }
                if let s = status, s.authenticated, s.isPaper, let account = s.accountId {
                    HStack(spacing: 8) {
                        Picker("", selection: $isBuy) {
                            Text("Buy").tag(true)
                            Text("Sell").tag(false)
                        }
                        .pickerStyle(.segmented).frame(width: 110).labelsHidden()
                        TextField("symbol (IBKR format, e.g. NVDA)", text: $symbol)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12, design: .monospaced))
                            .frame(width: 180)
                        TextField("amount", text: $amountText)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12, design: .monospaced))
                            .frame(width: 80)
                        Button(placing ? "Placing…" : "Place paper order…") {
                            place(account: account)
                        }
                        .disabled(placing || symbol.trimmingCharacters(in: .whitespaces).isEmpty
                                  || Double(amountText) == nil)
                        Spacer()
                    }
                    Text("whole shares · limit at last quote · \(usd(1_000)) per-order ceiling · confirmation before every order")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.tertiary)
                } else if status != nil {
                    Text("setup: download IBKR's Client Portal Gateway → run it → log in at https://localhost:5000 with your PAPER account (username usually starts 'du') → check again. Pulse refuses live accounts in code.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !lastResult.isEmpty {
                    Text(lastResult)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(lastResult.hasPrefix("✓") ? .green : .orange)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .task { check() }
    }

    private var statusChip: some View {
        let (text, color): (String, Color) = {
            guard let s = status else { return ("checking gateway…", .secondary) }
            if !s.authenticated { return ("gateway not connected", .orange) }
            guard let a = s.accountId else { return ("authenticated — no account visible", .orange) }
            return s.isPaper ? ("connected · PAPER \(a)", .green)
                             : ("⚠ \(a) is a LIVE account — Pulse will refuse orders", .red)
        }()
        return Text(text)
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.12)))
            .foregroundStyle(color)
    }

    private func check() {
        checking = true
        Task {
            let s = await IBKRService.status(gateway: gateway)
            await MainActor.run { status = s; checking = false }
        }
    }

    private func place(account: String) {
        let sym = symbol.trimmingCharacters(in: .whitespaces).uppercased()
        guard let amount = Double(amountText), amount > 0 else { return }
        placing = true; lastResult = ""
        Task {
            do {
                // Live-ish quote for the limit price + share math.
                guard let q = await QuoteService.fetch(symbol: sym) else {
                    throw IBKRService.IBKRError(message: "no quote for \(sym)")
                }
                let displayPrice = q.price * model.fx(q.currency)
                let qty = max(1, Int(amount / displayPrice))
                let notional = Double(qty) * displayPrice
                try IBKRService.validatePaperOrder(accountId: account, quantity: qty,
                                                   notional: notional)
                let side = isBuy ? "BUY" : "SELL"
                let confirmed = await MainActor.run { () -> Bool in
                    let alert = NSAlert()
                    alert.messageText = "Place PAPER order?"
                    alert.informativeText = "\(side) \(qty) × \(sym) ≈ \(usd(notional)) · limit \(String(format: "%.2f", q.price)) \(q.currency)\nAccount \(account) (paper). No real money moves."
                    alert.addButton(withTitle: "Place paper order")
                    alert.addButton(withTitle: "Cancel")
                    return alert.runModal() == .alertFirstButtonReturn
                }
                guard confirmed else {
                    await MainActor.run { placing = false }
                    return
                }
                let conid = try await IBKRService.findConid(symbol: sym, gateway: gateway)
                let placed = try await IBKRService.placePaperOrder(
                    gateway: gateway, accountId: account, conid: conid,
                    side: side, quantity: qty, limitPrice: q.price, notional: notional)
                await MainActor.run {
                    placing = false
                    lastResult = placed.orderId.map { "✓ paper order \($0) placed — \(side) \(qty) \(sym); it will fill like a real order, with zero real dollars" }
                        ?? "submitted: \(placed.messages.joined(separator: " · "))"
                }
            } catch {
                await MainActor.run {
                    placing = false
                    lastResult = "⚠ \(error.localizedDescription)"
                }
            }
        }
    }
}
