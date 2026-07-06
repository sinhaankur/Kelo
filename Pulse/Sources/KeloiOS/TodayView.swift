import SwiftUI
import PulseKit

/// The iOS home — the same "how am I set up today?" reading as the Mac, sized
/// for a phone and fed by Apple Health. One verdict, the reasons behind it,
/// and one obvious action: sync today from Health.
struct TodayView: View {
    @ObservedObject var model: KeloModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    heroCard
                    if let s = model.statusLine {
                        Label(s, systemImage: "info.circle")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .transition(.opacity)
                    }
                    signalSummary
                }
                .padding(16)
            }
            .navigationTitle("Kelo")
            .background(Color(.systemGroupedBackground))
        }
    }

    // MARK: hero

    private var heroCard: some View {
        let state = model.dayState
        let color = tint(state.standing)
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(color.opacity(0.15)).frame(width: 52, height: 52)
                    Image(systemName: icon(state.standing))
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(color)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("TODAY")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .tracking(2).foregroundStyle(.secondary)
                    Text(state.headline)
                        .font(.system(size: 21, weight: .semibold, design: .rounded))
                        .foregroundStyle(color)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }

            if state.thin {
                Text("Kelo reads your day from your sleep, resting heart rate and training in Apple Health, placed beside your money. Sync to see where you stand.")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Divider()
                VStack(alignment: .leading, spacing: 9) {
                    ForEach(state.reasons) { r in
                        HStack(spacing: 10) {
                            Image(systemName: r.icon)
                                .font(.system(size: 13))
                                .foregroundStyle(r.good ? Color.green : Color.orange)
                                .frame(width: 20)
                            Text(r.text).font(.callout)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                    }
                }
            }

            Button {
                Task { await model.syncFromHealth() }
            } label: {
                HStack {
                    if model.syncing {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "heart.text.square.fill")
                    }
                    Text(model.syncing ? "Syncing…" : "Sync today from Apple Health")
                        .fontWeight(.semibold)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(color)
            .disabled(model.syncing)

            if let t = model.lastSync {
                Text("last synced \(t.formatted(date: .omitted, time: .shortened))")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 18).fill(color.opacity(0.07)))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(color.opacity(0.22)))
    }

    // MARK: a compact read of the raw signals for the day

    private var signalSummary: some View {
        let today = model.todayHealth
        return VStack(alignment: .leading, spacing: 12) {
            Text("TODAY'S SIGNALS")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .tracking(2).foregroundStyle(.secondary)
            HStack(spacing: 12) {
                metric("Sleep", today?.sleepHours.map { String(format: "%.1fh", $0) }, "bed.double.fill")
                metric("Rest HR", today?.restingHR.map { String(format: "%.0f", $0) }, "heart.fill")
                metric("Training", today.map { "\($0.sessions.count)" }, "figure.run")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemGroupedBackground)))
    }

    private func metric(_ label: String, _ value: String?, _ icon: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: icon).font(.system(size: 15)).foregroundStyle(.secondary)
            Text(value ?? "—").font(.system(size: 18, weight: .semibold, design: .rounded))
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func tint(_ s: DayState.Standing) -> Color {
        switch s {
        case .strong: return .green
        case .steady: return .blue
        case .strained: return .orange
        }
    }
    private func icon(_ s: DayState.Standing) -> String {
        switch s {
        case .strong: return "checkmark.seal.fill"
        case .steady: return "circle.dashed"
        case .strained: return "exclamationmark.triangle.fill"
        }
    }
}
