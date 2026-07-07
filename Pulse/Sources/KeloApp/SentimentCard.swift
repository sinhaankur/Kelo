import SwiftUI
import KeloKit

/// Global sentiment from sourced numbers only — VIX with its standard bands,
/// world index breadth, crypto Fear & Greed, and (with a Finnhub key in
/// config.json) the latest market headlines. No invented mood scores.
struct SentimentCard: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Card(title: "GLOBAL SENTIMENT", trailing: "VIX · breadth · crypto F&G · Finnhub") {
            if let s = model.sentiment {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        if let v = s.vix, let band = s.vixBand {
                            tile("VIX", String(format: "%.1f", v), band, vixColor(v))
                        }
                        if !s.indices.isEmpty {
                            tile("WORLD BREADTH", "\(s.upCount)/\(s.indices.count)", "markets up today",
                                 s.upCount * 2 >= s.indices.count ? .green : .red)
                        }
                        if let fg = s.cryptoFearGreed, let label = s.cryptoFearGreedLabel {
                            tile("CRYPTO F&G", "\(fg)", label.lowercased(), fgColor(fg))
                        }
                        Spacer()
                    }
                    if !s.indices.isEmpty {
                        HStack(spacing: 8) {
                            ForEach(s.indices.indices, id: \.self) { i in
                                let idx = s.indices[i]
                                HStack(spacing: 4) {
                                    Text(idx.name)
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                    Text(String(format: "%+.1f%%", idx.dayPct))
                                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                                        .foregroundStyle(idx.dayPct >= 0 ? Color.green : Color.red)
                                }
                                .padding(.horizontal, 6).padding(.vertical, 3)
                                .background(Capsule().fill(Color.primary.opacity(0.05)))
                            }
                            Spacer()
                        }
                    }
                    // World dynamics — where geopolitics shows up in numbers:
                    // gold + oil (stress), the dollar, the US 10-year yield.
                    if !s.macro.isEmpty {
                        HStack(spacing: 8) {
                            Text("WORLD")
                                .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                                .tracking(1).foregroundStyle(.tertiary)
                            ForEach(s.macro.indices, id: \.self) { i in
                                let m = s.macro[i]
                                HStack(spacing: 4) {
                                    Text(m.name)
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                    Text(m.levelLabel)
                                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                                    Text(String(format: "%+.1f%%", m.dayPct))
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(m.dayPct >= 0 ? Color.green : Color.red)
                                }
                                .padding(.horizontal, 6).padding(.vertical, 3)
                                .background(Capsule().fill(Color.primary.opacity(0.05)))
                            }
                            Spacer()
                        }
                    }
                    if !s.headlines.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(s.headlines.indices, id: \.self) { i in
                                let h = s.headlines[i]
                                HStack(alignment: .firstTextBaseline, spacing: 6) {
                                    Text("·").foregroundStyle(.tertiary)
                                    Text(h.title)
                                        .font(.system(size: 11)).foregroundStyle(.secondary)
                                        .lineLimit(1)
                                    Text("\(h.source) · \(relative(h.date))")
                                        .font(.system(size: 9.5, design: .monospaced))
                                        .foregroundStyle(.tertiary)
                                        .layoutPriority(1)
                                }
                            }
                        }
                    } else if model.config.finnhubApiKey == nil {
                        Text("add finnhubApiKey to config.json for market headlines")
                            .font(.system(size: 10, design: .monospaced)).foregroundStyle(.tertiary)
                    }
                }
            } else {
                Text("fetching global sentiment…")
                    .font(.system(size: 11, design: .monospaced)).foregroundStyle(.tertiary)
            }
        }
    }

    private func vixColor(_ v: Double) -> Color {
        switch v {
        case ..<15: return .green
        case ..<20: return .secondary
        case ..<30: return .orange
        default: return .red
        }
    }

    // Fear & Greed: low = fear (red-ish), high = greed (green) — the index's
    // own orientation, not an opinion.
    private func fgColor(_ v: Int) -> Color {
        switch v {
        case ..<25: return .red
        case ..<45: return .orange
        case ..<55: return .secondary
        case ..<75: return .green
        default: return .mint
        }
    }

    private func relative(_ d: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f.localizedString(for: d, relativeTo: Date())
    }

    private func tile(_ label: String, _ value: String, _ detail: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 8.5, weight: .medium, design: .monospaced))
                .tracking(1).foregroundStyle(.tertiary)
            Text(value).font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundStyle(color)
            Text(detail).font(.system(size: 9.5, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
    }
}
