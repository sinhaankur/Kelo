import SwiftUI
import KeloKit

/// The body side, gathered: today's movement (sit/stand, steps), CrossFit PRs,
/// and DNA-informed notes — the health counterpart to the money cards. Each
/// section only shows when there's real data; DNA insights are always framed
/// as associations, never diagnoses.
struct BodyCard: View {
    @ObservedObject var model: AppModel

    private var movement: MovementDay? { MovementStore.today() }
    private var prs: [PersonalRecord] { CrossFitStore.personalRecords(from: CrossFitStore.load()) }
    private var insights: [DNAInsight] {
        DNAParser.insights(genome: DNAStore.loadGenome(), table: DNATable.associations)
    }

    var body: some View {
        Card(title: "BODY", trailing: "movement · training · DNA") {
            VStack(alignment: .leading, spacing: 14) {
                movementRow
                if !prs.isEmpty { prSection }
                if !insights.isEmpty { dnaSection }
                if movement == nil && prs.isEmpty && insights.isEmpty {
                    Text("log a workout, sync movement, or import your DNA (dna-raw.txt) to fill this in — Kelo reads your body, never invents it")
                        .font(.system(size: 11, design: .monospaced)).foregroundStyle(.tertiary)
                }
            }
        }
    }

    private var movementRow: some View {
        HStack(spacing: 16) {
            if let m = movement {
                stat("figure.walk", "\(m.steps)", "steps")
                stat("point.topleft.down.to.point.bottomright.curvepath", String(format: "%.1f km", m.distanceKm), "distance")
                stat(m.tooSedentary ? "figure.seated.side" : "figure.stand",
                     "\(Int(m.sittingFraction * 100))%", "sitting",
                     tint: m.tooSedentary ? .keloBad : .keloGood)
            } else {
                Text("no movement tracked today")
                    .font(.system(size: 11, design: .monospaced)).foregroundStyle(.tertiary)
            }
            Spacer()
        }
    }

    private var prSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("PERSONAL RECORDS")
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .tracking(1.5).foregroundStyle(.tertiary)
            ForEach(prs.prefix(4)) { pr in
                HStack(spacing: 8) {
                    Image(systemName: "trophy.fill").font(.system(size: 11)).foregroundStyle(Color.keloAccent).frame(width: 16)
                    Text(pr.name).font(.system(size: 12, weight: .semibold))
                    Text(pr.best).font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary)
                    Spacer()
                    Text(pr.date).font(.system(size: 10, design: .monospaced)).foregroundStyle(.tertiary)
                }
            }
        }
    }

    private var dnaSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("DNA-INFORMED")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .tracking(1.5).foregroundStyle(.tertiary)
                Text("associations, not diagnoses")
                    .font(.system(size: 9)).foregroundStyle(.tertiary)
            }
            ForEach(insights.filter(\.carriesTrait).prefix(5)) { i in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "helix").font(.system(size: 11)).foregroundStyle(Color.keloAccent).frame(width: 16)
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 6) {
                            Text(i.association.trait).font(.system(size: 12, weight: .semibold))
                            Text(i.association.source).font(.system(size: 8.5, design: .monospaced))
                                .foregroundStyle(.tertiary)
                        }
                        Text(i.association.note).font(.system(size: 10.5)).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func stat(_ icon: String, _ value: String, _ label: String, tint: Color = .keloAccent) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Image(systemName: icon).font(.system(size: 13)).foregroundStyle(tint)
            Text(value).font(.system(size: 15, weight: .semibold, design: .rounded))
            Text(label).font(.system(size: 9, design: .monospaced)).foregroundStyle(.tertiary)
        }
    }
}
