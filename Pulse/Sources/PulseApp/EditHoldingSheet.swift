import SwiftUI
import PulseKit

/// Add, edit, or record a partial sale of a position — the relevant
/// broker questions, asked plainly: what, how many, at what cost, when.
/// The "when" makes the whole timeline analysis exact instead of estimated.
/// Writes straight to portfolio.json and every card recomputes.
struct EditHoldingSheet: View {
    @ObservedObject var model: AppModel
    let holding: Holding?   // nil = add new
    @Environment(\.dismiss) private var dismiss

    @State private var symbol = ""
    @State private var quantity = ""
    @State private var costBasis = ""
    @State private var currency = "CAD"
    @State private var knowsDate = false
    @State private var acquired = Date()

    private var isEdit: Bool { holding != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(isEdit ? "Edit \(holding!.symbol)" : "Add a position")
                    .font(.system(size: 17, weight: .semibold))
                Text(isEdit ? "Change what you hold — lower the quantity to record a partial sale."
                            : "What did you buy, how much, at what price, and when?")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 12) {
                if !isEdit {
                    field("Ticker", "e.g. XEQT.TO · NVDA · BTC-CAD", $symbol,
                          help: "Use the exchange-qualified symbol: .TO for TSX, .V for TSX-V, none for US, -CAD/-USD for crypto.")
                }
                field("Quantity", "shares / units", $quantity,
                      help: "How many shares or units you hold.")
                field("Cost per unit", "your average buy price", $costBasis,
                      help: "What you paid per share/unit, in the listing's currency — not the total.")
                if !isEdit {
                    labeled("Currency") {
                        Picker("", selection: $currency) {
                            Text("CAD").tag("CAD"); Text("USD").tag("USD")
                        }.pickerStyle(.segmented).frame(width: 130).labelsHidden()
                    }
                }
                labeled("Date bought") {
                    HStack(spacing: 8) {
                        Toggle("I know it", isOn: $knowsDate)
                            .toggleStyle(.checkbox).font(.system(size: 11))
                        if knowsDate {
                            DatePicker("", selection: $acquired, in: ...Date(),
                                       displayedComponents: .date)
                                .labelsHidden().datePickerStyle(.compact)
                        } else {
                            Text("Pulse will estimate it from price history")
                                .font(.system(size: 10.5)).foregroundStyle(.tertiary)
                        }
                    }
                }
            }

            HStack {
                if isEdit {
                    Button("Sold — remove", role: .destructive) {
                        model.removeHolding(holding!.symbol); dismiss()
                    }
                }
                Spacer()
                Button("Cancel") { dismiss() }
                Button(isEdit ? "Save" : "Add position") { save() }
                    .keyboardShortcut(.return).buttonStyle(.borderedProminent)
                    .disabled(Double(quantity) == nil || Double(costBasis) == nil
                              || (!isEdit && symbol.trimmingCharacters(in: .whitespaces).isEmpty))
            }
        }
        .padding(20)
        .frame(width: 420)
        .onAppear {
            if let h = holding {
                quantity = num(h.quantity)
                costBasis = String(format: "%.4f", h.costBasis)
                currency = h.currency ?? "CAD"
                if let a = h.acquired, let d = parseISODate(a) {
                    knowsDate = true; acquired = d
                }
            }
        }
    }

    private func field(_ label: String, _ placeholder: String, _ text: Binding<String>, help: String) -> some View {
        labeled(label) {
            VStack(alignment: .leading, spacing: 2) {
                TextField(placeholder, text: text)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
                Text(help).font(.system(size: 9.5)).foregroundStyle(.tertiary)
            }
        }
    }

    private func labeled<Content: View>(_ label: String, @ViewBuilder _ content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(label).frame(width: 92, alignment: .leading)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .padding(.top, 4)
            content()
            Spacer(minLength: 0)
        }
    }

    private func save() {
        guard let qty = Double(quantity), let cost = Double(costBasis) else { return }
        let dateStr = knowsDate ? isoDateString(acquired) : nil
        if let h = holding {
            model.updateHolding(h.symbol, quantity: qty, costBasis: cost, acquired: dateStr)
        } else {
            model.addHolding(symbol: symbol, quantity: qty, costBasis: cost,
                             currency: currency, acquired: dateStr)
        }
        dismiss()
    }
}
