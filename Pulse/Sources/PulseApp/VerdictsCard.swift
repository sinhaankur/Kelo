import SwiftUI
import PulseKit

/// The committed recommendation block — a direct call, the reasoning, and
/// the one honest test. No hedging: an EXIT with two decay markers is not
/// ambiguous, and the app says so.
struct RecommendationBox: View {
    let headline: String
    let detail: String
    let test: String
    let color: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.right.circle.fill")
                    .font(.system(size: 12)).foregroundStyle(color)
                Text(headline).font(.system(size: 12, weight: .bold))
            }
            Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(test).font(.system(size: 11, weight: .medium, design: .default))
                .italic().foregroundStyle(color)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 9).fill(color.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(color.opacity(0.22)))
    }
}

/// A single decay marker with a tappable "why". The plain line stays inline;
/// the (i) opens a popover with the exact rule, threshold, and reasoning —
/// so no label is ever a mystery.
struct MarkerChip: View {
    let marker: PositionVerdict.Marker
    @State private var showWhy = false
    var body: some View {
        HStack(spacing: 4) {
            Text(marker.text)
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                showWhy.toggle()
            } label: {
                Image(systemName: "info.circle")
                    .font(.system(size: 9)).foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .help("Why this flag fired")
            .popover(isPresented: $showWhy, arrowEdge: .trailing) {
                Text(marker.explanation)
                    .font(.system(size: 12))
                    .frame(width: 320, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(14)
            }
        }
    }
}

/// A committed call for every position — EXIT CANDIDATE / REVIEW / HOLD —
/// with the specific decay markers that fired. Direction without ambiguity,
/// grounded only in what is observably true, never in price prediction.
struct VerdictsCard: View {
    @ObservedObject var model: AppModel
    @State private var showAllExits = false

    var body: some View {
        let verdicts = model.verdicts
        let exits = verdicts.filter { $0.call == .exit }
        let reviews = verdicts.filter { $0.call == .review }
        let holds = verdicts.filter { $0.call == .hold }

        Card(title: "VERDICTS", trailing: "every position, a plain call · condition-based, not prediction") {
            if verdicts.isEmpty {
                Text("waiting for quotes + timelines…")
                    .font(.system(size: 11, design: .monospaced)).foregroundStyle(.tertiary)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        summaryTile("EXIT CANDIDATES", "\(exits.count)",
                                    usd(exits.reduce(0) { $0 + $1.valueAtStake }), .red)
                        summaryTile("REVIEW", "\(reviews.count)",
                                    usd(reviews.reduce(0) { $0 + $1.valueAtStake }), .orange)
                        summaryTile("HOLD", "\(holds.count)",
                                    usd(holds.reduce(0) { $0 + $1.valueAtStake }), .green)
                        Spacer()
                    }
                    if !exits.isEmpty {
                        VStack(alignment: .leading, spacing: 7) {
                            ForEach((showAllExits ? exits : Array(exits.prefix(8))), id: \.symbol) { v in
                                verdictRow(v, color: .red)
                            }
                            if exits.count > 8 {
                                Button(showAllExits ? "show fewer" : "show all \(exits.count) exit candidates") {
                                    showAllExits.toggle()
                                }
                                .font(.system(size: 11))
                            }
                        }
                        // The committed recommendation — direct, no hedge.
                        if let first = exits.first {
                            RecommendationBox(
                                headline: "Recommendation: sell the exit candidates",
                                detail: first.recommendation,
                                test: first.buyItTodayVerdict,
                                color: .red)
                        }
                    }
                    if !reviews.isEmpty {
                        DisclosureGroup("\(reviews.count) positions marked REVIEW — one marker fired") {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(reviews.prefix(20), id: \.symbol) { v in
                                    verdictRow(v, color: .orange)
                                }
                                if reviews.count > 20 {
                                    Text("… and \(reviews.count - 20) more")
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            .padding(.top, 4)
                        }
                        .font(.system(size: 11.5))
                    }
                    // Patience is the game — for the RIGHT assets. The holds
                    // get the other half of the message.
                    if !holds.isEmpty, exits.isEmpty {
                        RecommendationBox(
                            headline: "Recommendation: hold, and be patient",
                            detail: holds[0].recommendation,
                            test: "Time compounds a healthy position. Don't sell what's working because something else is loud.",
                            color: .green)
                    } else if !holds.isEmpty {
                        Text("The \(holds.count) HOLDs are where patience pays — leave them alone while you clear the exits. Time compounds healthy positions; it only bleeds broken ones.")
                            .font(.system(size: 10.5)).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private func verdictRow(_ v: PositionVerdict, color: Color) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Button {
                model.outlookTarget = AppModel.OutlookTarget(symbol: v.symbol)
            } label: {
                HStack(spacing: 3) {
                    Text(v.symbol)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(color)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 7, weight: .semibold)).foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)
            .frame(minWidth: 86, alignment: .leading)
            // Each marker is its own info chip — tap the (i) for the exact
            // rule and why it matters.
            VStack(alignment: .leading, spacing: 3) {
                ForEach(v.markers.indices, id: \.self) { i in
                    MarkerChip(marker: v.markers[i])
                }
            }
            Spacer()
            Text(usd(v.valueAtStake))
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(.tertiary)
        }
    }

    private func summaryTile(_ label: String, _ count: String, _ value: String, _ color: Color) -> some View {
        summaryTileImpl(label, count, value, color)
    }

    private func summaryTileImpl(_ label: String, _ count: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 8.5, weight: .medium, design: .monospaced))
                .tracking(1).foregroundStyle(.tertiary)
            HStack(spacing: 6) {
                Text(count).font(.system(size: 15, weight: .bold, design: .monospaced))
                    .foregroundStyle(color)
                Text(value).font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
    }
}
