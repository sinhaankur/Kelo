import SwiftUI
import KeloKit

/// The live macro backdrop — inflation, the cost of money, how much money
/// exists, the dollar, the 10-year — from the St. Louis Fed (FRED), keyless.
/// These are the forces the per-stock Macro Lens explains; here they're the
/// actual current readings, so "why and how" is grounded in today's numbers.
struct MacroCard: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Card(title: "MACRO BACKDROP", trailing: "live from FRED (US Federal Reserve data) · keyless") {
            if let m = model.macroData, !m.readings.isEmpty {
                VStack(alignment: .leading, spacing: 9) {
                    ForEach(m.readings.indices, id: \.self) { i in
                        let r = m.readings[i]
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(r.label)
                                .font(.system(size: 12, weight: .medium))
                                .frame(width: 130, alignment: .leading)
                            Text(valueLabel(r))
                                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                .foregroundStyle(.primary)
                                .frame(width: 90, alignment: .leading)
                            Text(r.note)
                                .font(.system(size: 10.5)).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer()
                        }
                    }
                    Text("open any stock's Outlook to see how these forces reach that specific company (its sector + country).")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.tertiary).padding(.top, 2)
                }
            } else {
                Text("fetching macro data…")
                    .font(.system(size: 11, design: .monospaced)).foregroundStyle(.tertiary)
            }
        }
    }

    private func valueLabel(_ r: MacroData.Reading) -> String {
        if let yoy = r.yoyPct {
            return String(format: "%+.1f%% YoY", yoy)
        }
        return r.unit == "%" ? String(format: "%.2f%%", r.value)
             : r.unit == "$B" ? String(format: "$%.0fB", r.value)
             : String(format: "%.1f", r.value)
    }
}

