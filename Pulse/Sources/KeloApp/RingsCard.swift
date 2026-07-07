import SwiftUI
import KeloKit

/// The three rings on the desktop — Body · Money · Discipline — the same
/// glanceable "whole day in one image" as the phone and Watch.
struct RingsCard: View {
    @ObservedObject var model: AppModel

    private var rings: [Ring] {
        let totals = SpendService.monthTotals(SpendStore.load())
        let streaks = Discipline.streaks(health: model.health, mood: MoodStore.load())
        let today = model.todayHealth
        return Rings.all(movement: MovementStore.today(),
                         trainedToday: today?.didTrain ?? false,
                         spentThisMonth: totals.spent, budgeted: totals.budgeted,
                         streaks: streaks)
    }

    private func color(_ kind: Ring.Kind) -> Color {
        switch kind {
        case .body:       return Color(.sRGB, red: 0.90, green: 0.30, blue: 0.35, opacity: 1)
        case .money:      return .keloAccent
        case .discipline: return Color(.sRGB, red: 0.36, green: 0.66, blue: 0.52, opacity: 1)
        }
    }
    private func title(_ kind: Ring.Kind) -> String {
        switch kind { case .body: return "Body"; case .money: return "Money"; case .discipline: return "Discipline" }
    }

    var body: some View {
        Card(title: "YOUR DAY", trailing: "body · money · discipline") {
            HStack(spacing: 22) {
                ZStack {
                    ForEach(Array(rings.enumerated()), id: \.element.id) { i, ring in
                        let inset = CGFloat(i) * 26
                        ZStack {
                            Circle().stroke(color(ring.kind).opacity(0.18), lineWidth: 15)
                            Circle()
                                .trim(from: 0, to: max(0.001, ring.fraction))
                                .stroke(color(ring.kind), style: StrokeStyle(lineWidth: 15, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                        }
                        .padding(inset)
                    }
                }
                .frame(width: 150, height: 150)

                VStack(alignment: .leading, spacing: 14) {
                    ForEach(rings) { ring in
                        HStack(spacing: 10) {
                            Circle().fill(color(ring.kind)).frame(width: 10, height: 10)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(title(ring.kind))
                                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                    .tracking(1.5).foregroundStyle(.secondary)
                                Text(ring.label)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(ring.hasData ? .primary : .secondary)
                            }
                        }
                    }
                }
                Spacer()
            }
        }
    }
}
