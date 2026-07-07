import SwiftUI
import KeloKit

/// Kelo's hero — one glanceable card that answers "how am I set up today?"
/// by fusing body signals with money. It sits at the very top of Overview,
/// above everything, because it's the reason the two halves live in one app.
///
/// Intuitiveness is the whole point: a single verdict line the eye lands on,
/// a short list of plain-language reasons (each a body OR money tailwind/
/// drag), and one obvious action — "Log today" — since Kelo never fills the
/// day in for you.
struct DayStateCard: View {
    @ObservedObject var model: AppModel
    @State private var logging = false

    var body: some View {
        let state = model.dayState
        let color = tint(state.standing)
        VStack(alignment: .leading, spacing: 12) {
            // ── Verdict row ────────────────────────────────────────────
            HStack(alignment: .center, spacing: 12) {
                ZStack {
                    Circle().fill(color.opacity(0.15)).frame(width: 44, height: 44)
                    Image(systemName: icon(state.standing))
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(color)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("TODAY")
                        .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                        .tracking(2).foregroundStyle(.secondary)
                    Text(state.headline)
                        .font(.system(size: 19, weight: .semibold, design: .rounded))
                        .foregroundStyle(color)
                }
                Spacer()
                Button {
                    logging = true
                } label: {
                    Label(model.todayHealth == nil ? "Log today" : "Update today",
                          systemImage: model.todayHealth == nil ? "plus.circle.fill" : "pencil.circle.fill")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(color)
                .help("Record today's sleep, resting HR, energy and training — Kelo never logs for you")
            }

            // ── Reasons: the body + money signals behind the verdict ───
            if state.thin {
                Text("Kelo reads your day from what you log — sleep, resting heart rate, how you feel, and today's training — placed beside your portfolio and spending. Log today to see where you stand.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Divider().opacity(0.5)
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(state.reasons) { r in
                        HStack(spacing: 9) {
                            Image(systemName: r.icon)
                                .font(.system(size: 12))
                                .foregroundStyle(r.good ? Color.green : Color.orange)
                                .frame(width: 18)
                            Text(r.text)
                                .font(.system(size: 12))
                                .foregroundStyle(.primary)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 14).fill(color.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(color.opacity(0.22)))
        .sheet(isPresented: $logging) {
            LogTodaySheet(model: model)
        }
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

/// The one place the user hands Kelo their body signals for the day. Minimal
/// and forgiving: every field optional, a day with only sleep filled in is a
/// valid day. Nothing is recorded until "Save today" is pressed.
private struct LogTodaySheet: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var sleep = ""
    @State private var restingHR = ""
    @State private var readiness = 6.0
    @State private var trained = false
    @State private var kind = "CrossFit"
    @State private var minutes = ""
    @State private var rpe = 7.0

    private let kinds = ["CrossFit", "Run", "Lift", "Row", "Ride", "Swim", "Mobility"]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Log today").font(.system(size: 16, weight: .semibold))
                Spacer()
                Text(Date().formatted(date: .abbreviated, time: .omitted))
                    .font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
            }
            .padding(16)
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    field("Sleep last night", unit: "hours", text: $sleep, placeholder: "7.5")
                    field("Resting heart rate", unit: "bpm", text: $restingHR, placeholder: "54")

                    VStack(alignment: .leading, spacing: 6) {
                        labelRow("Energy / readiness", value: "\(Int(readiness))/10")
                        Slider(value: $readiness, in: 1...10, step: 1)
                    }

                    Toggle(isOn: $trained.animation()) {
                        Text("I trained today").font(.system(size: 13, weight: .medium))
                    }
                    if trained {
                        VStack(alignment: .leading, spacing: 12) {
                            Picker("Type", selection: $kind) {
                                ForEach(kinds, id: \.self) { Text($0).tag($0) }
                            }
                            .pickerStyle(.menu)
                            field("Duration", unit: "min", text: $minutes, placeholder: "60")
                            VStack(alignment: .leading, spacing: 6) {
                                labelRow("How hard (RPE)", value: "\(Int(rpe))/10")
                                Slider(value: $rpe, in: 1...10, step: 1)
                            }
                        }
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.04)))
                    }
                }
                .padding(16)
            }

            Divider()
            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save today") { save() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
            .padding(16)
        }
        .frame(width: 380, height: trained ? 560 : 400)
    }

    private func field(_ label: String, unit: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            labelRow(label, value: unit)
            TextField(placeholder, text: text)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 13, design: .monospaced))
        }
    }
    private func labelRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label).font(.system(size: 13, weight: .medium))
            Spacer()
            Text(value).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
        }
    }

    private func save() {
        var sessions: [TrainingSession] = []
        if trained, let m = Int(minutes), m > 0 {
            sessions.append(TrainingSession(kind: kind, minutes: m, rpe: Int(rpe)))
        }
        model.logHealthDay(
            sleepHours: Double(sleep),
            restingHR: Double(restingHR),
            readiness: Int(readiness),
            sessions: sessions)
        dismiss()
    }
}
