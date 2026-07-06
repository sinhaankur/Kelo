import SwiftUI
import PulseKit

/// "Am I bleeding money?" answered bluntly. Leads with whether you're over
/// this month and by how much, names the single biggest leak (the one thing
/// to fix), then ranks the worst categories with pace warnings — burning too
/// fast even while still under the cap.
///
/// All of this is Kelo's existing, tested SpendService logic; the card only
/// presents it. Same honesty as the rest of the app: it shows the cost, it
/// never moves money.
struct LeakCard: View {
    @ObservedObject var model: AppModel

    private var data: SpendData { SpendStore.load() }

    var body: some View {
        let d = data
        let totals = SpendService.monthTotals(d)
        let card = SpendService.scorecard(d)
        let statuses = SpendService.budgetStatuses(d)
        let over = totals.spent > totals.budgeted && totals.budgeted > 0
        // The bleed: over-budget categories, worst first; then "burning hot"
        // categories that aren't over yet but are on pace to be.
        let bleeding = statuses.filter { $0.over && $0.limit > 0 }
        let hot = statuses.filter { $0.paceHot && !$0.over }
        let color: Color = over ? .red : bleeding.isEmpty ? .green : .orange

        return VStack(alignment: .leading, spacing: 12) {
            // headline
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: over ? "drop.fill"
                      : bleeding.isEmpty ? "checkmark.seal.fill" : "drop.triangle")
                    .font(.system(size: 22)).foregroundStyle(color)
                VStack(alignment: .leading, spacing: 3) {
                    Text(headline(over: over, totals: totals, bleeding: bleeding.count))
                        .font(.system(size: 15, weight: .semibold))
                    Text(card.verdict)
                        .font(.system(size: 11.5)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }

            if totals.budgeted == 0 {
                Text("no budgets set — add category budgets to spending.json and Kelo will show exactly where the money's going")
                    .font(.system(size: 11, design: .monospaced)).foregroundStyle(.tertiary)
            } else if bleeding.isEmpty && hot.isEmpty {
                Text("nothing over budget and nothing burning hot. The bleed, if any, is elsewhere — check the big uncategorised rows below.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            } else {
                Divider().opacity(0.5)
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(bleeding, id: \.category) { s in
                        leakRow(icon: "arrow.up.right", color: .red,
                                category: s.category,
                                detail: "\(usd(s.spent)) spent · \(usd(s.spent - s.limit)) over the \(usd(s.limit)) cap")
                    }
                    ForEach(hot, id: \.category) { s in
                        leakRow(icon: "flame.fill", color: .orange,
                                category: s.category,
                                detail: "\(Int(s.fraction * 100))% of budget gone, on pace to blow it before month-end")
                    }
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(color.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(color.opacity(0.22)))
    }

    private func headline(over: Bool, totals: (spent: Double, budgeted: Double), bleeding: Int) -> String {
        if totals.budgeted == 0 { return "Where's the money going?" }
        if over {
            return "You're bleeding money — \(usd(totals.spent - totals.budgeted)) over budget this month"
        }
        if bleeding > 0 {
            return "\(bleeding) categor\(bleeding == 1 ? "y is" : "ies are") over budget"
        }
        return "Not bleeding — spending is within plan"
    }

    private func leakRow(icon: String, color: Color, category: String, detail: String) -> some View {
        HStack(spacing: 9) {
            Image(systemName: icon).font(.system(size: 12)).foregroundStyle(color).frame(width: 18)
            Text(category).font(.system(size: 12.5, weight: .semibold))
            Text(detail).font(.system(size: 11.5)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}
