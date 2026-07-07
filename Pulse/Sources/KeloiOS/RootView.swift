import SwiftUI
import KeloKit

/// The phone/iPad information architecture. Everything in Kelo is related, so
/// the tabs aren't silos — Today is the unified read, and Body / Money are two
/// views INTO the same life. Touch-first, brand-consistent, one clear action
/// per screen.
struct RootView: View {
    @ObservedObject var model: KeloModel

    var body: some View {
        TabView {
            TodayView(model: model)
                .tabItem { Label("Today", systemImage: "sun.max.fill") }
            BodyView(model: model)
                .tabItem { Label("Body", systemImage: "heart.fill") }
            MoneyView(model: model)
                .tabItem { Label("Money", systemImage: "chart.line.uptrend.xyaxis") }
        }
        .tint(.keloAccent)
    }
}

// MARK: - Body tab — movement, training, DNA (the same domains as desktop)

struct BodyView: View {
    @ObservedObject var model: KeloModel

    private var prs: [PersonalRecord] { CrossFitStore.personalRecords(from: CrossFitStore.load()) }
    private var insights: [DNAInsight] {
        DNAParser.insights(genome: DNAStore.loadGenome(), table: DNATable.associations)
            .filter(\.carriesTrait)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    MoodPicker(model: model)
                    StreakChips(streaks: model.streaks)
                    if model.movementAvailable { movementCard }
                    if !prs.isEmpty { prsCard }
                    if !insights.isEmpty { dnaCard }
                }
                .padding(16)
            }
            .navigationTitle("Body")
            .background(Color.keloPaper.ignoresSafeArea())
        }
    }

    private var movementCard: some View {
        let m = model.movement
        return sectionCard("Movement") {
            HStack(spacing: 10) {
                Image(systemName: model.liveActivity.icon).font(.system(size: 18)).foregroundStyle(Color.keloAccent)
                Text(model.liveActivity == .unknown ? "Tap sync on Today to read movement" : "Right now: \(model.liveActivity.label)")
                    .font(.callout).foregroundStyle(Color.keloInk)
                Spacer()
            }
            if let m {
                HStack(spacing: 20) {
                    metric("\(m.steps)", "steps")
                    metric(String(format: "%.1f km", m.distanceKm), "distance")
                    metric("\(Int(m.sittingFraction * 100))%", "sitting",
                           tint: m.tooSedentary ? .keloBad : .keloGood)
                }
                if m.tooSedentary {
                    Label("You've been sitting most of the day — move.", systemImage: "figure.walk")
                        .font(.footnote).foregroundStyle(Color.keloBad)
                }
            }
        }
    }

    private var prsCard: some View {
        sectionCard("Personal records") {
            ForEach(prs.prefix(6)) { pr in
                HStack {
                    Image(systemName: "trophy.fill").foregroundStyle(Color.keloAccent)
                    Text(pr.name).fontWeight(.semibold)
                    Spacer()
                    Text(pr.best).font(.system(.body, design: .monospaced)).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var dnaCard: some View {
        sectionCard("DNA-informed · associations, not diagnoses") {
            ForEach(insights.prefix(6)) { i in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Image(systemName: "helix").foregroundStyle(Color.keloAccent)
                        Text(i.association.trait).fontWeight(.semibold)
                        Spacer()
                        Text(i.association.source).font(.caption2).foregroundStyle(.tertiary)
                    }
                    Text(i.association.note).font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func metric(_ v: String, _ l: String, tint: Color = .keloAccent) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(v).font(KeloFont.display(18, .semibold)).foregroundStyle(tint)
            Text(l).font(KeloFont.mono(10)).foregroundStyle(Color.keloMuted)
        }
    }
}

// MARK: - Money tab — the wealth read (mirrors the desktop, phone-sized)

struct MoneyView: View {
    @ObservedObject var model: KeloModel

    private var leak: (over: Bool, verdict: String) {
        let card = SpendService.scorecard(SpendStore.load())
        let totals = SpendService.monthTotals(SpendStore.load())
        return (totals.spent > totals.budgeted && totals.budgeted > 0, card.verdict)
    }
    private var benchmark: Benchmark.Result {
        let saved = model.portfolio.holdings.reduce(0.0) { $0 + $1.costBasis * $1.quantity }
        return Benchmark.compute(profile: ProfileStore.load(),
                                 annualExpenses: annualExpenses(), currentSaved: saved)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    leakCard
                    benchmarkCard
                }
                .padding(16)
            }
            .navigationTitle("Money")
            .background(Color.keloPaper.ignoresSafeArea())
        }
    }

    private var leakCard: some View {
        let l = leak
        return sectionCard("Where you're bleeding money") {
            HStack(spacing: 10) {
                Image(systemName: l.over ? "drop.fill" : "checkmark.seal.fill")
                    .foregroundStyle(l.over ? Color.keloBad : Color.keloGood)
                Text(l.verdict).font(.callout).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
        }
    }

    private var benchmarkCard: some View {
        let b = benchmark
        let color: Color = b.onTrack ? .keloGood : b.fractionOfTarget >= 0.5 ? .keloAccent : .keloBad
        return sectionCard("Where you should be") {
            HStack(alignment: .firstTextBaseline) {
                Text(usd(b.currentSaved)).font(KeloFont.display(24, .semibold)).foregroundStyle(color)
                Text("of ~\(usd(b.expenseBasedTarget))").font(.footnote).foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(b.fractionOfTarget * 100))%").font(KeloFont.mono(15, .semibold)).foregroundStyle(color)
            }
            ProgressView(value: min(1, b.fractionOfTarget)).tint(color)
        }
    }

    private func annualExpenses() -> Double {
        let totals = SpendService.monthTotals(SpendStore.load())
        let (d, dim) = SpendService.monthProgress()
        let frac = dim > 0 ? Double(d) / Double(dim) : 1
        return (frac > 0 ? totals.spent / frac : totals.spent) * 12
    }
}

// MARK: - Shared small building blocks

func sectionCard<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 12) {
        Eyebrow(title)
        content()
    }
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(RoundedRectangle(cornerRadius: 16).fill(Color.keloInk.opacity(0.04)))
    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.keloInk.opacity(0.06)))
}

func emptyHint(_ text: String) -> some View {
    Text(text).font(.callout).foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading).padding(16)
}
