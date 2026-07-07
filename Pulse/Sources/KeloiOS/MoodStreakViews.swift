import SwiftUI
import KeloKit

/// Tap-to-log mood — five faces, one tap. The honest, deliberate self-rating
/// (the face check-in on Today is the other, labelled, path). Shows today's
/// pick if already logged.
struct MoodPicker: View {
    @ObservedObject var model: KeloModel

    private let scale = [1, 2, 3, 4, 5]

    var body: some View {
        sectionCard("How are you today?") {
            HStack(spacing: 10) {
                ForEach(scale, id: \.self) { m in
                    let e = MoodEntry(date: "d", mood: m)
                    let selected = model.todayMood?.mood == m
                    Button {
                        model.logMood(m)
                    } label: {
                        VStack(spacing: 4) {
                            Text(e.emoji).font(.system(size: 26))
                            Text(e.label).font(.system(size: 9)).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 12)
                            .fill(selected ? Color.keloAccent.opacity(0.18) : Color.clear))
                        .overlay(RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(selected ? Color.keloAccent : Color.clear, lineWidth: 1.5))
                    }
                    .buttonStyle(.plain)
                }
            }
            if let t = model.todayMood, t.note == "from facial expression" {
                Text("today's mood is from a facial reading — tap to set it yourself")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
    }
}

/// Discipline streaks as chips — the "am I holding the line" read. A lit chip
/// = met today; the number is the current run.
struct StreakChips: View {
    let streaks: [Streak]

    var body: some View {
        sectionCard("Discipline") {
            HStack(spacing: 10) {
                ForEach(streaks) { s in
                    VStack(spacing: 5) {
                        Image(systemName: s.icon)
                            .font(.system(size: 16))
                            .foregroundStyle(s.metToday ? Color.keloAccent : Color.keloMuted)
                        Text("\(s.current)")
                            .font(KeloFont.display(20, .semibold))
                            .foregroundStyle(s.current > 0 ? Color.keloInk : Color.keloMuted)
                        Text(s.title).font(.system(size: 9)).foregroundStyle(.secondary)
                            .lineLimit(1).minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 12)
                        .fill(s.metToday ? Color.keloAccent.opacity(0.10) : Color.keloInk.opacity(0.03)))
                }
            }
            if let best = streaks.map(\.current).max(), best >= 3 {
                Text("\(best)-day streak going — keep it.")
                    .font(.caption).foregroundStyle(Color.keloAccent)
            }
        }
    }
}
