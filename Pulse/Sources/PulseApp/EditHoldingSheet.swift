import SwiftUI
import PulseKit

/// Edit a position, add a new one, or record a partial sale by hand — the
/// portfolio is yours to change between broker exports. Writes straight to
/// portfolio.json and every card recomputes.
struct EditHoldingSheet: View {
    @ObservedObject var model: AppModel
    let holding: Holding?   // nil = add new
    @Environment(\.dismiss) private var dismiss

    @State private var symbol = ""
    @State private var quantity = ""
    @State private var costBasis = ""
    @State private var currency = "CAD"

    private var isEdit: Bool { holding != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(isEdit ? "Edit \(holding!.symbol)" : "Add position")
                .font(.system(size: 16, weight: .semibold))

            VStack(alignment: .leading, spacing: 10) {
                if !isEdit {
                    field("Symbol", "e.g. XEQT.TO, NVDA, BTC-CAD", $symbol)
                }
                field("Quantity", "shares / units", $quantity)
                field("Cost basis", "per share/unit, in the listing currency", $costBasis)
                if !isEdit {
                    HStack {
                        Text("Currency").frame(width: 90, alignment: .leading)
                            .font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                        Picker("", selection: $currency) {
                            Text("CAD").tag("CAD"); Text("USD").tag("USD")
                        }.pickerStyle(.segmented).frame(width: 140).labelsHidden()
                    }
                }
            }

            if isEdit {
                Text("To record a partial sale, lower the quantity. To mark it fully sold, use \"Sold / remove\" on the row.")
                    .font(.system(size: 10.5)).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button(isEdit ? "Save" : "Add") { save() }
                    .keyboardShortcut(.return)
                    .disabled(Double(quantity) == nil || Double(costBasis) == nil
                              || (!isEdit && symbol.trimmingCharacters(in: .whitespaces).isEmpty))
            }
        }
        .padding(18)
        .frame(width: 380)
        .onAppear {
            if let h = holding {
                quantity = num(h.quantity)
                costBasis = String(format: "%.4f", h.costBasis)
                currency = h.currency ?? "CAD"
            }
        }
    }

    private func field(_ label: String, _ placeholder: String, _ text: Binding<String>) -> some View {
        HStack {
            Text(label).frame(width: 90, alignment: .leading)
                .font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
            TextField(placeholder, text: text)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12, design: .monospaced))
        }
    }

    private func save() {
        guard let qty = Double(quantity), let cost = Double(costBasis) else { return }
        if let h = holding {
            model.updateHolding(h.symbol, quantity: qty, costBasis: cost)
        } else {
            model.addHolding(symbol: symbol, quantity: qty, costBasis: cost, currency: currency)
        }
        dismiss()
    }
}
