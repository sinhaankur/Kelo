import SwiftUI
import KeloKit

/// "How much should I have saved by now?" — the counterpart to the leak-finder.
/// Leads with the location-honest nest-egg target (your real expenses minus the
/// state benefit you'll actually earn, ×25), shows the Fidelity salary-multiple
/// as a cross-check, and states plainly where you stand. Every assumption is
/// spelled out in the notes — a short work-permit stay earns little state
/// pension, and the card says so rather than handing you a median you won't get.
struct BenchmarkCard: View {
    @ObservedObject var model: AppModel

    var body: some View {
        let r = model.benchmark
        let color: Color = r.onTrack ? .green : r.fractionOfTarget >= 0.5 ? .orange : .red

        Card(title: "WHERE YOU SHOULD BE", trailing: "saving & investing benchmark") {
            VStack(alignment: .leading, spacing: 12) {
                // Standing
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(usd(r.currentSaved))
                        .font(.system(size: 26, weight: .semibold, design: .rounded))
                        .foregroundStyle(color)
                    Text("of ~\(usd(r.expenseBasedTarget)) target")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int(r.fractionOfTarget * 100))%")
                        .font(.system(size: 15, weight: .semibold, design: .monospaced))
                        .foregroundStyle(color)
                }
                ProgressView(value: min(1, r.fractionOfTarget)).tint(color)

                // The two methods, side by side.
                HStack(spacing: 10) {
                    methodTile(
                        title: "EXPENSE-BASED",
                        big: usd(r.expenseBasedTarget),
                        sub: "your spend − state benefit, ×25 (4% rule)")
                    if let salaryTarget = r.salaryBasedTarget, let m = r.salaryMultiple {
                        methodTile(
                            title: "SALARY-MULTIPLE",
                            big: usd(salaryTarget),
                            sub: String(format: "%.1f× salary (US rule of thumb)", m))
                    } else {
                        methodTile(title: "SALARY-MULTIPLE", big: "—",
                                   sub: "add age + salary to profile.json")
                    }
                }

                // Concrete actions
                VStack(alignment: .leading, spacing: 6) {
                    if let save = r.recommendedAnnualSaving {
                        line("target.circle", "Save ~\(usd(save))/yr (15% of income) toward it")
                    }
                    line("shield.lefthalf.filled", "Emergency fund: ~\(usd(r.emergencyFundTarget)) (6 months of expenses)")
                }

                // The honest assumptions — the work-permit caveat lives here.
                Divider().opacity(0.5)
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(Array(r.notes.enumerated()), id: \.offset) { _, note in
                        HStack(alignment: .top, spacing: 6) {
                            Text("·").foregroundStyle(.tertiary)
                            Text(note).font(.system(size: 10.5)).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }

    private func methodTile(title: String, big: String, sub: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(size: 9, weight: .semibold, design: .monospaced))
                .tracking(1.5).foregroundStyle(.tertiary)
            Text(big).font(.system(size: 17, weight: .semibold, design: .rounded))
            Text(sub).font(.system(size: 9.5)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.04)))
    }

    private func line(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 12)).foregroundStyle(.secondary).frame(width: 18)
            Text(text).font(.system(size: 11.5))
            Spacer(minLength: 0)
        }
    }
}
