import SwiftUI
import PulseKit

/// Where "the dividend covers the losses" meets arithmetic: what each payer
/// actually sent over the trailing year, whether the payout itself is
/// growing or decaying, and the price damage in the same row. A stable
/// payout on a stable price is income; a collapsing payout on a collapsing
/// price is your own capital coming back on a schedule.
struct IncomeCard: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Card(title: "INCOME", trailing: "TTM distributions · payout trend = last 3 payments vs prior 3") {
            if let r = model.incomeReport {
                if r.positions.isEmpty {
                    Text("no distributions received in the trailing year (top positions checked)")
                        .font(.system(size: 11, design: .monospaced)).foregroundStyle(.tertiary)
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 14) {
                            Text("≈ \(usd(r.totalMonthly))/month")
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                            if r.decayingMonthly > 0 {
                                Text("of which \(usd(r.decayingMonthly))/mo comes from DECAYING payers — that part is not income, it's capital on an installment plan")
                                    .font(.system(size: 10.5, design: .monospaced))
                                    .foregroundStyle(.orange)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer()
                        }
                        Grid(alignment: .trailing, horizontalSpacing: 14, verticalSpacing: 8) {
                            GridRow {
                                head("PAYER", leading: true); head("$/MO"); head("TTM")
                                head("VALUE"); head("PRICE P/L"); head("PAYOUT TREND")
                            }
                            ForEach(r.positions.prefix(12), id: \.symbol) { p in
                                GridRow {
                                    Button {
                                        model.outlookTarget = AppModel.OutlookTarget(symbol: p.symbol)
                                    } label: {
                                        HStack(spacing: 3) {
                                            Text(p.symbol)
                                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                            Image(systemName: "chevron.right")
                                                .font(.system(size: 7)).foregroundStyle(.tertiary)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                    .gridColumnAlignment(.leading)
                                    Text(usd(p.monthlyEstimate)).cell()
                                    Text(usd(p.ttmIncome)).cell().foregroundStyle(.secondary)
                                    Text(usd(p.valueNow)).cell()
                                    Text(usd(p.pricePL)).cell()
                                        .foregroundStyle(p.pricePL >= 0 ? Color.green : Color.red)
                                    trendPill(p)
                                }
                            }
                        }
                    }
                }
            } else {
                Text("checking distribution history for your top positions…")
                    .font(.system(size: 11, design: .monospaced)).foregroundStyle(.tertiary)
            }
        }
    }

    private func trendPill(_ p: IncomePosition) -> some View {
        let label = p.payoutTrendPct.map { String(format: "%+.0f%%", $0) } ?? "—"
        return Text(p.decaying ? "\(label) decaying" : label)
            .font(.system(size: 10.5, weight: .medium, design: .monospaced))
            .padding(.horizontal, 7).padding(.vertical, 2.5)
            .background(Capsule().fill(p.decaying ? Color.red.opacity(0.15)
                                       : Color.green.opacity(0.10)))
            .foregroundStyle(p.decaying ? Color.red : Color.green)
    }

    private func head(_ s: String, leading: Bool = false) -> some View {
        Text(s).font(.system(size: 9, weight: .medium, design: .monospaced))
            .tracking(1).foregroundStyle(.tertiary)
            .gridColumnAlignment(leading ? .leading : .trailing)
    }
}
